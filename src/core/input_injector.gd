class_name InputInjector
extends RefCounted
## Injects REAL input events through Input.parse_input_event — the same path as the OS's mouse and
## keyboard (GUI first, then _unhandled_input: Shortcuts, Picker, CameraDirector). Used only by
## automation (captures, smoke, recording tours) to play the LIVING user tests with genuine
## clicks and typing; the game never calls it on its own.


## A left click at viewport position `pos`: motion to it, press, release (no travel = a click
## for Picker and CameraDirector).
static func click(pos: Vector2) -> void:
	var mm := InputEventMouseMotion.new()
	mm.position = pos
	mm.global_position = pos
	Input.parse_input_event(mm)
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = pos
	down.global_position = pos
	down.button_mask = MOUSE_BUTTON_MASK_LEFT
	Input.parse_input_event(down)
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = pos
	up.global_position = pos
	Input.parse_input_event(up)


## Press + release of a key (e.g. KEY_ENTER, KEY_ESCAPE).
static func tap(keycode: Key) -> void:
	for pressed in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = keycode
		ev.physical_keycode = keycode
		ev.pressed = pressed
		Input.parse_input_event(ev)


## One typed character (unicode only, no key code: no action or shortcut can match it).
static func type_char(c: String) -> void:
	if c.is_empty():
		return
	var ev := InputEventKey.new()
	ev.unicode = c.unicode_at(0)
	ev.pressed = true
	Input.parse_input_event(ev)
	var up := InputEventKey.new()
	up.unicode = 0
	up.pressed = false
	Input.parse_input_event(up)


## Screen positions (viewport coordinates) where entity `id` can be clicked: the centre of each
## pick body (collision layer Picker.PICK_MASK, meta `entity_id` = id) and a few points around it,
## in front of the camera and inside the viewport. When `picker` is given (call from
## _physics_process), only points whose ray really hits `id` are kept. Empty = not clickable.
static func entity_click_points(viewport: Viewport, id: StringName, picker: Picker = null) -> PackedVector2Array:
	var out := PackedVector2Array()
	var cam := viewport.get_camera_3d() if viewport else null
	if cam == null:
		return out
	var rect := viewport.get_visible_rect()
	var tree := viewport.get_tree()
	for body: Node in tree.root.find_children("*", "CollisionObject3D", true, false):
		var co := body as CollisionObject3D
		if co == null or Picker.entity_id_of(co) != id or (co.collision_layer & Picker.PICK_MASK) == 0:
			continue
		if not co.is_inside_tree():
			continue
		var centre := co.global_position
		for s: Node in co.find_children("*", "CollisionShape3D", false, false):
			centre = (s as Node3D).global_position
			break
		if cam.is_position_behind(centre):
			continue
		var base := cam.unproject_position(centre)
		for off: Vector2 in [Vector2.ZERO, Vector2(0, -24), Vector2(0, 24), Vector2(-24, 0), Vector2(24, 0),
				Vector2(0, -60), Vector2(0, 60), Vector2(-48, -48), Vector2(48, 48)]:
			var p := base + off
			if not rect.has_point(p):
				continue
			if picker != null and picker.pick_at(p) != id:
				continue
			out.append(p)
	return out


## The world's Picker (first node of class Picker in the tree), or null.
static func find_picker(tree: SceneTree) -> Picker:
	for n in tree.root.find_children("*", "Node", true, false):
		if n is Picker:
			return n
	return null
