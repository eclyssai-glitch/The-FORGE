extends GutTest
## Interaction flow (Loop 3): global shortcuts drive the autoloads, focus requests, HUD
## visibility, UI focus blocks shortcuts, the main scene composes Shortcuts, and the smoke
## helpers that find the UI by group.

const MainScene := preload("res://scenes/main.tscn")
const AutomationScript := preload("res://src/core/automation.gd")

var shortcuts: Shortcuts
var _prev_mode: SessionState.Mode
var _prev_cinematic: bool


func before_each() -> void:
	_prev_mode = Session.mode
	_prev_cinematic = Session.cinematic
	Simulation.reset()
	shortcuts = Shortcuts.new()
	add_child_autofree(shortcuts)


func after_each() -> void:
	Simulation.reset()
	Session.set_mode(_prev_mode)
	Session.set_cinematic(_prev_cinematic)
	Session.set_hud_visible(true)
	Session.select(&"")
	var focused := get_viewport().gui_get_focus_owner()
	if focused:
		focused.release_focus()


func _key(physical: Key, pressed := true, echo := false) -> InputEventKey:
	var k := InputEventKey.new()
	k.physical_keycode = physical
	k.pressed = pressed
	k.echo = echo
	return k


func _press(physical: Key) -> void:
	shortcuts._unhandled_input(_key(physical))


func test_new_actions_exist_with_their_keys() -> void:
	for a in Shortcuts.ACTIONS:
		assert_true(InputMap.has_action(a), "action %s in project.godot" % a)
	assert_eq(Shortcuts.action_for(_key(KEY_V)), &"toggle_cinematic")
	assert_eq(Shortcuts.action_for(_key(KEY_H)), &"toggle_hud")
	assert_eq(Shortcuts.action_for(_key(KEY_SPACE)), &"demo_toggle")
	assert_eq(Shortcuts.action_for(_key(KEY_R)), &"demo_reset")
	assert_eq(Shortcuts.action_for(_key(KEY_1)), &"mode_universe")
	assert_eq(Shortcuts.action_for(_key(KEY_2)), &"mode_forge")
	assert_eq(Shortcuts.action_for(_key(KEY_3)), &"mode_observatory")
	assert_eq(Shortcuts.action_for(_key(KEY_ESCAPE)), &"deselect")
	assert_eq(Shortcuts.action_for(_key(KEY_F11)), &"toggle_fullscreen")
	assert_eq(Shortcuts.action_for(_key(KEY_W)), &"", "camera keys are not shortcuts")
	assert_eq(Shortcuts.action_for(_key(KEY_V, false)), &"", "release does nothing")
	assert_eq(Shortcuts.action_for(_key(KEY_V, true, true)), &"", "echo does nothing")
	var ctrl_r := _key(KEY_R)
	ctrl_r.ctrl_pressed = true
	assert_eq(Shortcuts.action_for(ctrl_r), &"", "modified keys are not shortcuts")
	assert_eq(Shortcuts.action_for(InputEventMouseButton.new()), &"")
	assert_false(Shortcuts.apply(&"unknown_action"))


func test_shortcuts_drive_simulation() -> void:
	_press(KEY_SPACE)
	assert_eq(Simulation.status, EventTimeline.Status.PLAYING, "Space starts")
	Simulation._process(3.0)
	_press(KEY_SPACE)
	assert_eq(Simulation.status, EventTimeline.Status.PAUSED, "Space pauses")
	assert_gt(Simulation.time, 0.0)
	_press(KEY_R)
	assert_eq(Simulation.status, EventTimeline.Status.IDLE, "R resets")
	assert_eq(Simulation.time, 0.0)


func test_shortcuts_drive_session() -> void:
	_press(KEY_1)
	assert_eq(Session.mode, SessionState.Mode.UNIVERSE)
	_press(KEY_3)
	assert_eq(Session.mode, SessionState.Mode.OBSERVATORY)
	_press(KEY_2)
	assert_eq(Session.mode, SessionState.Mode.FORGE)
	Session.select(&"seed_vesper")
	_press(KEY_ESCAPE)
	assert_eq(Session.selected, &"", "Esc deselects")
	var before := Session.cinematic
	watch_signals(Session)
	_press(KEY_V)
	assert_eq(Session.cinematic, not before, "V toggles the cinematic camera")
	_press(KEY_V)
	assert_eq(Session.cinematic, before)
	assert_signal_emit_count(Session, "cinematic_changed", 2)


func test_toggle_hud_emits_visibility() -> void:
	assert_true(Session.hud_visible)
	watch_signals(Session)
	_press(KEY_H)
	assert_false(Session.hud_visible)
	assert_signal_emitted_with_parameters(Session, "hud_visibility_changed", [false])
	_press(KEY_H)
	assert_true(Session.hud_visible)
	assert_signal_emitted_with_parameters(Session, "hud_visibility_changed", [true])
	Session.set_hud_visible(true)
	assert_signal_emit_count(Session, "hud_visibility_changed", 2, "no signal without a change")


func test_focus_always_emits() -> void:
	watch_signals(Session)
	Session.focus(&"seed_aurel")
	Session.focus(&"seed_aurel")
	Session.focus(&"origin_core")
	assert_signal_emit_count(Session, "focus_requested", 3, "repeated requests re-emit")
	assert_signal_emitted_with_parameters(Session, "focus_requested", [&"origin_core"])
	assert_eq(Session.selected, &"", "focus does not select")


func test_text_and_value_controls_block_shortcuts() -> void:
	assert_false(Shortcuts.blocks_shortcuts(null))
	var edit := LineEdit.new()
	var slider := HSlider.new()
	var button := Button.new()
	for c: Control in [edit, slider, button]:
		c.focus_mode = Control.FOCUS_ALL
		add_child_autofree(c)
	assert_true(Shortcuts.blocks_shortcuts(edit))
	assert_true(Shortcuts.blocks_shortcuts(slider))
	assert_false(Shortcuts.blocks_shortcuts(button))
	# Live: with the slider focused the key is ignored and left unhandled.
	slider.grab_focus()
	await wait_process_frames(1)
	assert_eq(get_viewport().gui_get_focus_owner(), slider)
	_press(KEY_1)
	assert_ne(Session.mode, SessionState.Mode.UNIVERSE, "a focused slider keeps its keys")
	edit.grab_focus()
	await wait_process_frames(1)
	_press(KEY_H)
	assert_true(Session.hud_visible, "a focused LineEdit keeps its keys")
	button.grab_focus()
	await wait_process_frames(1)
	_press(KEY_1)
	assert_eq(Session.mode, SessionState.Mode.UNIVERSE, "a focused button does not block shortcuts")


func test_main_scene_composes_shortcuts_headless() -> void:
	var main := MainScene.instantiate()
	add_child_autofree(main)
	await wait_process_frames(2)
	var sc := main.get_node_or_null("Shortcuts")
	assert_not_null(sc, "main adds the Shortcuts node")
	assert_true(sc is Shortcuts)
	assert_eq(sc.get_index(), main.get_child_count() - 1, "Shortcuts last: first to see unhandled keys")
	assert_not_null(main.get_node_or_null("HUD"))
	# The UI must survive every state change in headless.
	for m: SessionState.Mode in [SessionState.Mode.UNIVERSE, SessionState.Mode.OBSERVATORY, SessionState.Mode.FORGE]:
		Session.set_mode(m)
		Session.select(&"layer_2")
		Session.focus(&"layer_2")
		Session.toggle_hud()
		await wait_process_frames(2)
	Session.set_hud_visible(true)
	Simulation.seek(30.0)
	await wait_process_frames(2)
	assert_true(is_instance_valid(main))


func test_capture_list_has_loop3_shots() -> void:
	var names: Array[String] = []
	for c: Array in AutomationScript.CAPTURES:
		names.append(String(c[0]))
		assert_between(float(c[1]), 0.0, Simulation.duration(), "%s time inside the demo" % c[0])
		if c.size() > 3:
			assert_false(EntityCatalog.info(c[3]).is_empty(), "%s selects a catalog entity" % c[0])
	for n in ["10_forge_inspector", "11_observatory_mid", "12_universe_seed_focus"]:
		assert_has(names, n)
	var c12: Array = AutomationScript.CAPTURES[names.find("12_universe_seed_focus")]
	assert_eq(c12[2], SessionState.Mode.UNIVERSE)
	assert_eq(c12[3], &"seed_aurel")
	assert_eq(c12[4], &"seed_aurel")


func test_smoke_ui_helpers() -> void:
	var transport := HBoxContainer.new()
	for n in ["Start", "Pause", "Reset"]:
		var b := Button.new()
		b.name = n
		transport.add_child(b)
	add_child_autofree(transport)
	for n in ["Start", "Pause", "Reset"]:
		var b := AutomationScript.find_ui_button([transport], n)
		assert_not_null(b, n)
		if b:
			assert_eq(b.name, StringName(n))
	assert_null(AutomationScript.find_ui_button([transport], "Stop"))

	var panel := PanelContainer.new()
	var label := Label.new()
	label.text = "DEMO MODE"
	panel.add_child(label)
	add_child_autofree(panel)
	assert_true(AutomationScript.visible_demo_badge([panel]), "badge text in a descendant")
	assert_true(AutomationScript.visible_demo_badge([label]))
	panel.hide()
	assert_false(AutomationScript.visible_demo_badge([panel]), "hidden badge does not count")
	panel.show()
	label.text = "SIMULATED"
	assert_false(AutomationScript.visible_demo_badge([panel]), "text must contain DEMO")
	assert_false(AutomationScript.visible_demo_badge([]))


func _automation(opts: Dictionary) -> Node:
	var auto: Node = AutomationScript.new()
	auto.options = opts
	add_child_autofree(auto)
	return auto


func test_smoke_ui_absent_fails_unless_allowed() -> void:
	var lines: PackedStringArray = []
	assert_false(await _automation({})._smoke_ui(lines), "absent UI fails by default")
	assert_has(lines, "ui=absent")
	lines.clear()
	assert_true(await _automation({"allow-missing-ui": true})._smoke_ui(lines), "tolerated with the flag")
	assert_has(lines, "ui=absent")


func test_smoke_ui_drives_a_conforming_ui() -> void:
	var ui := Control.new()
	var transport := HBoxContainer.new()
	transport.add_to_group(AutomationScript.UI_TRANSPORT_GROUP)
	ui.add_child(transport)
	for n: String in ["Start", "Pause", "Reset"]:
		var b := Button.new()
		b.name = n
		transport.add_child(b)
	(transport.get_node("Start") as Button).pressed.connect(Simulation.start)
	(transport.get_node("Pause") as Button).pressed.connect(Simulation.pause)
	(transport.get_node("Reset") as Button).pressed.connect(Simulation.reset)
	var badge := Label.new()
	badge.text = "DEMO MODE"
	badge.add_to_group(AutomationScript.UI_BADGE_GROUP)
	ui.add_child(badge)
	add_child_autofree(ui)
	var lines: PackedStringArray = []
	assert_true(await _automation({})._smoke_ui(lines), "\n".join(lines))
	assert_has(lines, "ui=present")
	assert_has(lines, "ui_transport start=true pause=true reset=true")
	# A hidden badge fails, even with the flag (the flag only tolerates a UI that does not exist).
	badge.hide()
	lines.clear()
	assert_false(await _automation({"allow-missing-ui": true})._smoke_ui(lines), "hidden badge fails")
	Simulation.set_speed(1.0)
