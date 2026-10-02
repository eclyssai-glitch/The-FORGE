extends Node
## DEVELOPMENT ONLY — runtime inspector of the game (docs/BUILD.md, "Inspector de desenvolvimento").
## Lives in tools/inspector, which the export excludes (`tools/*` in exclude_filter): the shipped
## game never contains it. No class_name, no autoload, nothing in project.godot: the automation
## (src/core/automation.gd) loads this script BY PATH only when an --inspect* flag is passed, and
## ignores the flag with a warning when the file does not exist (exported build).
##
## What it writes: a key-sorted JSON snapshot of the game (inspector_collect.gd: scene tree,
## relevant nodes, Skeleton3D bones — rest, input pose and the final pose after the
## SkeletonModifier3D chain —, the modifiers, AnimationTree parameters/playbacks, the camera and
## the `inspect_state()` sections of group dev_inspect) tied to the frame it describes:
##   - with --capture / --style-frames: `<shot>.json` next to every `<shot>.png`, same frame;
##   - with --inspect-every=<s>: every <s> seconds of game time, `inspect_<n>_f<frame>.json`
##     (+ `.png` of the same frame unless --inspect-png=off or headless) in the --inspect=<dir>
##     directory (default user://inspect);
##   - F9 (any run with --inspect): one dump on demand into that same directory.
## Read them with tools/inspector/summarize.py (summary, or --diff of two dumps).
##
## Final poses: Godot restores a skeleton's input pose after the modifiers ran, so the pose the
## frame was drawn with is only readable inside Skeleton3D.skeleton_updated. The inspector
## connects to every Skeleton3D of the tree (present and future) and keeps the last final pose
## (local + skeleton-space global per bone) — only while it exists, i.e. only in dev runs.

const Collect := preload("res://tools/inspector/inspector_collect.gd")
const DEFAULT_DIR := "user://inspect"
const DUMP_KEY := KEY_F9

## Directory of periodic / on-demand dumps (absolute).
var out_dir := ""
## Game seconds between periodic dumps (0 = off).
var every := 0.0
## Periodic dumps also save the frame as PNG.
var with_png := true
## Dumps written by this inspector (paths), in order.
var written: PackedStringArray = []

var _elapsed := 0.0
var _count := 0
var _busy := false
## {skeleton instance id: {"frame", "local": Array[Transform3D], "global": Array[Transform3D]}}
var _final := {}
## {skeleton instance id: Callable connected to its skeleton_updated}
var _tracked := {}


func _init() -> void:
	name = "DevInspector"


## Options from the command line (Main._parse_args): inspect (true or a directory), inspect-every
## (seconds), inspect-png (on|off).
func configure(options: Dictionary) -> void:
	var dir: Variant = options.get("inspect", true)
	out_dir = String(dir) if dir is String and String(dir) != "" else DEFAULT_DIR
	if out_dir.begins_with("user://") or out_dir.begins_with("res://"):
		out_dir = ProjectSettings.globalize_path(out_dir)
	elif out_dir.is_relative_path():
		out_dir = ProjectSettings.globalize_path("res://").path_join(out_dir)
	every = maxf(String(options.get("inspect-every", "0")).to_float(), 0.0)
	with_png = String(options.get("inspect-png", "on")) != "off" and DisplayServer.get_name() != "headless"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().node_added.connect(_on_node_added)
	for n in get_tree().root.find_children("*", "Skeleton3D", true, false):
		_track(n as Skeleton3D)
	print("[inspect] enabled dir=%s every=%s png=%s (F9 = dump now)" % [out_dir, every, with_png])


func _exit_tree() -> void:
	if get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.disconnect(_on_node_added)


func _process(delta: float) -> void:
	if every <= 0.0 or _busy:
		return
	_elapsed += delta
	if _elapsed >= every:
		_elapsed -= every
		_dump_periodic({"trigger": "every", "every": every})


func _input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k and k.pressed and not k.echo and k.keycode == DUMP_KEY and not _busy:
		_dump_periodic({"trigger": "key"})


## The snapshot of this moment (see inspector_collect.gd).
func snapshot(context: Dictionary = {}) -> Dictionary:
	return Collect.collect(get_tree(), context, _final)


## Writes `<base>.json` (base = path without extension) and returns its path ("" on failure).
func dump(base: String, context: Dictionary = {}) -> String:
	var path := base.get_basename() + ".json" if base.get_extension() != "" else base + ".json"
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_warning("dev inspector: cannot write %s (%s)" % [path, error_string(FileAccess.get_open_error())])
		return ""
	var data := snapshot(context)
	f.store_string(Collect.to_json(data))
	f.close()
	written.append(path)
	print("[inspect] %s (frame=%d sim=T+%.2f skeletons=%d sections=%d)" % [path, data["frame"], Simulation.time,
		(data["skeletons"] as Dictionary).size(), (data["sections"] as Dictionary).size()])
	return path


## The JSON twin of a capture: `<shot>.png` -> `<shot>.json`, same frame (call right after saving
## the image, in the same frame).
func dump_for_image(png_path: String, context: Dictionary = {}) -> String:
	var ctx := context.duplicate()
	ctx["image"] = png_path.get_file()
	return dump(png_path, ctx)


func _dump_periodic(context: Dictionary) -> void:
	_busy = true
	_count += 1
	await RenderingServer.frame_post_draw
	var base := out_dir.path_join("inspect_%04d_f%07d" % [_count, Engine.get_process_frames()])
	if with_png:
		var img := get_viewport().get_texture().get_image()
		if img:
			img.save_png(base + ".png")
			context["image"] = (base + ".png").get_file()
	dump(base, context)
	_busy = false


# ------------------------------------------------------------------ final skeleton poses


func _on_node_added(n: Node) -> void:
	if n is Skeleton3D:
		_track(n as Skeleton3D)


func _track(sk: Skeleton3D) -> void:
	var id := sk.get_instance_id()
	if _tracked.has(id):
		return
	var cb := _on_skeleton_updated.bind(sk)
	_tracked[id] = cb
	sk.skeleton_updated.connect(cb)
	sk.tree_exiting.connect(_untrack.bind(sk), CONNECT_ONE_SHOT)


func _untrack(sk: Skeleton3D) -> void:
	var id := sk.get_instance_id()
	if _tracked.has(id) and sk.skeleton_updated.is_connected(_tracked[id]):
		sk.skeleton_updated.disconnect(_tracked[id])
	_tracked.erase(id)
	_final.erase(id)


func _on_skeleton_updated(sk: Skeleton3D) -> void:
	var count := sk.get_bone_count()
	var local: Array[Transform3D] = []
	var global: Array[Transform3D] = []
	local.resize(count)
	global.resize(count)
	for i in count:
		local[i] = sk.get_bone_pose(i)
		global[i] = sk.get_bone_global_pose(i)
	_final[sk.get_instance_id()] = {"frame": Engine.get_process_frames(), "local": local, "global": global}
