class_name UiKindLegend
extends VBoxContainer
## OBSERVATORY legend: how to read the vault as astronomy, one faint line per sign —
## planet · subagent, moon · documentation, ring · skills, belt · memory, thread · link.
## Never catches the mouse.

const ROWS: Array = [
	[&"planet", "planet", "subagent"],
	[&"moon", "moon", "documentation"],
	[&"ring", "ring", "skills"],
	[&"belt", "belt", "memory"],
	[&"thread", "thread", "link"],
]


func _init() -> void:
	name = "KindLegend"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 3)
	for r: Array in ROWS:
		var h := UiKit.hbox(10)
		h.name = String(r[1]).capitalize()
		var sign := Control.new()
		sign.custom_minimum_size = Vector2(12, 12)
		sign.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		sign.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var g: StringName = r[0]
		sign.draw.connect(func() -> void: UiGlyphs.draw(sign, g, sign.size * 0.5, 4.5, Palette.UI_INK_SOFT))
		h.add_child(sign)
		h.add_child(UiKit.label(String(r[1]), &"WordSoft"))
		h.add_child(UiKit.label("·", &"WordFaint"))
		h.add_child(UiKit.label(String(r[2]), &"WordFaint"))
		add_child(h)
