class_name LivingCallLine
extends CanvasLayer
## PLACEHOLDER of the LIVING call line ("sussurro"): a thin text line low in the frame where the
## user speaks to MIKU. Minimal on purpose — the final, diegetic look is the art-director's
## (a UI node in group LivingInteraction.CALL_LINE_UI_GROUP replaces this placeholder entirely).
## Created by LivingInteraction on the first Session.call_line_changed(true) when no UI provides
## the line. Enter submits (Session.submit_call), Esc or losing focus closes
## (Session.close_call_line). No box, no menu, no button: one hairline and the text.

const WIDTH_SHARE := 0.42
const BOTTOM_MARGIN := 64.0
const HEIGHT := 34.0

var line: LineEdit


func _init() -> void:
	name = "LivingCallLine"
	layer = 6


func _ready() -> void:
	line = LineEdit.new()
	line.name = "CallLineEdit"
	line.placeholder_text = "Miku, …"
	line.max_length = SessionState.CALL_MAX_CHARS
	line.alignment = HORIZONTAL_ALIGNMENT_CENTER
	line.context_menu_enabled = false
	line.select_all_on_focus = true
	line.anchor_left = 0.5 - WIDTH_SHARE * 0.5
	line.anchor_right = 0.5 + WIDTH_SHARE * 0.5
	line.anchor_top = 1.0
	line.anchor_bottom = 1.0
	line.offset_top = -BOTTOM_MARGIN - HEIGHT
	line.offset_bottom = -BOTTOM_MARGIN
	var empty := StyleBoxEmpty.new()
	var under := StyleBoxFlat.new()
	under.bg_color = Palette.CLEAR
	under.border_color = Palette.UI_THREAD
	under.border_width_bottom = 1
	line.add_theme_stylebox_override(&"normal", under)
	line.add_theme_stylebox_override(&"focus", empty)
	line.add_theme_stylebox_override(&"read_only", under)
	line.add_theme_color_override(&"font_color", Palette.UI_INK)
	line.add_theme_color_override(&"font_placeholder_color", Palette.UI_INK_FAINT)
	line.add_theme_color_override(&"caret_color", Palette.UI_INK_SOFT)
	line.add_theme_font_size_override(&"font_size", Palette.SIZE_WHISPER)
	add_child(line)
	line.text_submitted.connect(_on_submitted)
	line.focus_exited.connect(_on_focus_exited)
	line.gui_input.connect(_on_gui_input)
	Session.call_line_changed.connect(_on_call_line_changed)
	line.hide()


func _exit_tree() -> void:
	if Session.call_line_changed.is_connected(_on_call_line_changed):
		Session.call_line_changed.disconnect(_on_call_line_changed)


## Shows the line, empty, with keyboard focus.
func open() -> void:
	if line == null:
		return
	line.text = ""
	line.show()
	line.grab_focus()
	line.edit()


func is_open() -> bool:
	return line != null and line.visible


func _on_call_line_changed(open_now: bool) -> void:
	if open_now:
		open()
	elif line.visible:
		line.hide()
		line.release_focus()


func _on_submitted(text: String) -> void:
	Session.submit_call(text)


func _on_focus_exited() -> void:
	if line.visible:
		Session.close_call_line()


func _on_gui_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		Session.close_call_line()
		line.accept_event()
