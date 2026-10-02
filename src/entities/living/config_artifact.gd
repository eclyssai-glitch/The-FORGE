class_name ConfigArtifact
extends Node3D
## The configuration "file" of the CONFIGURATION MOCK (Loop 5, test 7). Owner: animator (motion);
## look: art-director (&"artifact" material: uniforms presence, edit, valid).
## A card of light with rows of glyphs. Never on screen by itself: MIKU calls it into being over
## her raised palm (APPEAR), a puppet hand takes it (HELD: the card follows that hand), another
## hand writes on it (EDIT: the glyph rows are rewritten one after another while `edit` goes
## 0 -> 1), the change is validated (VALID: a warm pulse) or refused (REJECT: it dims and falls),
## and it is let go (VANISH: it rises and dissolves). Deterministic (no randomness).

enum State { HIDDEN, APPEAR, HELD, EDIT, VALID, REJECT, VANISH }
const STATE_IDS: Array[StringName] = [&"hidden", &"appear", &"held", &"edit", &"valid", &"reject", &"vanish"]

const SIZE := Vector2(0.62, 0.84)
const ROWS := 7
## Seconds the edit takes (tempo 1) and the presence spring.
const T_EDIT := 2.6
const PRESENCE := Vector2(0.9, 1.0)
## Offset of the card from the holding hand (along its palm normal / fingers), units.
const HOLD_OFFSET := 0.55

var state: State = State.HIDDEN
var presence := SecondOrder.new(PRESENCE.x, PRESENCE.y, 0.0, 0.0)
var edit := 0.0
var valid := 0.0
var holder: PuppetHand
var spot := Vector3.ZERO
var card: MeshInstance3D
var material: Material
var glyph_material: Material
var rows: Array[MeshInstance3D] = []
var tempo := 1.0
## Line of the sheet being rewritten (config_artifact `edit_row`).
var edit_row := 1

var _pos := SecondOrder3.new(0.8, 0.8, 0.0)
var _fall := 0.0
var _art := false
var _time := 0.0


func _init() -> void:
	name = "ConfigArtifact"
	material = LivingMaterials.get_material(&"artifact").duplicate()
	glyph_material = LivingMaterials.get_material(&"artifact").duplicate()
	card = MeshInstance3D.new()
	card.name = "Card"
	_art = LivingMaterials.has_art(&"artifact")
	if _art:
		# The art-director's sheet draws its own script (QuadMesh, UV top-left).
		var quad := QuadMesh.new()
		quad.size = SIZE
		card.mesh = quad
		LivingMaterials.set_param(material, &"aspect", SIZE.x / SIZE.y)
	else:
		var q := BoxMesh.new()
		q.size = Vector3(SIZE.x, SIZE.y, 0.012)
		card.mesh = q
	card.material_override = material
	add_child(card)
	for i in (0 if _art else ROWS):
		var r := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(1.0, 0.026, 0.004)
		r.mesh = bm
		r.material_override = glyph_material
		card.add_child(r)
		rows.append(r)
	visible = false


func state_id() -> StringName:
	return STATE_IDS[state]


func is_present() -> bool:
	return state != State.HIDDEN


## Forms over `at` (world), facing `face` (world direction towards the viewer/MIKU).
func appear(at: Vector3, face: Vector3) -> void:
	state = State.APPEAR
	visible = true
	spot = at
	edit = 0.0
	valid = 0.0
	_fall = 0.0
	holder = null
	_pos.reset(at + Vector3.DOWN * 0.15)
	presence.reset(0.0)
	global_transform = Transform3D(Basis.looking_at(-face, Vector3.UP), _pos.y)


func hold(h: PuppetHand) -> void:
	holder = h
	if state == State.APPEAR:
		state = State.HELD


func begin_edit() -> void:
	state = State.EDIT


func validate() -> void:
	state = State.VALID
	valid = 0.0


func reject() -> void:
	state = State.REJECT


func vanish() -> void:
	if state != State.HIDDEN:
		state = State.VANISH


func edit_done() -> bool:
	return edit >= 1.0


func step(dt: float) -> void:
	if state == State.HIDDEN:
		return
	_time += dt
	match state:
		State.APPEAR, State.HELD, State.EDIT, State.VALID:
			presence.step(1.0, dt)
		State.REJECT:
			presence.step(0.0, dt * 0.5)
			_fall += dt
		State.VANISH:
			presence.step(0.0, dt)
	if state == State.EDIT:
		edit = minf(edit + dt * tempo / T_EDIT, 1.0)
	if state == State.VALID:
		valid = minf(valid + dt * 1.6, 1.0)
	var goal := spot
	var facing := Vector3.BACK
	if holder != null and is_instance_valid(holder) and holder.active:
		goal = holder.global_position + holder.palm_s.y * HOLD_OFFSET + holder.point_s.y * HOLD_OFFSET * 0.4
		facing = holder.palm_s.y
	if state == State.VANISH:
		goal += Vector3.UP * (1.0 - presence.y) * 0.6
	if state == State.REJECT:
		goal += Vector3.DOWN * _fall * _fall * 0.8
	_pos.step(goal, dt)
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	var look := (cam.global_position - _pos.y) if cam != null else facing
	if look.length_squared() < 1e-6:
		look = Vector3.BACK
	var tilt := Basis(Vector3.BACK, sin(_time * 0.7) * 0.03 + (_fall * 0.8 if state == State.REJECT else 0.0))
	global_transform = Transform3D(Basis.looking_at(-look.normalized(), Vector3.UP) * tilt, _pos.y)
	var p := clampf(presence.y, 0.0, 1.0)
	scale = Vector3.ONE * lerpf(0.7, 1.0, p)
	LivingMaterials.set_param(material, &"presence", p)
	LivingMaterials.set_param(material, &"edit", edit)
	LivingMaterials.set_param(material, &"edit_row", float(edit_row))
	LivingMaterials.set_param(material, &"validated", valid)
	LivingMaterials.set_param(glyph_material, &"presence", p)
	LivingMaterials.set_param(glyph_material, &"validated", valid)
	_layout_rows()
	if state == State.VANISH and presence.y < 0.02 or state == State.REJECT and _fall > 2.0:
		state = State.HIDDEN
		visible = false
		holder = null


## Glyph rows: each row is rewritten in turn while editing (its width moves from the old line to
## the new one); deterministic widths.
func _layout_rows() -> void:
	for i in rows.size():
		var old_w := 0.35 + 0.45 * absf(sin(float(i) * 2.17 + 0.3))
		var new_w := 0.3 + 0.5 * absf(sin(float(i) * 1.31 + 1.9))
		var k := clampf(edit * float(ROWS) - float(i), 0.0, 1.0)
		var w := lerpf(old_w, new_w, k * k * (3.0 - 2.0 * k))
		var y := SIZE.y * 0.36 - float(i) * SIZE.y * 0.105
		var r := rows[i]
		r.scale = Vector3(SIZE.x * 0.8 * w, 1.0, 1.0)
		r.position = Vector3(-SIZE.x * 0.4 + SIZE.x * 0.4 * w, y, 0.009)
