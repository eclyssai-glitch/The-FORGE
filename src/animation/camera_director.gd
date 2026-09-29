class_name CameraDirector
extends Node3D
## The only camera of the world. Owner: animator.
## Orbit rig (target, yaw, pitch, distance, fov, offset — see CameraShots.Shot) that follows
## the shot of the current mode, and — when Session.cinematic in FORGE — the cue of the event
## being told (approach on activation, pull back on fragments, slow orbit while building, low
## angle on verification, orbital reveal on the final form).
##
## Transitions between shots are real-time Tweens (Palette.T_CINEMATIC) of a blend factor from
## a snapshot to the live goal, so moving goals (orbits) stay smooth. After Simulation.seek/reset
## (`world_rebuilt`) the camera snaps to the goal without a tween.
## Input (unhandled, so the UI consumes first): drag with left/right button = orbit, wheel = zoom,
## WASD = fly (UNIVERSE), `camera_reset` = back to the mode shot. A press only orbits once its
## accumulated travel is a drag for InputTuning.is_drag — the same threshold the Picker uses, so
## a press is either a click or an orbit, never both. Input suspends cues for
## USER_HOLD seconds; outside a cue the user's framing stays until reset or mode change.
## Group "camera_director": automation calls snap_to_mode_shot() after each seek/mode change.

const GROUP := &"camera_director"
## Seconds of user control before cinematic cues take the camera back.
const USER_HOLD := 6.0
## Orbit radians per dragged pixel; zoom factor per wheel notch; fly speed in distances/s.
const ORBIT_PER_PIXEL := 0.0055
const ZOOM_STEP := 1.1
const FLY_SPEED := 0.5

var camera: Camera3D

var _rig := CameraShots.Shot.new()
var _from := CameraShots.Shot.new()
var _goal := CameraShots.Shot.new()
## Tweened 0..1 from _from to the live goal.
var _blend := 1.0
var _tween: Tween
var _shot_id: StringName = &""
var _user := false
var _user_until := 0.0
var _press_travel := -1.0


func _ready() -> void:
	add_to_group(GROUP)
	process_mode = Node.PROCESS_MODE_ALWAYS
	camera = Camera3D.new()
	camera.name = "Camera"
	camera.near = 0.05
	camera.far = 600.0
	add_child(camera)
	camera.current = true
	Session.mode_changed.connect(_on_mode_changed)
	Session.cinematic_changed.connect(_on_cinematic_changed)
	Simulation.world_rebuilt.connect(snap_to_mode_shot)
	snap_to_mode_shot()


## Jumps (no tween) to the goal of the current state: the cinematic cue in FORGE when
## Session.cinematic, otherwise the mode shot. Clears user control.
func snap_to_mode_shot() -> void:
	_kill_tween()
	_user = false
	_press_travel = -1.0
	_shot_id = _evaluate_goal()
	_rig.copy_from(_goal)
	_from.copy_from(_goal)
	_blend = 1.0
	_apply()


## Tweens back to the goal of the current state (what `camera_reset` does).
func reset_to_mode_shot() -> void:
	_user = false
	_shot_id = _evaluate_goal()
	_begin_transition()


## Accumulated pointer travel (px) of the current left/right press; -1 when no press.
func press_travel() -> float:
	return _press_travel


## Current rig (read-only use: HUD/debug/tests).
func rig() -> CameraShots.Shot:
	return _rig


func _process(delta: float) -> void:
	_fly(delta)
	var id := _evaluate_goal()
	if _user:
		# The user framing holds; cues take over again after USER_HOLD seconds.
		if _is_cue(id) and _now() >= _user_until:
			_user = false
			_shot_id = id
			_begin_transition()
	elif id != _shot_id:
		_shot_id = id
		_begin_transition()
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
		CameraShots.clamp_shot(_rig, Session.mode)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("camera_reset"):
		reset_to_mode_shot()
		get_viewport().set_input_as_handled()


func _zoom(factor: float) -> void:
	_take_control()
	_rig.distance *= factor
	CameraShots.clamp_shot(_rig, Session.mode)
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
	CameraShots.clamp_shot(_rig, Session.mode)


func _take_control() -> void:
	if not _user:
		_kill_tween()
		_user = true
	_user_until = _now() + USER_HOLD


func _evaluate_goal() -> StringName:
	return CameraShots.desired(Session.mode, Session.cinematic, Simulation.world, Simulation.time, _goal)


func _begin_transition() -> void:
	_kill_tween()
	_from.copy_from(_rig)
	_blend = 0.0
	_tween = create_tween()
	_tween.tween_property(self, "_blend", 1.0, Palette.T_CINEMATIC) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _kill_tween() -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = null


func _apply() -> void:
	var pos := _rig.position()
	camera.transform = Transform3D(Basis.IDENTITY, pos).looking_at(_rig.target, Vector3.UP)
	camera.fov = _rig.fov
	var size := get_viewport().get_visible_rect().size if is_inside_tree() else Vector2(16, 9)
	camera.h_offset = _rig.h_offset(size.x / maxf(size.y, 1.0))


func _on_mode_changed(_mode: SessionState.Mode) -> void:
	reset_to_mode_shot()


func _on_cinematic_changed(_enabled: bool) -> void:
	if not _user:
		reset_to_mode_shot()


static func _is_cue(id: StringName) -> bool:
	return String(id).begins_with("cue_")


static func _now() -> float:
	return Time.get_ticks_msec() * 0.001
