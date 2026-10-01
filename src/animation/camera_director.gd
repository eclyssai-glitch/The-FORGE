class_name CameraDirector
extends Node3D
## The only camera of the world. Owner: animator.
## Orbit rig (target, yaw, pitch, distance, fov, offset — see CameraShots.Shot) that follows
## the shot of the current mode, and — when Session.cinematic in FORGE — the cue of the event
## being told (approach on activation, pull back on fragments, slow orbit while building, low
## angle on verification, orbital reveal on the final form).
##
## Transitions between shots are real-time tweens (Palette.T_CINEMATIC, sine in-out curve of
## Tween.interpolate_value on the wall clock — see _start_blend) of a blend factor from a
## snapshot to the live goal, so moving goals (orbits) stay smooth. The blended rig is clamped
## (CameraShots.clamp_rig) before it reaches the camera: never below the floor, even mid-blend. After Simulation.seek/reset
## (`world_rebuilt`) the camera snaps to the goal without a tween (unless a user/focus framing
## holds outside a cue, see below).
## Input (unhandled, so the UI consumes first): drag with left/right button = orbit, wheel = zoom,
## WASD = fly (UNIVERSE), `camera_reset` = back to the mode shot. A press only orbits once its
## accumulated travel is a drag for InputTuning.is_drag — the same threshold the Picker uses, so
## a press is either a click or an orbit, never both. Input suspends cues for
## USER_HOLD seconds; outside a cue the user's framing stays until reset or mode change.
## Group "camera_director": automation calls snap_to_mode_shot() after each seek/mode change.
##
## Focus (Session.focus_requested(id)): the entity is found through the group
## SessionState.entity_group(id); its world bounds are the FOCUS_BOUNDS_META AABB (local) of the
## group node when present, else the merged AABB of its VisualInstance3D descendants.
## CameraShots.focus_shot frames it keeping the mode (fov, offset, limits) and the rig tweens
## there (Palette.T_CINEMATIC). A focus counts as user input: cues wait USER_HOLD seconds after
## the framing settles; outside a cue it holds until reset, mode change or new input. Targets
## outside the mode's reach (CameraShots.FOCUS_REACH, e.g. a seed from FORGE) are ignored.
## Seek/reset keep a user framing that is not under a cue (the story cue always snaps).
##
## GENESIS (Simulation.scenario == Scenario.GENESIS): shots, cues, limits and focus come from
## GenesisShots (pure); its cues are stations of one continuous path (GenesisShots.cue_path), so a
## cue change needs no blend; returning to the cues after user control cranes over
## GenesisShots.T_CUE (Palette.T_CRANE), user-driven
## changes (mode, focus, reset) over GenesisShots.T_USER; every GENESIS entity can be focused from
## any mode. A scenario change snaps to the new scenario's shot. `style_frame_poses()` gives the
## GENESIS style frames to the automation (StyleFrames).

const GROUP := &"camera_director"
## Seconds of user control before cinematic cues take the camera back.
const USER_HOLD := 6.0
## Orbit radians per dragged pixel; zoom factor per wheel notch; fly speed in distances/s.
const ORBIT_PER_PIXEL := 0.0055
const ZOOM_STEP := 1.1
const FLY_SPEED := 0.5
## Meta (AABB, in the node's local space) that an entity root sets to give its exact focus bounds.
const FOCUS_BOUNDS_META := &"focus_bounds"

var camera: Camera3D

var _rig := CameraShots.Shot.new()
var _from := CameraShots.Shot.new()
var _goal := CameraShots.Shot.new()
## Tweened 0..1 from _from to the live goal.
var _blend := 1.0
## Running transition: wall-clock start (s) and duration; duration 0 = none.
var _blend_start := 0.0
var _blend_duration := 0.0
var _shot_id: StringName = &""
var _user := false
var _user_until := 0.0
var _press_travel := -1.0
## Focus framing being tweened / held (_blend goes _from -> _focus_goal).
var _focus_goal := CameraShots.Shot.new()
var _focusing := false
var _focus_id: StringName = &""
## Exposure trim last asked of the world (GENESIS cinematic path; 1 = the mode's exposure).
var _trim := 1.0


func _ready() -> void:
	add_to_group(GROUP)
	process_mode = Node.PROCESS_MODE_ALWAYS
	camera = Camera3D.new()
	camera.name = "Camera"
	camera.near = 0.05
	camera.far = 800.0
	add_child(camera)
	camera.current = true
	Session.mode_changed.connect(_on_mode_changed)
	Session.cinematic_changed.connect(_on_cinematic_changed)
	Session.focus_requested.connect(focus_on)
	Simulation.world_rebuilt.connect(_on_world_rebuilt)
	Simulation.scenario_changed.connect(_on_scenario_changed)
	snap_to_mode_shot()


## Jumps (no tween) to the goal of the current state: the cinematic cue in FORGE when
## Session.cinematic, otherwise the mode shot. Clears user control.
func snap_to_mode_shot() -> void:
	_stop_blend()
	_user = false
	_end_focus()
	_press_travel = -1.0
	_shot_id = _evaluate_goal()
	_rig.copy_from(_goal)
	_from.copy_from(_goal)
	_blend = 1.0
	_apply()


## Tweens back to the goal of the current state (what `camera_reset` does).
func reset_to_mode_shot() -> void:
	_user = false
	_end_focus()
	_shot_id = _evaluate_goal()
	_begin_transition()


## Frames entity `id` (Session.focus_requested). Returns false (camera untouched) when no node
## is in its group or the target is out of the mode's reach.
func focus_on(id: StringName) -> bool:
	if not is_inside_tree() or id == &"":
		return false
	var nodes := get_tree().get_nodes_in_group(SessionState.entity_group(id))
	var found := false
	var bounds := AABB()
	for n in nodes:
		if not n is Node3D:
			continue
		var b := node_bounds(n as Node3D)
		bounds = b if not found else bounds.merge(b)
		found = true
	if not found:
		return false
	if _genesis():
		if not GenesisShots.focus_reachable(bounds.get_center()):
			return false
		GenesisShots.focus_shot(Session.mode, bounds, _rig, _aspect(), _focus_goal)
	else:
		if not CameraShots.focus_reachable(Session.mode, bounds.get_center()):
			return false
		CameraShots.focus_shot(Session.mode, bounds, _rig, _aspect(), _focus_goal)
	_stop_blend()
	_user = true
	_press_travel = -1.0
	_focusing = true
	_focus_id = id
	var dur := _user_blend_duration()
	# The hold starts when the framing has settled.
	_user_until = _now() + dur + USER_HOLD
	_from.copy_from(_rig)
	_start_blend(dur)
	return true


## Entity being framed by the last focus (empty when none or after reset/input/mode change).
func focused() -> StringName:
	return _focus_id if _focusing else &""


## Goal of the last focus (read-only use: tests/debug).
func focus_goal() -> CameraShots.Shot:
	return _focus_goal


## World bounds of a focus node: its FOCUS_BOUNDS_META (local AABB) or the merged AABB of its
## VisualInstance3D descendants (itself included); a bare point at its position otherwise.
static func node_bounds(n: Node3D) -> AABB:
	if n.has_meta(FOCUS_BOUNDS_META):
		return n.global_transform * (n.get_meta(FOCUS_BOUNDS_META) as AABB)
	var acc := [false, AABB(n.global_position, Vector3.ZERO)]
	_merge_visuals(n, acc)
	return acc[1]


static func _merge_visuals(n: Node, acc: Array) -> void:
	if n is VisualInstance3D:
		var v := n as VisualInstance3D
		var b := v.global_transform * v.get_aabb()
		acc[1] = (acc[1] as AABB).merge(b) if acc[0] else b
		acc[0] = true
	for c in n.get_children():
		_merge_visuals(c, acc)


## Accumulated pointer travel (px) of the current left/right press; -1 when no press.
func press_travel() -> float:
	return _press_travel


## Current rig (read-only use: HUD/debug/tests).
func rig() -> CameraShots.Shot:
	return _rig


func _process(delta: float) -> void:
	_fly(delta)
	_advance_blend()
	var id := _evaluate_goal()
	if _user:
		# The user framing holds; cues take over again after USER_HOLD seconds.
		if _is_cue(id) and _now() >= _user_until:
			_user = false
			_end_focus()
			_shot_id = id
			_begin_transition(true)
		elif _focusing:
			CameraShots.blend(_from, _focus_goal, _blend, _rig)
	elif id != _shot_id:
		var story := _is_cue(id) and _is_cue(_shot_id)
		_shot_id = id
		# GENESIS cues are stations of one continuous path: no blend between them (a running blend
		# into the path, e.g. after a mode change, keeps running towards the live goal).
		if not (story and _genesis() and GenesisShots.CONTINUOUS_CUES):
			_begin_transition(story)
	if not _user:
		CameraShots.blend(_from, _goal, _blend, _rig)
	_apply()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_zoom(1.0 / ZOOM_STEP)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_zoom(ZOOM_STEP)
		elif mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_RIGHT:
			_press_travel = 0.0 if mb.pressed else -1.0
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _press_travel < 0.0 or (mm.button_mask & (MOUSE_BUTTON_MASK_LEFT | MOUSE_BUTTON_MASK_RIGHT)) == 0:
			return
		_press_travel += mm.relative.length()
		if not InputTuning.is_drag(_press_travel):
			return
		_take_control()
		_rig.yaw -= mm.relative.x * ORBIT_PER_PIXEL
		_rig.pitch += mm.relative.y * ORBIT_PER_PIXEL
		_clamp_shot(_rig)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("camera_reset"):
		reset_to_mode_shot()
		get_viewport().set_input_as_handled()


func _zoom(factor: float) -> void:
	_take_control()
	_rig.distance *= factor
	_clamp_shot(_rig)
	get_viewport().set_input_as_handled()


func _fly(delta: float) -> void:
	if Session.mode != SessionState.Mode.UNIVERSE:
		return
	var v := Input.get_vector("camera_left", "camera_right", "camera_forward", "camera_back")
	if v == Vector2.ZERO:
		return
	_take_control()
	var forward := Vector3(-sin(_rig.yaw), 0.0, -cos(_rig.yaw))
	var right := Vector3(cos(_rig.yaw), 0.0, -sin(_rig.yaw))
	_rig.target += (right * v.x - forward * v.y) * _rig.distance * FLY_SPEED * delta
	_clamp_shot(_rig)


func _take_control() -> void:
	if not _user or _focusing:
		# Input during a focus keeps the camera where it is and hands it to the user.
		_stop_blend()
		_end_focus()
		_user = true
	_user_until = _now() + USER_HOLD


func _evaluate_goal() -> StringName:
	if _genesis():
		return GenesisShots.desired(Session.mode, Session.cinematic, Simulation.genesis, Simulation.time,
			_now(), _goal)
	return CameraShots.desired(Session.mode, Session.cinematic, Simulation.world, Simulation.time, _goal)


## True while the GENESIS scenario is playing (its own shots, cues and limits).
static func _genesis() -> bool:
	return Simulation.scenario == Scenario.GENESIS


## Mode limits of the active scenario.
func _clamp_shot(s: CameraShots.Shot) -> void:
	if _genesis():
		GenesisShots.clamp_shot(s, Session.mode)
	else:
		CameraShots.clamp_shot(s, Session.mode)


## Transition time of a user-driven change (mode, focus, reset, cinematic toggle).
static func _user_blend_duration() -> float:
	return GenesisShots.T_USER if _genesis() else Palette.T_CINEMATIC


## `cue` = the story moved on (GENESIS cranes slowly between cues).
func _begin_transition(cue := false) -> void:
	_stop_blend()
	_from.copy_from(_rig)
	_start_blend(GenesisShots.T_CUE if cue and _genesis() else _user_blend_duration())


## Starts a transition of _blend 0 -> 1 over Palette.T_CINEMATIC of wall-clock time.
## It is a Tween curve (Tween.interpolate_value, sine in-out) driven by MotionClock (wall clock;
## game frame time only under the Movie Maker), not by the frame delta: the engine caps a frame's delta (max_physics_steps_per_frame /
## physics_ticks_per_second = 8/60 s), so on a slow renderer a delta-driven Tween would run
## several times slower than real time and a focus would not settle in the time it promises.
func _start_blend(duration := Palette.T_CINEMATIC) -> void:
	_blend = 0.0
	_blend_start = _now()
	_blend_duration = duration


func _advance_blend() -> void:
	if _blend_duration <= 0.0:
		return
	var x := clampf((_now() - _blend_start) / _blend_duration, 0.0, 1.0)
	_blend = Tween.interpolate_value(0.0, 1.0, x, 1.0, Tween.TRANS_SINE, Tween.EASE_IN_OUT)
	if x >= 1.0:
		_blend = 1.0
		_blend_duration = 0.0


func _end_focus() -> void:
	_focusing = false
	_focus_id = &""


## Stops the running transition where it is (the rig keeps its current pose).
func _stop_blend() -> void:
	_blend_duration = 0.0


## Writes the rig to the camera. The rig is clamped here, after the blend of the frame
## (CameraShots.clamp_rig: never below the floor + clearance, also mid-transition).
func _apply() -> void:
	if _genesis():
		GenesisShots.clamp_rig(_rig)
	else:
		CameraShots.clamp_rig(_rig)
	var pos := _rig.position()
	camera.transform = Transform3D(Basis.IDENTITY, pos).looking_at(_rig.target, Vector3.UP)
	camera.fov = _rig.fov
	camera.h_offset = _rig.h_offset(_aspect())
	_update_trim()


## GENESIS: asks the world for the exposure trim of the cinematic path (GenesisShots.cue_trim) while
## the story camera runs, 1 otherwise; only when it changes (the world eases towards it).
func _update_trim() -> void:
	if not _genesis():
		return
	var story := Session.cinematic and Session.mode == SessionState.Mode.FORGE and not _user
	var k := GenesisShots.cue_trim(Simulation.genesis, Simulation.time) if story else 1.0
	var world := get_parent()
	if world == null or not world.has_method(&"set_exposure_trim"):
		return
	# Compared with the world's own target: a recomposition resets it to 1.
	if is_equal_approx(k, _trim) and is_equal_approx(float(world.call(&"exposure_trim_target")), k):
		return
	_trim = k
	world.call(&"set_exposure_trim", k)


func _aspect() -> float:
	var size := get_viewport().get_visible_rect().size if is_inside_tree() else Vector2(16, 9)
	return size.x / maxf(size.y, 1.0)


## Seek/reset: the story cue always snaps (its framing is a function of the sim time); a user or
## focus framing outside a cue stays (a focused seed does not jump away on a timeline scrub).
func _on_world_rebuilt() -> void:
	if _user and not _is_cue(_evaluate_goal()):
		return
	snap_to_mode_shot()


func _on_mode_changed(_mode: SessionState.Mode) -> void:
	reset_to_mode_shot()


## A new scenario: its own shots from the first frame (no blend across worlds).
func _on_scenario_changed(_id: StringName) -> void:
	snap_to_mode_shot()


## GENESIS style frames (StyleFrames: `style_frame_poses() -> Array` of pose dictionaries).
func style_frame_poses() -> Array:
	return GenesisShots.style_frame_poses()


func _on_cinematic_changed(_enabled: bool) -> void:
	if not _user:
		reset_to_mode_shot()


static func _is_cue(id: StringName) -> bool:
	return String(id).begins_with("cue_")


static func _now() -> float:
	return MotionClock.now()
