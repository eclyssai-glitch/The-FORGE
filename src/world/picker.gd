class_name Picker
extends Node
## Mouse picking of 3D entities. Casts a ray from the active camera
## (`get_viewport().get_camera_3d()`) against collision layer 2 ("pickable") and forwards the
## hit's `entity_id` meta to `Session.select` (left click) or `Session.hover` (mouse motion).
## A left press whose accumulated travel (every movement between press and release, not just
## the net displacement) reaches InputTuning.DRAG_THRESHOLD_PX is a camera orbit drag, not a
## click. Clicking empty space clears the selection (the `deselect` action is handled by
## Shortcuts, src/core/shortcuts.gd).
## Uses `_unhandled_input`, so events consumed by the UI never reach it; it never marks events
## as handled, so the camera rig still receives the same drags.
## Physics queries run in `_physics_process` (the safe place to use the direct space state).

const PICK_MASK := 2
const RAY_LENGTH := 500.0

var _pressing := false
## Accumulated pointer travel (px) of the current left press and the last pointer position.
var _travel := 0.0
var _last_pos := Vector2.ZERO
var _pending_click := false
var _click_pos := Vector2.ZERO
var _pending_hover := false
var _hover_pos := Vector2.ZERO


func _init() -> void:
	name = "Picker"


func _unhandled_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb and mb.button_index == MOUSE_BUTTON_LEFT:
		if mb.pressed:
			_pressing = true
			_travel = 0.0
			_last_pos = mb.position
		elif _pressing:
			_pressing = false
			_travel += _last_pos.distance_to(mb.position)
			if not InputTuning.is_drag(_travel):
				_pending_click = true
				_click_pos = mb.position
		return
	var mm := event as InputEventMouseMotion
	if mm:
		if _pressing:
			_travel += _last_pos.distance_to(mm.position)
			_last_pos = mm.position
		_pending_hover = true
		_hover_pos = mm.position


func _physics_process(_delta: float) -> void:
	if _pending_click:
		_pending_click = false
		Session.select(pick_at(_click_pos))
	if _pending_hover:
		_pending_hover = false
		# No hover changes while dragging the camera.
		if not _pressing or not InputTuning.is_drag(_travel):
			Session.hover(pick_at(_hover_pos))


## Entity under a viewport position, seen from the active camera; &"" if none.
func pick_at(screen_pos: Vector2) -> StringName:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return &""
	var from := cam.project_ray_origin(screen_pos)
	return pick_ray(from, from + cam.project_ray_normal(screen_pos) * RAY_LENGTH)


## Entity hit first by the segment from -> to on the pick layer; &"" if none.
func pick_ray(from: Vector3, to: Vector3) -> StringName:
	var vp := get_viewport()
	if vp == null or vp.find_world_3d() == null:
		return &""
	var query := PhysicsRayQueryParameters3D.create(from, to, PICK_MASK)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	return entity_id_of_hit(vp.find_world_3d().direct_space_state.intersect_ray(query))


## Accumulated length of a pointer path (press, motions..., release) in px.
static func path_length(points: PackedVector2Array) -> float:
	var total := 0.0
	for i in range(1, points.size()):
		total += points[i - 1].distance_to(points[i])
	return total


## True when a pointer path (press, motions..., release) is a click, not an orbit drag.
static func is_click_path(points: PackedVector2Array) -> bool:
	return not InputTuning.is_drag(path_length(points))


## Entity id carried by a ray hit: the collider's "entity_id" meta, else its parent's; &"" if none.
static func entity_id_of_hit(hit: Dictionary) -> StringName:
	if hit.is_empty():
		return &""
	return entity_id_of(hit.get("collider") as Object)


static func entity_id_of(collider: Object) -> StringName:
	if collider == null:
		return &""
	if collider.has_meta(&"entity_id"):
		return StringName(collider.get_meta(&"entity_id"))
	var node := collider as Node
	if node and node.get_parent() and node.get_parent().has_meta(&"entity_id"):
		return StringName(node.get_parent().get_meta(&"entity_id"))
	return &""
