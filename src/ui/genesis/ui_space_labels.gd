class_name UiSpaceLabels
extends Control
## Names written in space, beside the bodies they name (GENESIS). For each entity of the active
## scenario, the visual root is the first visible Node3D of group Session.entity_group(id); its
## position is projected with the current Camera3D (unproject_position) and a thin leader (a short
## diagonal, then a horizontal run) leads from the body's edge to the name. No node, no camera, a
## body behind the camera or off screen, or a body not formed yet (status UNFORMED) = no label.
##
## Which labels: FORGE / UNIVERSE — only the body under the pointer (Session.hovered) or selected;
## OBSERVATORY — every body, with its sign (UiGlyphs) and its symbolic kind under the name
## (subagent · documentation · skills · memory …): the vault read as astronomy. The selected body's
## label yields to its floating card (`card_id`), and the leader then runs to the card instead.
## Labels fade in/out with a sine over Palette.T_LABEL. Placement is radial (away from the frame
## centre, around the bodies, never on them) and each name sits on a feathered night veil.
##
## Optional metadata on the entity root (set by the 3D modules; see docs/VISUAL_DIRECTION.md §8):
##   label_anchor: Vector3 (local offset) or Node3D — the point the label points at (default: origin)
##   label_radius: float (world units) — body radius for the leader start (default: mesh AABB)
## Entities in NEEDS_ANCHOR (their root sits at another body's centre) only get a label with a
## label_anchor. Draws only while something is visible; never catches the mouse.

const NEEDS_ANCHOR: Array[StringName] = [&"belt_memory", &"relations"]
const META_ANCHOR := &"label_anchor"
const META_RADIUS := &"label_radius"
## Symbolic kind shown under the name in OBSERVATORY, by GenesisCatalog kind name.
const KIND_WORDS := {
	"CENTRAL AGENT": "central agent",
	"AUXILIARY HAND": "auxiliary hand",
	"SUBAGENT": "subagent",
	"DOCUMENTATION": "documentation",
	"SKILLS": "skills",
	"MEMORY": "memory",
	"RELATIONS": "links",
}
## Screen margin (px) outside which a body is not labelled.
const SCREEN_MARGIN := 8.0
const GLYPH_R := 4.0
const LINE_GAP := 2.0

## Entity whose floating card is open (its label yields to the card).
var card_id: StringName = &""
## The card (for the leader to it); may be null.
var card: Control
## Camera used instead of the viewport's (tests). null = get_viewport().get_camera_3d().
var camera_override: Camera3D

## id -> {"p": fade 0..1, "on": wanted, "seen": anchor projected, "pos": Vector2, "r": float (px)}
var _state: Dictionary = {}
var _drawn_any := false
## Feathered veil drawn under each name (colour set per label with its fade).
var _veil := StyleBoxFlat.new()


func _init() -> void:
	name = "SpaceLabels"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_veil.set_corner_radius_all(14)
	_veil.shadow_size = 16
	_veil.anti_aliasing = true


func _ready() -> void:
	Simulation.scenario_changed.connect(func(_id: StringName) -> void: _state.clear())


# ------------------------------------------------------------------ pure helpers

## Visual root of entity `id`: the first Node3D of its group that is visible in the tree, or null.
static func entity_anchor(tree: SceneTree, id: StringName) -> Node3D:
	if tree == null:
		return null
	for n in tree.get_nodes_in_group(Session.entity_group(id)):
		var n3 := n as Node3D
		if n3 and n3.is_inside_tree() and n3.is_visible_in_tree():
			return n3
	return null


## World point a label of `node` points at (label_anchor metadata, else the node's origin).
static func anchor_point(node: Node3D) -> Vector3:
	if node.has_meta(META_ANCHOR):
		var a: Variant = node.get_meta(META_ANCHOR)
		if a is Vector3:
			return node.to_global(a)
		if a is Node3D and is_instance_valid(a) and (a as Node3D).is_inside_tree():
			return (a as Node3D).global_position
	return node.global_position


## Body radius (world units) of `node`: label_radius metadata, else half the horizontal extent of the
## first GeometryInstance3D found under it (global scale), else 0.5.
static func body_radius(node: Node3D) -> float:
	if node.has_meta(META_RADIUS):
		return float(node.get_meta(META_RADIUS))
	var geo: GeometryInstance3D = node as GeometryInstance3D
	if geo == null:
		var found := node.find_children("*", "GeometryInstance3D", true, false)
		if not found.is_empty():
			geo = found[0] as GeometryInstance3D
	if geo == null:
		return 0.5
	var aabb := geo.get_aabb()
	var s := geo.global_basis.get_scale()
	return 0.25 * (aabb.size.x * absf(s.x) + aabb.size.z * absf(s.z))


## True when `id` gets a label in `mode` given the pointer and the selection.
static func wanted(id: StringName, mode: SessionState.Mode, hovered: StringName, selected: StringName) -> bool:
	if mode == SessionState.Mode.OBSERVATORY:
		return true
	return id == hovered or id == selected


static func kind_word(info: Dictionary) -> String:
	return String(KIND_WORDS.get(String(info.get("kind_name", "")), ""))


## Sine fade of a 0..1 progress (what the eye sees).
static func ease_alpha(p: float) -> float:
	return 0.5 - 0.5 * cos(PI * clampf(p, 0.0, 1.0))


func camera() -> Camera3D:
	if camera_override and is_instance_valid(camera_override):
		return camera_override
	return get_viewport().get_camera_3d() if is_inside_tree() else null


## Projected anchor of `id` this frame: {"pos": Vector2, "r": float} or {} when it is not on screen.
func screen_anchor(id: StringName) -> Dictionary:
	var st: Dictionary = _state.get(id, {})
	if st.is_empty() or not bool(st["seen"]):
		return {}
	return {"pos": st["pos"], "r": st["r"]}


## Fade progress of the label of `id` (0 hidden .. 1 fully shown).
func label_progress(id: StringName) -> float:
	return float((_state.get(id, {}) as Dictionary).get("p", 0.0))


## Ids whose label is visible now (progress > 0).
func shown_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for id: StringName in _state:
		if float(_state[id]["p"]) > 0.0:
			out.append(id)
	return out


# ------------------------------------------------------------------ update

func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	update_labels(delta)


## Projects every entity and advances the fades by `delta` seconds.
func update_labels(delta: float) -> void:
	var cam := camera()
	var vp := get_viewport_rect().size
	var any := false
	var scenario := Simulation.scenario
	for id in Scenario.entity_ids(scenario):
		var st: Dictionary = _state.get(id, {"p": 0.0, "on": false, "seen": false, "pos": Vector2.ZERO, "r": 0.0})
		st["seen"] = false
		var node := entity_anchor(get_tree(), id) if cam else null
		if node and not (NEEDS_ANCHOR.has(id) and not node.has_meta(META_ANCHOR)):
			var world := anchor_point(node)
			if not cam.is_position_behind(world):
				var c2 := cam.unproject_position(world)
				var edge := cam.unproject_position(world + cam.global_basis.x * body_radius(node))
				st["pos"] = c2
				st["r"] = c2.distance_to(edge)
				st["seen"] = Rect2(Vector2.ONE * -SCREEN_MARGIN, vp + Vector2.ONE * SCREEN_MARGIN * 2.0).has_point(c2)
		var on: bool = st["seen"] and id != card_id \
			and wanted(id, Session.mode, Session.hovered, Session.selected) \
			and Scenario.entity_status(scenario, id, Simulation.state) != "UNFORMED"
		st["on"] = on
		st["p"] = move_toward(float(st["p"]), 1.0 if on else 0.0, delta / Palette.T_LABEL)
		_state[id] = st
		any = any or float(st["p"]) > 0.0
	var card_leader := card_id != &"" and card != null and card.is_visible_in_tree() \
		and bool((_state.get(card_id, {}) as Dictionary).get("seen", false))
	if any or card_leader or _drawn_any:
		queue_redraw()
	_drawn_any = any or card_leader


# ------------------------------------------------------------------ drawing

func _draw() -> void:
	var vp := get_viewport_rect().size
	var observatory := Session.mode == SessionState.Mode.OBSERVATORY
	var title_font := get_theme_font(&"font", &"Word")
	var kind_font := get_theme_font(&"font", &"NoteFaint")
	var fs := get_theme_font_size(&"font_size", &"Word")
	var line_h := title_font.get_height(fs)
	# Obstacles: every body on screen (its disc) and the open card.
	var discs: Array[Rect2] = []
	for id: StringName in _state:
		if bool(_state[id]["seen"]):
			discs.append(_disc(_state[id]))
	var card_rect := Rect2()
	if card and card.is_visible_in_tree():
		card_rect = card.get_global_rect()
		card_rect.position -= get_global_rect().position
	var placed: Array[Rect2] = []
	var ids: Array = _state.keys()
	# Nearest to the bottom first: they keep their natural place, the others move.
	ids.sort_custom(func(a: StringName, b: StringName) -> bool:
		return (_state[a]["pos"] as Vector2).y > (_state[b]["pos"] as Vector2).y)
	for id: StringName in ids:
		var st: Dictionary = _state[id]
		var a := ease_alpha(float(st["p"]))
		if a <= 0.0 or not bool(st["seen"]):
			continue
		var info := Scenario.entity_info(Simulation.scenario, id)
		var title := String(info.get("title", String(id)))
		var kind := kind_word(info) if observatory else ""
		var glyph := UiGlyphs.kind_glyph(String(info.get("kind_name", ""))) if observatory else &""
		var text_w := title_font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		if kind != "":
			text_w = maxf(text_w, kind_font.get_string_size(kind, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)
		var glyph_w := (GLYPH_R * 2.0 + 8.0) if glyph != &"" else 0.0
		var block := Vector2(glyph_w + text_w, line_h * (2.0 if kind != "" else 1.0) + (LINE_GAP if kind != "" else 0.0))
		var lay := place_label(st["pos"], float(st["r"]), block, line_h, vp, placed, discs, _disc(st))
		var rect: Rect2 = lay["rect"]
		placed.append(rect)
		# Under the open card a label steps back (the card is the focus).
		if card_rect.size != Vector2.ZERO and card_rect.grow(4.0).intersects(rect):
			a *= 0.18
		# A soft night veil under the name (legible over the bright nebula and the hair; no frame).
		var veil := Palette.UI_SHADE
		veil.a *= a
		_veil.bg_color = veil
		_veil.shadow_color = veil
		draw_style_box(_veil, rect.grow_individual(8.0, 3.0, 8.0, 3.0))
		var thread := Palette.UI_THREAD
		thread.a *= a
		draw_polyline(PackedVector2Array([lay["start"], lay["knee"], lay["end"]]), thread, 1.0, true)
		var x := rect.position.x
		var base := rect.position.y + title_font.get_ascent(fs)
		if glyph != &"":
			var g := Palette.UI_INK_SOFT
			g.a *= a
			UiGlyphs.draw(self, glyph, Vector2(x + GLYPH_R + 1.0, rect.position.y + line_h * 0.5), GLYPH_R, g)
			x += glyph_w
		var ink := Palette.UI_INK
		ink.a *= a
		_text(title_font, Vector2(x, base), title, fs, ink, a)
		if kind != "":
			var faint := Palette.UI_INK_FAINT
			faint.a *= a
			_text(kind_font, Vector2(x, base + line_h + LINE_GAP), kind, fs, faint, a)
	_draw_card_leader()


## Screen disc (as a rect) of a projected body state, with a small margin.
static func _disc(st: Dictionary) -> Rect2:
	var r := maxf(float(st["r"]), 3.0) + 4.0
	return Rect2((st["pos"] as Vector2) - Vector2(r, r), Vector2(r, r) * 2.0)


## Layout of one label for a body at `pos` (screen radius `r`): radial — the leader leaves the body
## along the direction from the frame centre to the body (labels fan out around the composition
## instead of piling up on one side), then runs horizontally to the name. Tries that direction, then
## directions turned by 30°, 60°, 90°, 135° either way and finally inward, each at two leader lengths,
## and keeps the first place inside the screen margins that touches neither the labels already
## `placed` nor the other bodies' `discs` (`own` is the body's own disc). Falls back to the first try.
## Returns {"start", "knee", "end": Vector2, "rect": Rect2, "side": float}.
static func place_label(pos: Vector2, r: float, block: Vector2, line_h: float, vp: Vector2,
		placed: Array[Rect2], discs: Array[Rect2], own: Rect2) -> Dictionary:
	var radial := pos - vp * 0.5
	var base := radial.normalized() if radial.length() > 24.0 else Vector2(0.7071, -0.7071)
	var first := {}
	var screen := Rect2(Vector2.ONE * 8.0, vp - Vector2.ONE * 16.0)
	for turn: float in [0.0, 30.0, -30.0, 60.0, -60.0, 90.0, -90.0, 135.0, -135.0, 180.0]:
		var dir := base.rotated(deg_to_rad(turn))
		# Never a vertical leader: the name always sits to one side of its knee.
		var side := 1.0 if dir.x >= 0.0 else -1.0
		if absf(dir.x) < 0.35:
			dir = Vector2(side * 0.35, signf(dir.y) if dir.y != 0.0 else -1.0).normalized()
		var start := pos + dir * (r + 5.0)
		for reach: float in [1.0, 2.2]:
			var knee := start + dir * Palette.UI_LEADER * reach
			var end_x := knee.x + side * Palette.UI_LEADER_RUN
			var text_x := end_x + side * 6.0
			var rect := Rect2(Vector2(text_x if side > 0.0 else text_x - block.x, knee.y - line_h * 0.5), block)
			var lay := {"start": start, "knee": knee, "end": Vector2(end_x, knee.y), "rect": rect, "side": side}
			if first.is_empty():
				first = lay
			if not screen.encloses(rect) or _hits(rect, placed, discs, own):
				continue
			return lay
	return first


## Screen discs (as rects) of every body projected on screen this frame (the card avoids them).
func body_discs() -> Array[Rect2]:
	var out: Array[Rect2] = []
	for id: StringName in _state:
		if bool(_state[id]["seen"]):
			out.append(_disc(_state[id]))
	return out


static func _hits(rect: Rect2, placed: Array[Rect2], discs: Array[Rect2], own: Rect2) -> bool:
	for o in placed:
		if o.grow(3.0).intersects(rect):
			return true
	for d in discs:
		if d != own and d.intersects(rect):
			return true
	return false


func _text(font: Font, at: Vector2, text: String, fs: int, col: Color, a: float) -> void:
	var shade := Palette.UI_SHADE
	shade.a *= a
	draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 3, shade)
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


## Leader from the selected body's edge to the nearest side of its floating card.
func _draw_card_leader() -> void:
	if card_id == &"" or card == null or not card.is_visible_in_tree():
		return
	var st: Dictionary = _state.get(card_id, {})
	if st.is_empty() or not bool(st["seen"]):
		return
	var r := card.get_global_rect()
	r.position -= get_global_rect().position
	var pos: Vector2 = st["pos"]
	var to := Vector2(r.position.x if pos.x < r.get_center().x else r.end.x, clampf(pos.y, r.position.y + 10.0, r.end.y - 10.0))
	var dir := (to - pos).normalized()
	var from := pos + dir * (float(st["r"]) + 5.0)
	if from.distance_to(to) < 8.0:
		return
	var thread := Palette.UI_THREAD
	thread.a *= card.modulate.a
	draw_line(from, to, thread, 1.0, true)
	draw_circle(from, 1.5, thread, true, -1.0, true)
