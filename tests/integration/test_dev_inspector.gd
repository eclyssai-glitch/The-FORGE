extends GutTest
## Development-only runtime inspector (tools/inspector; docs/BUILD.md, "Inspector de
## desenvolvimento"): loaded by path only with an --inspect* flag; a dump of a synthetic scene with
## a Skeleton3D, a LookAtModifier3D, an AnimationTree state machine and a fake dev_inspect node
## has every section; nothing in the shipped code (src/, scenes/, project.godot) references it
## except the guarded load() path in the automation; tools/ stays out of the export.

const AutomationScript := preload("res://src/core/automation.gd")
const INSPECTOR := "res://tools/inspector/dev_inspector.gd"
const COLLECT := "res://tools/inspector/inspector_collect.gd"
const TMP_DIR := "user://_test_dev_inspector"


## Fake game node following the inspect_state() contract.
class FakeMind:
	extends Node
	var mood := &"curious"

	func _ready() -> void:
		add_to_group(&"dev_inspect")

	func inspect_section() -> String:
		return "miku"

	func inspect_state() -> Dictionary:
		return {"mood": mood, "composure": 0.8, "action": &"WORK", "gaze": Vector3(1, 2, 3),
			"hands": [{"id": 0, "target": Vector3(0.5, 1, 0), "active": true}],
			"threads": [{"id": 0, "tension": 0.25, "presence": 1.0}]}


## In group dev_inspect but without the method: reported in "errors", never fatal.
class Broken:
	extends Node

	func _ready() -> void:
		add_to_group(&"dev_inspect")


var scene: Node3D
var skeleton: Skeleton3D
var look: LookAtModifier3D
var anim_tree: AnimationTree
var inspector: Node


func after_each() -> void:
	if is_instance_valid(scene):
		scene.free()
	if is_instance_valid(inspector):
		inspector.free()
	var abs_dir := ProjectSettings.globalize_path(TMP_DIR)
	if DirAccess.dir_exists_absolute(abs_dir):
		for f in DirAccess.get_files_at(abs_dir):
			DirAccess.remove_absolute(abs_dir.path_join(f))
		DirAccess.remove_absolute(abs_dir)


# ------------------------------------------------------------------ no flag, nothing loaded


func test_without_flag_nothing_is_loaded() -> void:
	assert_false(AutomationScript.inspector_requested({}))
	assert_false(AutomationScript.inspector_requested({"capture": "x", "smoke-test": true, "scenario": "living"}))
	assert_true(AutomationScript.inspector_requested({"inspect": true}))
	assert_true(AutomationScript.inspector_requested({"inspect-every": "2"}))
	assert_null(AutomationScript.load_inspector({"capture": "x"}), "no flag -> no inspector")
	var automation: Node = AutomationScript.new()
	automation.options = {}
	add_child(automation)
	assert_null(automation.inspector)
	assert_eq(automation.get_child_count(), 0, "no DevInspector child")
	automation.free()


func test_missing_inspector_file_is_ignored() -> void:
	assert_null(AutomationScript.load_inspector({"inspect": true}, "res://tools/inspector/not_here.gd"),
		"exported build: the flag is ignored")


func test_flag_loads_the_inspector_by_path() -> void:
	inspector = AutomationScript.load_inspector({"inspect": TMP_DIR, "inspect-every": "0.5", "inspect-png": "off"})
	assert_not_null(inspector)
	assert_eq(inspector.get_script().resource_path, INSPECTOR)
	assert_eq(inspector.get(&"out_dir"), ProjectSettings.globalize_path(TMP_DIR))
	assert_almost_eq(float(inspector.get(&"every")), 0.5, 1e-6)
	assert_false(inspector.get(&"with_png"))


func test_shipped_code_never_references_the_inspector() -> void:
	var hits: PackedStringArray = []
	for root in ["res://src", "res://scenes"]:
		for f in _files(root):
			var text := _code(f)
			if text.contains("tools/inspector") or text.contains("inspector_collect"):
				hits.append(f)
			assert_false(text.contains("preload(\"res://tools/"), "%s preloads a tool" % f)
	assert_eq(hits, PackedStringArray(["res://src/core/automation.gd"]), "only the guarded load() path")
	var auto_src := _code("res://src/core/automation.gd")
	assert_false(auto_src.contains("preload(INSPECTOR_PATH"))
	assert_true(auto_src.contains("load(path)"))
	var project := FileAccess.get_file_as_string("res://project.godot")
	assert_false(project.contains("tools/"), "no autoload/setting points at tools/")
	var presets := FileAccess.get_file_as_string("res://export_presets.cfg")
	assert_true(presets.contains("exclude_filter=\"addons/gut/*, tests/*, tools/*"), "tools/ excluded from the export")
	for f in _files("res://tools/inspector"):
		if f.ends_with(".gd"):
			assert_false(("\n" + _code(f)).contains("\nclass_name"), "%s: no global class" % f)


# ------------------------------------------------------------------ dump of a synthetic scene


func test_dump_of_synthetic_scene_has_every_section() -> void:
	_build_scene()
	inspector = AutomationScript.load_inspector({"inspect": TMP_DIR, "inspect-png": "off"})
	add_child(inspector)
	await wait_process_frames(4)
	var path: String = inspector.call(&"dump_for_image", ProjectSettings.globalize_path(TMP_DIR).path_join("synthetic.png"),
		{"capture": "synthetic"})
	assert_true(path.ends_with("synthetic.json"), "same base name as the PNG")
	var text := FileAccess.get_file_as_string(path)
	var data: Variant = JSON.parse_string(text)
	assert_true(data is Dictionary, "valid JSON")
	var d: Dictionary = data
	for k in ["format", "frame", "time", "motion_time", "sim_time", "scenario", "mode", "quality", "camera",
			"tree", "nodes", "skeletons", "animation_trees", "animation_players", "sections", "errors", "context"]:
		assert_true(d.has(k), "key %s" % k)
	assert_eq(d["context"]["capture"], "synthetic")
	assert_eq(d["context"]["image"], "synthetic.png")
	var sp := _path(skeleton)
	var anp := _path(anim_tree)
	# Scene tree + relevant nodes.
	assert_true((d["tree"]["nodes"] as Dictionary).has(sp))
	assert_true((d["tree"]["nodes"] as Dictionary).has(_path(look)))
	assert_true((d["nodes"] as Dictionary).has(sp), "Skeleton3D is relevant")
	assert_true((d["nodes"] as Dictionary).has(anp), "AnimationTree is relevant")
	assert_true((d["nodes"] as Dictionary).has(_path(scene.get_node("Entity"))), "entity_* group is relevant")
	assert_has(d["nodes"][_path(scene.get_node("Entity"))]["groups"], "entity_probe")
	# Skeleton: bones with rest, input pose and the final pose after the modifier.
	var sk: Dictionary = d["skeletons"][sp]
	assert_eq(int(sk["bone_count"]), 3)
	assert_eq((sk["bones"] as Dictionary).keys().size(), 3)
	var head: Dictionary = sk["bones"]["head"]
	assert_eq(head["parent"], "neck")
	assert_eq(int(head["index"]), 2)
	for k in ["rest", "pose", "pose_global", "final", "final_global", "world_position"]:
		assert_true(head.has(k), "head.%s" % k)
	assert_almost_eq(float(head["rest"]["pos"][1]), 0.3, 1e-5)
	assert_ne(head["final"]["quat"], head["pose"]["quat"], "the LookAtModifier3D turned the head")
	assert_gt(int(sk["final_frame"]), 0)
	# Modifier: class, active, influence, own properties, resolved target.
	assert_eq((sk["modifiers"] as Array).size(), 1)
	var m: Dictionary = sk["modifiers"][0]
	assert_eq(m["class"], "LookAtModifier3D")
	assert_eq(m["active"], true)
	assert_almost_eq(float(m["influence"]), 0.75, 1e-5)
	assert_eq(m["properties"]["bone_name"], "head")
	assert_true((m["properties"] as Dictionary).has("forward_axis"))
	assert_false((m["properties"] as Dictionary).has("transform"), "Node3D members are left out")
	assert_eq(m["targets"]["target_node"]["node"], _path(scene.get_node("Target")))
	assert_almost_eq(float(m["targets"]["target_node"]["world_position"][0]), 2.0, 1e-5)
	assert_true((m["status"] as Dictionary).has("interpolating"))
	# AnimationTree: state machine playback + parameters.
	var at: Dictionary = d["animation_trees"][anp]
	assert_eq(at["root"], "AnimationNodeStateMachine")
	assert_eq(at["parameters"]["parameters/conditions/busy"], true)
	var pb: Dictionary = at["playbacks"]["parameters/playback"]
	assert_eq(pb["current_node"], "work", "travelled idle -> work on the condition")
	assert_true(pb["playing"])
	assert_true((d["animation_players"] as Dictionary).has(_path(scene.get_node("Player"))))
	# dev_inspect sections (duck-typed contract) and the contract violation.
	var miku: Dictionary = d["sections"]["miku"]
	assert_eq(miku["mood"], "curious")
	assert_eq(miku["action"], "WORK")
	assert_eq(miku["gaze"], [1.0, 2.0, 3.0])
	assert_almost_eq(float(miku["threads"][0]["tension"]), 0.25, 1e-6)
	assert_eq(miku["_path"], _path(scene.get_node("Mind")))
	var broken_reported := (d["errors"] as Array).any(func(e: Variant) -> bool:
		return String(e).contains(_path(scene.get_node("Broken"))) and String(e).contains("without inspect_state()"))
	assert_true(broken_reported, "contract violation reported, not fatal: %s" % str(d["errors"]))
	# Camera of the synthetic scene (no director: a point ahead of it).
	assert_eq(d["camera"]["path"], _path(scene.get_node("Cam")))
	assert_eq(d["camera"]["fov"], 50.0)
	assert_true((d["camera"] as Dictionary).has("target"))


## The real MIKU rig (procedural-modeler) + one angelic hand, with a LookAtModifier3D on the head:
## every contract bone is dumped and the file stays small. INSPECTOR_SAMPLE_DIR=<dir> keeps a copy
## of the dump (sample for docs/BUILD.md).
func test_dump_of_the_miku_rig() -> void:
	scene = Node3D.new()
	scene.name = "RigProbe"
	add_child(scene)
	var miku := MikuRig.build()
	scene.add_child(miku)
	var hand := HandRig.build(HandRig.Side.RIGHT)
	scene.add_child(hand)
	hand.position = Vector3(1.5, 1.0, 0.5)
	var target := Marker3D.new()
	target.name = "User"
	scene.add_child(target)
	target.position = Vector3(1.0, 1.6, 3.0)
	skeleton = MikuRig.get_skeleton(miku)
	look = LookAtModifier3D.new()
	look.name = "GazeHead"
	skeleton.add_child(look)
	look.bone_name = "head"
	look.forward_axis = SkeletonModifier3D.BONE_AXIS_PLUS_Z
	look.target_node = look.get_path_to(target)
	inspector = AutomationScript.load_inspector({"inspect": TMP_DIR, "inspect-png": "off"})
	add_child(inspector)
	await wait_process_frames(4)
	var path: String = inspector.call(&"dump", ProjectSettings.globalize_path(TMP_DIR).path_join("miku_rig"),
		{"probe": "miku_rig"})
	var text := FileAccess.get_file_as_string(path)
	assert_lt(text.length(), 600_000, "bounded dump size (%d bytes)" % text.length())
	var d: Dictionary = JSON.parse_string(text)
	var sk: Dictionary = d["skeletons"][_path(skeleton)]
	for b in MikuRig.CONTRACT_BONES:
		assert_true((sk["bones"] as Dictionary).has(b), "bone %s" % b)
	assert_eq(sk["modifiers"][0]["class"], "LookAtModifier3D")
	assert_ne(sk["bones"]["head"]["final"]["quat"], sk["bones"]["head"]["pose"]["quat"], "gaze applied in final")
	assert_eq(sk["bones"]["hand.L"]["parent"], "forearm.L")
	assert_eq((d["skeletons"] as Dictionary).size(), 2, "MIKU + hand")
	var sample := OS.get_environment("INSPECTOR_SAMPLE_DIR")
	if sample != "":
		DirAccess.make_dir_recursive_absolute(sample)
		DirAccess.copy_absolute(path, sample.path_join("miku_rig_probe.json"))


func test_json_is_key_sorted_and_stable() -> void:
	_build_scene()
	inspector = AutomationScript.load_inspector({"inspect": TMP_DIR, "inspect-png": "off"})
	add_child(inspector)
	await wait_process_frames(3)
	var a: Dictionary = inspector.call(&"snapshot", {})
	var b: Dictionary = inspector.call(&"snapshot", {})
	for k in ["time", "motion_time"]:
		a.erase(k)
		b.erase(k)
	var collect: GDScript = load(COLLECT)
	assert_eq(collect.to_json(a), collect.to_json(b), "same frame -> same dump")
	var keys: Array = JSON.parse_string(collect.to_json({"b": 1, "a": {"d": 1, "c": 2}})).keys()
	assert_eq(keys, ["a", "b"])
	assert_true(collect.to_json({"b": 1, "a": 2}).find("\"a\"") < collect.to_json({"b": 1, "a": 2}).find("\"b\""))
	assert_true(collect.to_json(collect.value({"x": 0.1 + 0.2, "y": 1.0 / 3.0})).contains("\"x\": 0.3,"), "rounded floats")
	assert_true(collect.to_json(collect.value({"y": 1.0 / 3.0})).contains("0.33333\n"), "rounded floats")
	assert_eq(collect.value(-0.000001), 0.0, "no -0.0")


func test_periodic_dumps_follow_game_time() -> void:
	_build_scene()
	inspector = AutomationScript.load_inspector({"inspect": TMP_DIR, "inspect-every": "0.05", "inspect-png": "off"})
	add_child(inspector)
	await wait_seconds(0.4)
	var written: PackedStringArray = inspector.get(&"written")
	assert_gt(written.size(), 1, "several periodic dumps")
	assert_true(written[0].get_file().begins_with("inspect_0001_f"))


func test_living_interaction_exposes_the_contract() -> void:
	var li := LivingInteraction.new()
	add_child(li)
	assert_true(li.is_in_group(&"dev_inspect"))
	assert_eq(li.inspect_section(), "interaction")
	var s := li.inspect_state()
	for k in ["action", "action_args", "plan", "queue", "last_report", "executor_bound", "provider_available", "config"]:
		assert_true(s.has(k), "interaction.%s" % k)
	assert_false(s["provider_available"])
	li.free()


# ------------------------------------------------------------------ helpers


func _build_scene() -> void:
	scene = Node3D.new()
	scene.name = "InspectorProbe"
	add_child(scene)
	var cam := Camera3D.new()
	cam.name = "Cam"
	cam.fov = 50.0
	scene.add_child(cam)
	cam.position = Vector3(0, 1.5, 4)
	cam.make_current()
	skeleton = Skeleton3D.new()
	skeleton.name = "Skeleton3D"
	scene.add_child(skeleton)
	skeleton.add_bone("root")
	skeleton.add_bone("neck")
	skeleton.set_bone_parent(1, 0)
	skeleton.add_bone("head")
	skeleton.set_bone_parent(2, 1)
	skeleton.set_bone_rest(1, Transform3D(Basis(), Vector3(0, 1, 0)))
	skeleton.set_bone_rest(2, Transform3D(Basis(), Vector3(0, 0.3, 0)))
	skeleton.reset_bone_poses()
	var target := Marker3D.new()
	target.name = "Target"
	scene.add_child(target)
	target.position = Vector3(2, 1.3, 1)
	look = LookAtModifier3D.new()
	look.name = "LookAt"
	skeleton.add_child(look)
	look.bone_name = "head"
	look.forward_axis = SkeletonModifier3D.BONE_AXIS_PLUS_Z
	look.influence = 0.75
	look.target_node = look.get_path_to(target)
	var entity := Node3D.new()
	entity.name = "Entity"
	entity.add_to_group(&"entity_probe")
	scene.add_child(entity)
	# AnimationTree: state machine idle -> work on condition "busy".
	var player := AnimationPlayer.new()
	player.name = "Player"
	scene.add_child(player)
	var lib := AnimationLibrary.new()
	for n: StringName in [&"idle", &"work"]:
		var a := Animation.new()
		a.length = 1.0
		a.loop_mode = Animation.LOOP_LINEAR
		lib.add_animation(n, a)
	player.add_animation_library(&"", lib)
	var sm := AnimationNodeStateMachine.new()
	for n: StringName in [&"idle", &"work"]:
		var node := AnimationNodeAnimation.new()
		node.animation = n
		sm.add_node(n, node)
	var start := AnimationNodeStateMachineTransition.new()
	start.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_AUTO
	sm.add_transition(&"Start", &"idle", start)
	var go := AnimationNodeStateMachineTransition.new()
	go.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_AUTO
	go.advance_condition = &"busy"
	sm.add_transition(&"idle", &"work", go)
	anim_tree = AnimationTree.new()
	anim_tree.name = "AnimationTree"
	scene.add_child(anim_tree)
	anim_tree.tree_root = sm
	anim_tree.anim_player = anim_tree.get_path_to(player)
	anim_tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	anim_tree.active = true
	anim_tree.advance(0.05)
	anim_tree.set(&"parameters/conditions/busy", true)
	anim_tree.advance(0.05)
	anim_tree.advance(0.05)
	var mind := FakeMind.new()
	mind.name = "Mind"
	scene.add_child(mind)
	var broken := Broken.new()
	broken.name = "Broken"
	scene.add_child(broken)


## Source of a script/scene without its comment lines.
func _code(f: String) -> String:
	var keep: PackedStringArray = []
	for line in FileAccess.get_file_as_string(f).split("\n"):
		if not line.strip_edges().begins_with("#"):
			keep.append(line)
	return "\n".join(keep)


func _path(n: Node) -> String:
	return String(get_tree().root.get_path_to(n))


func _files(dir: String) -> PackedStringArray:
	var out: PackedStringArray = []
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd") or f.ends_with(".tscn") or f.ends_with(".tres"):
			out.append(dir.path_join(f))
	for sub in DirAccess.get_directories_at(dir):
		out.append_array(_files(dir.path_join(sub)))
	return out
