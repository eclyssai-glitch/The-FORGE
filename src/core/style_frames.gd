class_name StyleFrames
extends RefCounted
## GENESIS style frames (Loop 4 acceptance: ≥ 6 hero framings, HUD hidden, 1920×1080), saved
## by the automation (`--style-frames=<dir>`, tools/style_frames.sh). Pure data + validation.
##
## A pose is a Dictionary:
##   "name": String      file stem (e.g. "sf_01_hero")
##   "time": float       Simulation time (seek) of the frame, 0..GenesisScript.DURATION
##   "mode": int         SessionState.Mode (fog/sky settings and UI context)
##   "position": Vector3 camera position (world)
##   "target": Vector3   point the camera looks at
##   "fov": float        vertical field of view in degrees (10..100)
## The automation places its own Camera3D (current) on each pose — no drift, no tween — so the
## frames are deterministic. The CameraDirector (animator) may supply the poses through an
## optional method `style_frame_poses() -> Array` (same Dictionary shape); they replace
## DEFAULT_POSES when at least MIN_FRAMES of them are valid (see poses_from).

const MIN_FRAMES := 6
const SIZE := Vector2i(1920, 1080)
## Optional CameraDirector method providing the poses.
const DIRECTOR_METHOD := &"style_frame_poses"
## Manifest written next to the frames (one file name per line), checked by tools/style_frames.sh.
const MANIFEST := "style_frames.txt"

## Fallback poses (game-engineer), from the layout of docs/contracts/loop-04.md: MIKU (0, 4, 0)
## ~6 u tall, planet (0, 1, 4) r 1.6, hands ≈ (−3, −1.5, 4.6) / (3.2, 3.4, 4.8), moons r 3.0/4.2,
## ring 2.2–2.9, belt r 16–19, far planets r 11 and 24; warm core behind MIKU (−Z).
const DEFAULT_POSES: Array[Dictionary] = [
	{"name": "sf_01_hero", "time": 55.0, "mode": SessionState.Mode.FORGE,
		"position": Vector3(0.0, 0.4, 17.0), "target": Vector3(0.0, 4.0, 1.5), "fov": 42.0},
	{"name": "sf_02_awakening", "time": 6.5, "mode": SessionState.Mode.FORGE,
		"position": Vector3(1.4, 3.2, 9.5), "target": Vector3(0.0, 5.2, 0.0), "fov": 38.0},
	{"name": "sf_03_cradle", "time": 25.5, "mode": SessionState.Mode.FORGE,
		"position": Vector3(-6.0, 0.2, 12.0), "target": Vector3(0.0, 1.0, 4.2), "fov": 40.0},
	{"name": "sf_04_crust", "time": 30.5, "mode": SessionState.Mode.FORGE,
		"position": Vector3(3.0, 2.0, 9.6), "target": Vector3(0.0, 1.3, 4.0), "fov": 36.0},
	{"name": "sf_05_moons_ring", "time": 45.0, "mode": SessionState.Mode.FORGE,
		"position": Vector3(7.0, 5.5, 12.0), "target": Vector3(0.0, 1.0, 4.0), "fov": 42.0},
	{"name": "sf_06_system", "time": 55.0, "mode": SessionState.Mode.UNIVERSE,
		"position": Vector3(0.0, 26.0, 44.0), "target": Vector3(0.0, 2.0, 0.0), "fov": 45.0},
	{"name": "sf_07_threads", "time": 52.0, "mode": SessionState.Mode.OBSERVATORY,
		"position": Vector3(-14.0, 11.0, 16.0), "target": Vector3(0.0, 3.0, 2.0), "fov": 45.0},
	{"name": "sf_08_silhouette", "time": 55.0, "mode": SessionState.Mode.FORGE,
		"position": Vector3(-11.0, 3.0, 6.5), "target": Vector3(0.0, 4.5, 0.5), "fov": 40.0},
]


## True when `p` is a usable pose (keys, types and ranges above).
static func is_valid_pose(p: Variant) -> bool:
	if not p is Dictionary:
		return false
	var d := p as Dictionary
	for k in ["name", "time", "mode", "position", "target", "fov"]:
		if not d.has(k):
			return false
	var stem := str(d["name"])
	if stem.is_empty() or not stem.is_valid_filename() or stem.contains(" "):
		return false
	var t: Variant = d["time"]
	var fov: Variant = d["fov"]
	var mode: Variant = d["mode"]
	if not (t is float or t is int) or not (fov is float or fov is int) or not mode is int:
		return false
	if float(t) < 0.0 or float(t) > GenesisScript.DURATION:
		return false
	if int(mode) < 0 or int(mode) >= SessionState.MODE_NAMES.size():
		return false
	if float(fov) < 10.0 or float(fov) > 100.0:
		return false
	if not d["position"] is Vector3 or not d["target"] is Vector3:
		return false
	var dir := (d["target"] as Vector3) - (d["position"] as Vector3)
	return dir.length() > 0.01


## Valid poses of `list`, first occurrence of each name kept.
static func valid_poses(list: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var seen := {}
	for p in list:
		if is_valid_pose(p) and not seen.has(str(p["name"])):
			seen[str(p["name"])] = true
			out.append(p)
	return out


## Poses to shoot: the director's (`style_frame_poses()`) when it offers ≥ MIN_FRAMES valid
## ones, else DEFAULT_POSES. `director` may be null.
static func poses_from(director: Object) -> Array[Dictionary]:
	if director != null and director.has_method(DIRECTOR_METHOD):
		var list: Variant = director.call(DIRECTOR_METHOD)
		if list is Array:
			var valid := valid_poses(list)
			if valid.size() >= MIN_FRAMES:
				return valid
			push_warning("StyleFrames: %s() gave %d valid poses (< %d); using the defaults." % [
				DIRECTOR_METHOD, valid.size(), MIN_FRAMES])
	return DEFAULT_POSES.duplicate()


## Places `camera` on a pose (position, look-at, fov). Straight up/down targets use +Z as up.
static func apply_pose(camera: Camera3D, pose: Dictionary) -> void:
	var from: Vector3 = pose["position"]
	var to: Vector3 = pose["target"]
	var up := Vector3.UP
	if absf((to - from).normalized().dot(up)) > 0.999:
		up = Vector3.BACK
	camera.fov = float(pose["fov"])
	camera.look_at_from_position(from, to, up)
