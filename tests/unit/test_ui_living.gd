extends GutTest
## LIVING HUD (Loop 5): the call line contract with the interaction system (group
## "living_call_line", submitted / opened / closed, show_feedback kinds), its keyboard behaviour,
## the barest dialect (no seek, settings, no panels) and the palette discipline of its theme.
## The scenario registry entry `living` is the game-engineer's: the dialect switch is tested through
## Hud.dialect_for and the LivingHud on its own.

const HudScene := preload("res://scenes/hud.tscn")

var host: SubViewport


func before_each() -> void:
	Session.set_hud_visible(true)
	host = SubViewport.new()
	host.size = Vector2i(1600, 900)
	add_child_autofree(host)


func _line() -> UiCallLine:
	var hud := LivingHud.new()
	host.add_child(hud)
	return hud.call_line


func _key(code: Key) -> InputEventKey:
	var k := InputEventKey.new()
	k.keycode = code
	k.pressed = true
	return k


func test_call_line_is_found_by_group_and_rests_closed() -> void:
	var line := _line()
	await wait_process_frames(2)
	var found := get_tree().get_nodes_in_group(UiCallLine.GROUP)
	assert_eq(found.size(), 1, "exactly one call line")
	assert_same(found[0], line)
	assert_false(line.is_open())
	assert_false(line.field.visible, "closed: no field, nothing takes the keyboard")
	assert_eq(line.mouse_filter, Control.MOUSE_FILTER_IGNORE, "the strip lets picking through")
	assert_true(line.has_signal(&"submitted"))
	assert_true(line.has_method(&"show_feedback"))


func test_open_type_submit() -> void:
	var line := _line()
	await wait_process_frames(2)
	watch_signals(line)
	line.open()
	assert_true(line.is_open())
	assert_signal_emitted(line, "opened")
	assert_true(line.field.visible)
	line.field.text = "  Miku, fique mais alta  "
	line.field.text_submitted.emit(line.field.text)
	assert_signal_emitted_with_parameters(line, "submitted", ["Miku, fique mais alta"])
	assert_signal_emitted(line, "closed")
	assert_false(line.is_open())
	assert_eq(line.sent.text, "Miku, fique mais alta", "the sent words rise from the line")
	await wait_seconds(Palette.T_CALL_CLOSE + 0.2)
	assert_false(line.field.visible, "the field is gone once the line retracted")


func test_empty_submit_only_closes() -> void:
	var line := _line()
	await wait_process_frames(1)
	watch_signals(line)
	line.open()
	line.submit("   ")
	assert_signal_not_emitted(line, "submitted")
	assert_false(line.is_open())


func test_programmatic_submit_and_length_cap() -> void:
	var line := _line()
	await wait_process_frames(1)
	watch_signals(line)
	line.submit("miku, " + "a".repeat(400))
	assert_signal_emit_count(line, "submitted", 1)
	var sent: String = get_signal_parameters(line, "submitted")[0]
	assert_eq(sent.length(), UiCallLine.MAX_CHARS)


func test_enter_opens_and_escape_cancels() -> void:
	var line := _line()
	await wait_process_frames(2)
	watch_signals(line)
	line._unhandled_key_input(_key(KEY_ENTER))
	assert_true(line.is_open(), "Enter opens the line")
	line._on_field_input(_key(KEY_ESCAPE))
	assert_false(line.is_open(), "Esc lets it go")
	assert_signal_not_emitted(line, "submitted")
	line.visible = false
	line._unhandled_key_input(_key(KEY_KP_ENTER))
	assert_false(line.is_open(), "hidden (H): Enter does nothing")


func test_typing_blocks_shortcuts() -> void:
	var line := _line()
	await wait_process_frames(2)
	line.open()
	await wait_process_frames(1)
	assert_true(Shortcuts.blocks_shortcuts(line.field), "keys go to the words, not to Space/H/R")
	line.close()


func test_feedback_kinds_and_ink() -> void:
	var line := _line()
	await wait_process_frames(1)
	line.show_feedback(&"recognized", "altura")
	await wait_seconds(Palette.T_CALL_ECHO_IN + 0.1)
	assert_eq(line.feedback_text(), "→ altura")
	assert_eq(line.feedback_kind(), &"recognized")
	assert_eq(line.echo.get_theme_color(&"font_color"), Palette.UI_INK_SOFT)
	line.show_feedback(&"recognized", "→ altura")
	await wait_seconds(Palette.T_WHISPER_HANDOFF + Palette.T_CALL_ECHO_IN + 0.1)
	assert_eq(line.feedback_text(), "→ altura", "never a double arrow")
	line.show_feedback(&"refused", "não posso agora")
	assert_eq(line.feedback_kind(), &"refused")
	assert_eq(line.echo.get_theme_color(&"font_color"), Palette.UI_INK_FAINT)
	line.show_feedback(&"whatever", "hm")
	assert_eq(line.feedback_kind(), &"heard", "unknown kinds are 'heard'")
	line.show_feedback(&"applied", "  ")
	assert_eq(line.feedback_kind(), &"heard", "empty feedback is ignored")
	assert_eq(UiCallLine.feedback_ink(&"applied"), Palette.UI_INK)
	await wait_seconds(Palette.T_WHISPER_HANDOFF + Palette.T_CALL_ECHO_IN + Palette.T_CALL_ECHO_HOLD + Palette.T_CALL_ECHO_OUT + 0.3)
	assert_eq(line.feedback_text(), "", "the whisper dissolves")


func test_line_geometry_and_layout() -> void:
	var line := _line()
	await wait_process_frames(2)
	assert_almost_eq(UiCallLine.line_width(0.0), Palette.UI_CALL_REST, 0.01)
	assert_almost_eq(UiCallLine.line_width(1.0), Palette.UI_CALL_WIDTH, 0.01)
	var vp := host.size
	var r := line.get_global_rect()
	assert_almost_eq(r.end.y, vp.y - Palette.UI_CALL_FROM_BOTTOM + UiCallLine.LINE_INSET, 1.0)
	var line_screen_y := r.position.y + line.line_y()
	assert_almost_eq(line_screen_y, vp.y - Palette.UI_CALL_FROM_BOTTOM, 1.0, "line above the transport zone")
	assert_lt(line_screen_y, vp.y - Palette.UI_REVEAL_ZONE * 0.5, "clear of the revealed transport controls")
	assert_almost_eq(line.field.get_global_rect().get_center().x, vp.x * 0.5, 1.0, "centred")
	assert_lt(line.echo.get_global_rect().end.y, line.field.get_global_rect().position.y + 1.0, "the whisper sits above the words")
	assert_eq(line.field.focus_mode, Control.FOCUS_CLICK)
	assert_eq(line.hint.focus_mode, Control.FOCUS_NONE)


func test_living_hud_is_bare_and_never_seeks() -> void:
	var hud := LivingHud.new()
	host.add_child(hud)
	await wait_process_frames(2)
	assert_false(hud.transport.seekable, "ADR-015: no seek in the living scenario")
	assert_eq(hud.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	assert_eq(hud.transport.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	assert_true(hud.settings.keys_label.text.contains("enter"), "the keys name the call")
	for c in hud.find_children("*", "PanelContainer", true, false):
		assert_ne((c as PanelContainer).theme_type_variation, &"HudPanel", "no panels")
	var t0 := Simulation.time
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_LEFT
	mb.pressed = true
	mb.position = Vector2(hud.transport.track.size.x * 0.9, 4.0)
	hud.transport._on_track_input(mb)
	await wait_process_frames(2)
	assert_almost_eq(Simulation.time, t0, 0.2, "a press on the arc does not seek")


func test_hud_dialects() -> void:
	assert_eq(Hud.dialect_for(&"living"), &"living")
	assert_eq(Hud.dialect_for(Scenario.GENESIS), &"genesis")
	assert_eq(Hud.dialect_for(Scenario.ORIGIN_CHAMBER), &"origin")
	assert_eq(LivingHud.SCENARIO, &"living")
	var hud := HudScene.instantiate() as Hud
	host.add_child(hud)
	await wait_process_frames(2)
	assert_not_null(hud.living)
	assert_eq(hud.chromes().size(), 3)
	assert_false(hud.living.visible, "LIVING hidden outside its scenario")
	assert_false(hud.living.transport.is_in_group(UiOrbitTransport.GROUP), "only the active transport is in the smoke group")
	assert_eq(get_tree().get_nodes_in_group(Transport.GROUP).size(), 1)
	# The call line exists once per HUD, only reacts while LIVING is shown.
	assert_false(hud.living.call_line.is_visible_in_tree())


func test_living_theme_is_pearl_ink() -> void:
	var t := UiTheme.get_theme()
	assert_eq(t.get_type_variation_base(&"CallField"), &"LineEdit")
	for v in ["CallEcho", "CallSent"]:
		assert_eq(t.get_type_variation_base(v), &"Label", v)
		assert_between(t.get_font_size("font_size", v), 11, 16, "%s legible" % v)
	for n: StringName in [&"font_color", &"font_placeholder_color", &"caret_color", &"selection_color"]:
		var c := t.get_color(n, &"CallField")
		assert_almost_eq(c.r, Palette.PEARL.r, 0.003, "%s pearl" % n)
		assert_lt(c.a, 1.0, "%s is ink, never opaque" % n)
	assert_eq(t.get_font_size("font_size", &"CallField"), Palette.SIZE_CALL)


func test_nothing_suggests_a_real_connection() -> void:
	var line := _line()
	await wait_process_frames(1)
	var forbidden := ["CONNECT", "SERVER", "CLOUD", "LOGIN", "ACCOUNT", "SYNC", "NETWORK", "UPLOAD", "API ", "CHAT", "SEND"]
	var texts := [line.field.placeholder_text, LivingHud.KEYS]
	for s: String in texts:
		for w: String in forbidden:
			assert_false(s.to_upper().contains(w), "\"%s\" contains %s" % [s, w])
