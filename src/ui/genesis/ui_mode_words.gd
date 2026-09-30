class_name UiModeWords
extends HBoxContainer
## GENESIS mode selector: three spaced words, UNIVERSE · FORGE · OBSERVATORY. The active word is in
## full ink, the others faint (soft under the pointer); a short pearl hairline glides under the
## active word. Every change is a sine fade/glide (Palette.T_BASE), nothing pops. Writes
## Session.set_mode; follows Session.mode_changed (keys 1/2/3 or any other source).

const MARK_WIDTH := 18.0
const MARK_DROP := 3.0

var words: Array[Button] = []
## Position/width of the hairline under the active word (animated).
var mark_x := -1.0

var _hover := -1
var _mark_tween: Tween


func _init() -> void:
	name = "GenesisModes"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 2)
	for m in SessionState.MODE_NAMES.size():
		var b := UiKit.button(SessionState.MODE_NAMES[m], &"ModeWord")
		b.name = SessionState.MODE_NAMES[m].capitalize()
		b.self_modulate.a = Palette.UI_INK_FAINT.a
		b.pressed.connect(_on_word_pressed.bind(m))
		b.mouse_entered.connect(_on_hover.bind(m, true))
		b.mouse_exited.connect(_on_hover.bind(m, false))
		add_child(b)
		words.append(b)
		if m < SessionState.MODE_NAMES.size() - 1:
			var dot := UiKit.label("·", &"WordFaint")
			dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			add_child(dot)


func _ready() -> void:
	Session.mode_changed.connect(_on_mode_changed)
	resized.connect(_place_mark.bind(false))
	sort_children.connect(_place_mark.bind(false))
	refresh(false)


## Ink level of word `i` for the current mode and pointer.
func word_alpha(i: int) -> float:
	if i == Session.mode:
		return Palette.UI_INK.a
	return Palette.UI_INK_SOFT.a if i == _hover else Palette.UI_INK_FAINT.a


func refresh(animated := true) -> void:
	for i in words.size():
		var a := word_alpha(i)
		var w := words[i]
		var old: Variant = w.get_meta(&"ink_tween") if w.has_meta(&"ink_tween") else null
		if old is Tween and (old as Tween).is_valid():
			(old as Tween).kill()
		if animated and is_inside_tree():
			var tw := w.create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
			tw.tween_property(w, "self_modulate:a", a, Palette.T_BASE)
			w.set_meta(&"ink_tween", tw)
		else:
			w.self_modulate.a = a
	_place_mark(animated)


func _place_mark(animated: bool) -> void:
	var w := words[Session.mode]
	var target := w.position.x + w.size.x * 0.5
	if _mark_tween and _mark_tween.is_valid():
		_mark_tween.kill()
	if not animated or mark_x < 0.0 or not is_inside_tree():
		mark_x = target
		queue_redraw()
		return
	_mark_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_mark_tween.tween_method(_set_mark_x, mark_x, target, Palette.T_BASE)


func _set_mark_x(x: float) -> void:
	mark_x = x
	queue_redraw()


func _draw() -> void:
	if mark_x < 0.0 or words.is_empty():
		return
	var w := words[Session.mode]
	var y := floorf(w.position.y + w.size.y - MARK_DROP - 4.0) + 0.5
	draw_line(Vector2(mark_x - MARK_WIDTH * 0.5, y), Vector2(mark_x + MARK_WIDTH * 0.5, y), Palette.UI_INK_SOFT, 1.0, true)


func _on_word_pressed(m: int) -> void:
	if m != Session.mode:
		UiKit.ui_sound(self, &"ui_tick")
	Session.set_mode(m as SessionState.Mode)


func _on_hover(m: int, on: bool) -> void:
	_hover = m if on else (-1 if _hover == m else _hover)
	refresh(true)


func _on_mode_changed(_m: SessionState.Mode) -> void:
	refresh(true)
