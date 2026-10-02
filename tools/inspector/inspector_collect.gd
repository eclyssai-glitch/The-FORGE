extends RefCounted
## DEVELOPMENT ONLY (tools/inspector is excluded from the export: `tools/*` in exclude_filter).
## Pure collection of a JSON-ready snapshot of the running game for the dev inspector
## (dev_inspector.gd; docs/BUILD.md, "Inspector de desenvolvimento"). No class_name on purpose:
## nothing here may enter the global class cache of the exported game; load it by path.
##
## collect(tree, context) -> Dictionary with (keys sorted by the JSON writer):
##   format, frame, time, motion_time, movie, sim_time, sim_status, sim_speed, scenario, phase,
##   mode, selected, hud, cinematic, call_line_open, quality, viewport, camera, context,
##   tree             {path: "Class"} of every node (capped at MAX_TREE_NODES; "truncated")
##   nodes            relevant nodes: groups entity_* and dev_inspect, Skeleton3D, AnimationTree,
##                    AnimationPlayer, Camera3D, BoneAttachment3D (class, script, groups, visible,
##                    global transform) — capped at MAX_RELEVANT
##   skeletons        per Skeleton3D: bones by name (index, parent, enabled, rest, pose = the input
##                    pose before modifiers, final/final_global = after the frame's
##                    SkeletonModifier3D chain when the caller tracked it, world position) and the
##                    modifiers (class, active, influence, own properties, resolved targets, status)
##   animation_trees  per AnimationTree: active, root class, every non-object `parameters/*` value
##                    and every state machine playback (current node, travel path, positions, fade)
##   animation_players per AnimationPlayer: current/assigned animation, position, playing, speed
##   sections         one entry per node of group dev_inspect with `inspect_state() -> Dictionary`
##                    (key = inspect_section() when present, else the node name; "_path" added)
##   errors           contract violations found while collecting (never fatal)
## Values are made JSON-safe (vectors -> arrays, transforms -> {pos, quat, euler_deg, scale}, nodes
## -> paths, resources -> class/path) and floats are rounded to DECIMALS so diffs show real changes.

const FORMAT := "korium-inspect/1"
const DEV_GROUP := &"dev_inspect"
const ENTITY_PREFIX := "entity_"
const INSPECT_METHOD := &"inspect_state"
const SECTION_METHOD := &"inspect_section"
## Size limits (the dump stays a few hundred KB at most).
const MAX_TREE_NODES := 4000
const MAX_RELEVANT := 400
const MAX_BONES := 256
const MAX_PROPS := 160
const MAX_PARAMS := 256
const MAX_ARRAY := 64
const MAX_DEPTH := 8
## Float rounding step.
const DECIMALS := 0.00001
## Classes always reported in `nodes`.
const RELEVANT_CLASSES: Array[String] = ["Skeleton3D", "AnimationTree", "AnimationPlayer", "Camera3D",
	"BoneAttachment3D"]


## Snapshot of the whole tree. `context` is copied into "context" (capture name, trigger...).
## `final_poses`: {skeleton instance id: {"frame", "local": Array[Transform3D],
## "global": Array[Transform3D]}} recorded on Skeleton3D.skeleton_updated (the pose after the
## modifiers is only readable there: outside the update Godot restores the input pose).
static func collect(tree: SceneTree, context: Dictionary = {}, final_poses: Dictionary = {}) -> Dictionary:
	var root: Node = tree.root
	var out := {
		"format": FORMAT,
		"frame": Engine.get_process_frames(),
		"time": value(Time.get_ticks_msec() * 0.001),
		"motion_time": value(MotionClock.now()),
		"movie": Engine.get_write_movie_path() != "",
		"context": value(context),
		"errors": [],
	}
	_game_state(out)
	out["viewport"] = value(root.get_visible_rect().size)
	out["camera"] = camera(tree)
	var all := root.find_children("*", "", true, false)
	out["tree"] = scene_tree(root, all)
	var nodes := {}
	var skeletons := {}
	var trees := {}
	var players := {}
	var errors: Array = out["errors"]
	for n: Node in all:
		var path := node_path(root, n)
		if is_relevant(n) and nodes.size() < MAX_RELEVANT:
			nodes[path] = node_info(n)
		if n is Skeleton3D:
			skeletons[path] = skeleton(n as Skeleton3D, root, final_poses.get((n as Object).get_instance_id(), {}))
		elif n is AnimationTree:
			trees[path] = animation_tree(n as AnimationTree, root)
		elif n is AnimationPlayer:
			players[path] = animation_player(n as AnimationPlayer)
	if nodes.size() >= MAX_RELEVANT:
		errors.append("nodes truncated at %d" % MAX_RELEVANT)
	out["nodes"] = nodes
	out["skeletons"] = skeletons
	out["animation_trees"] = trees
	out["animation_players"] = players
	out["sections"] = sections(tree, root, errors)
	return out


## Pretty, key-sorted JSON (stable for diffs).
static func to_json(data: Dictionary) -> String:
	return JSON.stringify(data, "  ", true) + "\n"


# ------------------------------------------------------------------ game state


static func _game_state(out: Dictionary) -> void:
	out["sim_time"] = value(Simulation.time)
	out["sim_status"] = String(EventTimeline.Status.keys()[Simulation.status])
	out["sim_speed"] = value(Simulation.timeline.speed) if Simulation.timeline else null
	out["scenario"] = String(Simulation.scenario)
	out["phase"] = Simulation.state.phase_name() if Simulation.state else ""
	out["mode"] = Session.mode_name()
	out["selected"] = String(Session.selected)
	out["hud"] = Session.hud_visible
	out["cinematic"] = Session.cinematic
	out["call_line_open"] = Session.call_line_open
	out["quality"] = {"level": Quality.level_name(), "auto": Quality.auto}


## The current 3D camera and, when a camera director (group camera_director) exposes `rig()`,
## its orbit rig (target, yaw, pitch, distance, fov, offset).
static func camera(tree: SceneTree) -> Dictionary:
	var cam := tree.root.get_camera_3d()
	if cam == null:
		return {}
	var forward := -cam.global_basis.z
	var info := {
		"path": node_path(tree.root, cam),
		"position": value(cam.global_position),
		"forward": value(forward),
		"rotation_deg": value(cam.global_rotation_degrees),
		"fov": value(cam.fov),
		"near": value(cam.near),
		"far": value(cam.far),
		"projection": cam.projection,
	}
	for d: Node in tree.get_nodes_in_group(&"camera_director"):
		if not d.has_method(&"rig"):
			continue
		var r: Variant = d.call(&"rig")
		if r is Object:
			var rig := {}
			for k: String in ["target", "yaw", "pitch", "distance", "fov", "offset"]:
				rig[k] = value((r as Object).get(k))
			info["rig"] = rig
			info["director"] = node_path(tree.root, d)
			info["target"] = rig["target"]
			if d.has_method(&"focused"):
				info["focused"] = String(d.call(&"focused"))
		break
	if not info.has("target"):
		info["target"] = value(cam.global_position + forward * 10.0)
		info["target_note"] = "no camera director rig: 10 m ahead of the camera"
	return info


# ------------------------------------------------------------------ tree and nodes


## Path of `n` relative to the root window ("Main/World/Miku").
static func node_path(root: Node, n: Node) -> String:
	return String(root.get_path_to(n))


static func scene_tree(root: Node, all: Array[Node]) -> Dictionary:
	var nodes := {}
	for n: Node in all:
		if nodes.size() >= MAX_TREE_NODES:
			break
		var label := n.get_class()
		var s: Script = n.get_script()
		if s != null and s.resource_path != "":
			label += " " + s.resource_path.get_file()
		if (n is Node3D and not (n as Node3D).visible) or (n is CanvasItem and not (n as CanvasItem).visible):
			label += " hidden"
		nodes[node_path(root, n)] = label
	return {"count": all.size(), "truncated": all.size() > MAX_TREE_NODES, "nodes": nodes}


static func is_relevant(n: Node) -> bool:
	for c in RELEVANT_CLASSES:
		if n.is_class(c):
			return true
	for g: StringName in n.get_groups():
		if g == DEV_GROUP or String(g).begins_with(ENTITY_PREFIX):
			return true
	return false


static func node_info(n: Node) -> Dictionary:
	var groups: Array = []
	for g: StringName in n.get_groups():
		if not String(g).begins_with("_"):
			groups.append(String(g))
	groups.sort()
	var info := {"class": n.get_class(), "groups": groups}
	var s: Script = n.get_script()
	if s != null:
		info["script"] = s.resource_path
	if n is Node3D:
		var n3 := n as Node3D
		info["visible"] = n3.is_visible_in_tree()
		info["global"] = xform(n3.global_transform)
	elif n is CanvasItem:
		info["visible"] = (n as CanvasItem).is_visible_in_tree()
	return info


# ------------------------------------------------------------------ skeletons


static func skeleton(sk: Skeleton3D, root: Node, final: Dictionary) -> Dictionary:
	var count := sk.get_bone_count()
	var bones := {}
	var final_local: Array = final.get("local", [])
	var final_global: Array = final.get("global", [])
	var has_final := final_local.size() == count and final_global.size() == count
	for i in mini(count, MAX_BONES):
		var parent := sk.get_bone_parent(i)
		var global_pose := sk.get_bone_global_pose(i)
		var b := {
			"index": i,
			"parent": sk.get_bone_name(parent) if parent >= 0 else "",
			"enabled": sk.is_bone_enabled(i),
			"rest": xform(sk.get_bone_rest(i)),
			"pose": xform(sk.get_bone_pose(i)),
			"pose_global": xform(global_pose),
		}
		if has_final:
			var fl: Transform3D = final_local[i]
			var fg: Transform3D = final_global[i]
			b["final"] = xform(fl)
			b["final_global"] = xform(fg)
			b["world_position"] = value(sk.global_transform * fg.origin)
		else:
			b["world_position"] = value(sk.global_transform * global_pose.origin)
		bones[sk.get_bone_name(i)] = b
	var modifiers: Array = []
	for c: Node in sk.get_children():
		if c is SkeletonModifier3D:
			modifiers.append(modifier(c as SkeletonModifier3D, root))
	return {
		"bone_count": count,
		"bones_truncated": count > MAX_BONES,
		"final_frame": final.get("frame", -1) if has_final else -1,
		"final_note": "" if has_final else "no skeleton_updated since the inspector started: pose/pose_global are the input pose (no modifier applied)",
		"global": xform(sk.global_transform),
		"motion_scale": value(sk.motion_scale),
		"show_rest_only": sk.show_rest_only,
		"modifier_callback_mode_process": sk.modifier_callback_mode_process,
		"bones": bones,
		"modifiers": modifiers,
	}


## Class, state and own properties of a SkeletonModifier3D (everything declared below Node3D:
## SkeletonModifier3D.active/influence, the subclass members — bones, targets, axes, limits, the
## dynamic `settings/<i>/...` of the IK/constraint modifiers — and script variables). NodePath
## properties are resolved to the target node path and its world position.
static func modifier(m: SkeletonModifier3D, root: Node) -> Dictionary:
	var base := _node3d_property_names()
	var props := {}
	var targets := {}
	for p: Dictionary in m.get_property_list():
		var usage: int = p["usage"]
		if usage & (PROPERTY_USAGE_CATEGORY | PROPERTY_USAGE_GROUP | PROPERTY_USAGE_SUBGROUP):
			continue
		if not (usage & (PROPERTY_USAGE_STORAGE | PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_SCRIPT_VARIABLE)):
			continue
		var pname := String(p["name"])
		if base.has(pname) or pname == "script" or props.size() >= MAX_PROPS:
			continue
		var v: Variant = m.get(pname)
		props[pname] = value(v)
		if v is NodePath and not (v as NodePath).is_empty():
			var t := m.get_node_or_null(v as NodePath)
			targets[pname] = {"node": node_path(root, t), "world_position": value((t as Node3D).global_position)} \
				if t is Node3D else ({"node": node_path(root, t)} if t else {"missing": String(v)})
	var info := {
		"name": String(m.name),
		"class": m.get_class(),
		"active": m.active,
		"influence": value(m.influence),
		"properties": props,
		"targets": targets,
	}
	var s: Script = m.get_script()
	if s != null:
		info["script"] = s.resource_path
	var status := {}
	if m is LookAtModifier3D:
		var la := m as LookAtModifier3D
		status["interpolating"] = la.is_interpolating()
		status["interpolation_remaining"] = value(la.get_interpolation_remaining())
		status["target_within_limitation"] = la.is_target_within_limitation()
	if not status.is_empty():
		info["status"] = status
	return info


static var _base_names: Dictionary = {}


static func _node3d_property_names() -> Dictionary:
	if _base_names.is_empty():
		for p: Dictionary in ClassDB.class_get_property_list(&"Node3D"):
			_base_names[String(p["name"])] = true
	return _base_names


# ------------------------------------------------------------------ animation


## Every `parameters/*` value of an AnimationTree: plain values as they are; state machine
## playbacks as {current_node, travel_path, playing, position, length, fading_from...}.
static func animation_tree(t: AnimationTree, root: Node) -> Dictionary:
	var params := {}
	var playbacks := {}
	for p: Dictionary in t.get_property_list():
		var pname := String(p["name"])
		if not pname.begins_with("parameters/") or params.size() + playbacks.size() >= MAX_PARAMS:
			continue
		var v: Variant = t.get(pname)
		if v is AnimationNodeStateMachinePlayback:
			playbacks[pname] = playback(v as AnimationNodeStateMachinePlayback)
		elif v is Object:
			continue
		else:
			params[pname] = value(v)
	var player := t.get_node_or_null(t.anim_player) if not t.anim_player.is_empty() else null
	return {
		"active": t.active,
		"root": t.tree_root.get_class() if t.tree_root else "",
		"anim_player": node_path(root, player) if player else "",
		"callback_mode_process": t.callback_mode_process,
		"parameters": params,
		"playbacks": playbacks,
	}


static func playback(pb: AnimationNodeStateMachinePlayback) -> Dictionary:
	var path: Array = []
	for s: StringName in pb.get_travel_path():
		path.append(String(s))
	return {
		"current_node": String(pb.get_current_node()),
		"travel_path": path,
		"playing": pb.is_playing(),
		"position": value(pb.get_current_play_position()),
		"length": value(pb.get_current_length()),
		"fading_from": String(pb.get_fading_from_node()),
		"fading_position": value(pb.get_fading_position()),
		"fading_length": value(pb.get_fading_length()),
	}


static func animation_player(p: AnimationPlayer) -> Dictionary:
	var anims: Array = []
	for a: StringName in p.get_animation_list():
		if anims.size() >= MAX_ARRAY:
			break
		anims.append(String(a))
	return {
		"active": p.active,
		"playing": p.is_playing(),
		"current": String(p.current_animation),
		"assigned": String(p.assigned_animation),
		"position": value(p.current_animation_position) if p.assigned_animation != &"" else 0.0,
		"speed_scale": value(p.speed_scale),
		"animations": anims,
	}


# ------------------------------------------------------------------ dev_inspect sections


## inspect_state() of every node of group dev_inspect, by section key (sorted paths, so
## duplicate keys get a stable "@path" suffix).
static func sections(tree: SceneTree, root: Node, errors: Array) -> Dictionary:
	var out := {}
	var members: Array = []
	for n: Node in tree.get_nodes_in_group(DEV_GROUP):
		members.append([node_path(root, n), n])
	members.sort_custom(func(a: Array, b: Array) -> bool: return String(a[0]) < String(b[0]))
	for pair: Array in members:
		var path := String(pair[0])
		var n: Node = pair[1]
		if not n.has_method(INSPECT_METHOD):
			errors.append("%s is in group %s without %s()" % [path, DEV_GROUP, INSPECT_METHOD])
			continue
		var state: Variant = n.call(INSPECT_METHOD)
		if not (state is Dictionary):
			errors.append("%s.%s() returned %s, not a Dictionary" % [path, INSPECT_METHOD, type_string(typeof(state))])
			continue
		var key := String(n.call(SECTION_METHOD)) if n.has_method(SECTION_METHOD) else String(n.name)
		if out.has(key):
			key = "%s@%s" % [key, path]
		var section: Dictionary = value(state)
		section["_path"] = path
		section["_class"] = n.get_class()
		out[key] = section
	return out


# ------------------------------------------------------------------ values


## {pos, quat, euler_deg (YXZ), scale} of a transform (rounded).
static func xform(t: Transform3D) -> Dictionary:
	var s := t.basis.get_scale()
	var q := t.basis.orthonormalized().get_rotation_quaternion() if s.x > 0.0 and s.y > 0.0 and s.z > 0.0 \
		else Quaternion.IDENTITY
	return {
		"pos": value(t.origin),
		"quat": value(q),
		"euler_deg": value(q.get_euler() * (180.0 / PI)),
		"scale": value(s),
	}


static func round_float(f: float) -> Variant:
	if is_nan(f) or is_inf(f):
		return str(f)
	var r := snappedf(f, DECIMALS)
	return 0.0 if r == 0.0 else r  # no "-0.0"


## JSON-safe copy of any Variant (bounded depth and array length).
static func value(v: Variant, depth: int = 0) -> Variant:
	if depth > MAX_DEPTH:
		return "<depth>"
	match typeof(v):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_STRING:
			return v
		TYPE_FLOAT:
			return round_float(v)
		TYPE_STRING_NAME, TYPE_NODE_PATH:
			return String(v)
		TYPE_VECTOR2, TYPE_VECTOR2I:
			return [round_float(v.x), round_float(v.y)]
		TYPE_VECTOR3, TYPE_VECTOR3I:
			return [round_float(v.x), round_float(v.y), round_float(v.z)]
		TYPE_VECTOR4, TYPE_VECTOR4I, TYPE_QUATERNION:
			return [round_float(v.x), round_float(v.y), round_float(v.z), round_float(v.w)]
		TYPE_COLOR:
			return [round_float(v.r), round_float(v.g), round_float(v.b), round_float(v.a)]
		TYPE_RECT2, TYPE_RECT2I:
			return {"position": value(v.position), "size": value(v.size)}
		TYPE_TRANSFORM3D:
			return xform(v)
		TYPE_BASIS:
			return xform(Transform3D(v, Vector3.ZERO))
		TYPE_TRANSFORM2D:
			return {"origin": value(v.origin), "rotation_deg": round_float(rad_to_deg(v.get_rotation())),
				"scale": value(v.get_scale())}
		TYPE_DICTIONARY:
			var d := {}
			for k: Variant in v:
				d[str(k)] = value(v[k], depth + 1)
			return d
		TYPE_OBJECT:
			return _object(v)
		TYPE_CALLABLE, TYPE_SIGNAL, TYPE_RID:
			return str(v)
	if typeof(v) >= TYPE_ARRAY:
		var arr: Array = []
		var n := 0
		for item: Variant in v:
			if n >= MAX_ARRAY:
				arr.append("<+%d more>" % (v.size() - MAX_ARRAY))
				break
			arr.append(value(item, depth + 1))
			n += 1
		return arr
	return str(v)


static func _object(o: Object) -> Variant:
	if o == null or not is_instance_valid(o):
		return null
	if o is Node:
		var n := o as Node
		if n.is_inside_tree():
			return {"node": String(n.get_tree().root.get_path_to(n)), "class": n.get_class()}
		return {"node": String(n.name), "class": n.get_class(), "outside_tree": true}
	if o is Resource:
		var r := o as Resource
		return {"resource": r.get_class(), "path": r.resource_path}
	return {"object": o.get_class()}
