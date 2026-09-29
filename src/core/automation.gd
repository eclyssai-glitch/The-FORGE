extends Node
## Test automation driven from the command line (see main.gd). Runs inside the real
## game — same scenes, same renderer — so results reflect what a player sees.

const WorldScript := preload("res://src/world/world.gd")

const SMOKE_SPEED := 8.0
## Seconds allowed for get_tree().quit() to end the main loop before the process kills itself.
const EXIT_WATCHDOG_SECONDS := 3.0
const REPORT_NAME := "smoke_report.txt"

## Capture points: [file name, simulation time, mode, (selected id), (focused id)].
## Without a selected id the selection is cleared; a focused id is requested after the camera
## snapped to the mode shot, and gets FOCUS_SETTLE seconds to frame it.
const CAPTURES: Array = [
	["01_dormant_core", 0.5, SessionState.Mode.FORGE],
	["02_core_active", 5.0, SessionState.Mode.FORGE],
	["03_fragments", 8.5, SessionState.Mode.FORGE],
	["04_building_layers", 19.5, SessionState.Mode.FORGE],
	["05_materials_lighting", 30.5, SessionState.Mode.FORGE],
	["06_verification", 37.0, SessionState.Mode.FORGE],
	["07_final_form", 49.0, SessionState.Mode.FORGE],
	["08_universe", 49.0, SessionState.Mode.UNIVERSE],
	["09_observatory", 49.0, SessionState.Mode.OBSERVATORY],
	["10_forge_inspector", 30.5, SessionState.Mode.FORGE, &"layer_2"],
	["11_observatory_mid", 37.0, SessionState.Mode.OBSERVATORY],
	["12_universe_seed_focus", 49.0, SessionState.Mode.UNIVERSE, &"seed_aurel", &"seed_aurel"],
]
## Real seconds a capture waits after seek/mode change (and after a focus request).
const CAPTURE_SETTLE := 2.4
const FOCUS_SETTLE := 3.6

## UI contract (docs/ARCHITECTURE.md): transport buttons and the DEMO badge, found by group.
const UI_TRANSPORT_GROUP := &"ui_transport"
const UI_BADGE_GROUP := &"demo_badge"
const UI_BUTTONS: Array[String] = ["Start", "Pause", "Reset"]
## Real seconds the badge may take to become visible after a mode change (UI transitions).
const UI_BADGE_WAIT := 1.5

var options: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if options.has("capture"):
		_run_capture.call_deferred(String(options["capture"]))
	elif options.has("smoke-test"):
		_run_smoke.call_deferred()


func _run_smoke() -> void:
	var lines: PackedStringArray = []
	var ok := true
	var received: Array[StringName] = []
	Simulation.event_emitted.connect(func(e: SimEvent) -> void: received.append(e.id))
	Session.set_mode(Session.Mode.FORGE)
	Simulation.set_speed(SMOKE_SPEED)
	Simulation.start()
	var started := Time.get_ticks_msec()
	var frames := 0
	while Simulation.status != EventTimeline.Status.COMPLETE:
		await get_tree().process_frame
		frames += 1
		if Time.get_ticks_msec() - started > 120_000:
			lines.append("FAIL timeout after %d frames at t=%.1f" % [frames, Simulation.time])
			ok = false
			break
	var elapsed := (Time.get_ticks_msec() - started) / 1000.0
	var expected := OriginChamberScript.build().size()
	lines.append("renderer=%s adapter=%s" % [RenderingServer.get_current_rendering_method(), RenderingServer.get_video_adapter_name()])
	lines.append("quality=%s" % Quality.level_name())
	# Every expected world module must have loaded: a missing entity/fx/camera script would
	# otherwise only print a warning and the demo would still "complete".
	var expected_modules := WorldScript.expected_module_names()
	var missing: Array[String] = expected_modules.duplicate()
	var world := _world()
	if world:
		missing = world.missing_modules()
	lines.append("modules=%d/%d" % [expected_modules.size() - missing.size(), expected_modules.size()])
	if not missing.is_empty():
		lines.append("FAIL modules missing: %s" % ", ".join(PackedStringArray(missing)))
	lines.append("events_received=%d expected=%d" % [received.size(), expected])
	lines.append("phase=%s layers=%d/%d" % [Simulation.world.phase_name(), Simulation.world.layers_built(), OriginChamberScript.LAYER_COUNT])
	lines.append("frames=%d wall_seconds=%.2f avg_fps=%.1f" % [frames, elapsed, frames / maxf(elapsed, 0.001)])
	var mission := Mission.evaluate(Simulation.emitted_events())
	lines.append("mission_objectives=%d/%d" % [Mission.completed_count(mission), mission.size()])
	ok = ok and missing.is_empty() and received.size() == expected and Simulation.world.phase == WorldState.Phase.COMPLETE \
		and Mission.completed_count(mission) == mission.size()
	# Exercise pause / reset on the live game.
	Simulation.seek(20.0)
	Simulation.start()
	Simulation.pause()
	var paused_at := Simulation.time
	for i in 10:
		await get_tree().process_frame
	var pause_holds := is_equal_approx(paused_at, Simulation.time) and Simulation.status == EventTimeline.Status.PAUSED
	Simulation.reset()
	var reset_ok := Simulation.time == 0.0 and Simulation.world.phase == WorldState.Phase.DORMANT \
		and Simulation.status == EventTimeline.Status.IDLE
	ok = ok and pause_holds and reset_ok
	lines.append("pause_holds=%s reset_ok=%s" % [pause_holds, reset_ok])
	ok = await _smoke_ui(lines) and ok
	lines.append("RESULT=%s" % ("PASS" if ok else "FAIL"))
	_write_report(lines)
	_quit(0 if ok else 1)


## Exercises the native UI through its groups: the transport buttons (Start -> Pause -> Reset,
## via pressed.emit()) must drive Simulation.status, and a visible "demo_badge" node with "DEMO"
## in its text must exist in every mode. Report line `ui=present|absent`. A UI with neither group
## is `ui=absent`: a failure unless the run was started with --allow-missing-ui.
func _smoke_ui(lines: PackedStringArray) -> bool:
	var transports := get_tree().get_nodes_in_group(UI_TRANSPORT_GROUP)
	var badges := get_tree().get_nodes_in_group(UI_BADGE_GROUP)
	if transports.is_empty() and badges.is_empty():
		var allowed := options.has("allow-missing-ui")
		lines.append("ui=absent")
		if not allowed:
			lines.append("FAIL ui absent: no \"%s\" / \"%s\" nodes (pass --allow-missing-ui to tolerate)" % [UI_TRANSPORT_GROUP, UI_BADGE_GROUP])
		return allowed
	lines.append("ui=present")
	var ok := true
	# Transport buttons.
	var buttons := {}
	for n in UI_BUTTONS:
		var b := find_ui_button(transports, n)
		if b == null:
			lines.append("FAIL ui_transport: no button named %s" % n)
			ok = false
		else:
			buttons[n] = b
	if buttons.size() == UI_BUTTONS.size():
		Simulation.reset()
		Simulation.set_speed(1.0)
		(buttons["Start"] as BaseButton).pressed.emit()
		for i in 5:
			await get_tree().process_frame
		var start_ok := Simulation.status == EventTimeline.Status.PLAYING and Simulation.time > 0.0
		(buttons["Pause"] as BaseButton).pressed.emit()
		await get_tree().process_frame
		var paused_at := Simulation.time
		for i in 5:
			await get_tree().process_frame
		var pause_ok := Simulation.status == EventTimeline.Status.PAUSED and is_equal_approx(paused_at, Simulation.time)
		(buttons["Reset"] as BaseButton).pressed.emit()
		await get_tree().process_frame
		var reset_ok := Simulation.status == EventTimeline.Status.IDLE and Simulation.time == 0.0
		lines.append("ui_transport start=%s pause=%s reset=%s" % [start_ok, pause_ok, reset_ok])
		ok = ok and start_ok and pause_ok and reset_ok
	# DEMO badge, visible in every mode.
	var badge_modes: PackedStringArray = []
	for m: SessionState.Mode in [SessionState.Mode.UNIVERSE, SessionState.Mode.FORGE, SessionState.Mode.OBSERVATORY]:
		Session.set_mode(m)
		var until := Time.get_ticks_msec() + int(UI_BADGE_WAIT * 1000.0)
		var seen := visible_demo_badge(get_tree().get_nodes_in_group(UI_BADGE_GROUP))
		while not seen and Time.get_ticks_msec() < until:
			await get_tree().process_frame
			seen = visible_demo_badge(get_tree().get_nodes_in_group(UI_BADGE_GROUP))
		if seen:
			badge_modes.append(Session.mode_name())
		else:
			lines.append("FAIL demo_badge: no visible node with \"DEMO\" in %s" % Session.mode_name())
			ok = false
	lines.append("ui_demo_badge=%d/3 (%s)" % [badge_modes.size(), ",".join(badge_modes)])
	Session.set_mode(SessionState.Mode.FORGE)
	return ok


## Button named `button_name` among the nodes of the transport group (or their descendants).
static func find_ui_button(roots: Array, button_name: String) -> BaseButton:
	for r: Node in roots:
		if r is BaseButton and r.name == button_name:
			return r
		var found := r.find_child(button_name, true, false)
		if found is BaseButton:
			return found
	return null


## True when one of `nodes` is visible in the tree and it (or a descendant) shows text with "DEMO".
static func visible_demo_badge(nodes: Array) -> bool:
	for n: Node in nodes:
		var ci := n as CanvasItem
		if ci == null or not ci.is_visible_in_tree():
			continue
		if _text_has_demo(n):
			return true
		for c in n.find_children("*", "", true, false):
			if c is CanvasItem and (c as CanvasItem).is_visible_in_tree() and _text_has_demo(c):
				return true
	return false


static func _text_has_demo(n: Node) -> bool:
	var t: Variant = n.get(&"text")
	return t is String and (t as String).to_upper().contains("DEMO")


func _run_capture(dir: String) -> void:
	var abs_dir := dir if dir.is_absolute_path() else ProjectSettings.globalize_path("res://").path_join(dir)
	DirAccess.make_dir_recursive_absolute(abs_dir)
	# Captures must not depend on how far the entry fade got: end it before anything is shot.
	var main := get_parent()
	if main and main.has_method(&"finish_fade"):
		main.call(&"finish_fade")
	await _settle(1.5)
	var only := String(options.get("capture-only", ""))
	for c in CAPTURES:
		if only != "" and not String(c[0]).begins_with(only):
			continue
		Session.set_mode(c[2])
		Simulation.seek(c[1])
		Session.select(c[3] if c.size() > 3 else &"")
		_snap_cameras()
		if c.size() > 4:
			Session.focus(c[4])
			await _settle(FOCUS_SETTLE)
		else:
			await _settle(CAPTURE_SETTLE)
		var img := get_viewport().get_texture().get_image()
		var path := abs_dir.path_join("%s.png" % c[0])
		img.save_png(path)
		print("[capture] %s (t=%.1f, %s, selected=%s)" % [path, c[1], Session.mode_name(), Session.selected])
	_quit(0)


## Ends an automation run. quit() normally ends the main loop at the end of this frame; if
## the loop is still running EXIT_WATCHDOG_SECONDS later (seen under Xvfb + lavapipe), the
## process kills itself so scripts waiting on it never hang. Only reached in automation runs
## (--capture / --smoke-test). Hangs after the main loop (driver teardown) are covered by
## tools/_proc.sh, which kills the whole process session.
func _quit(code: int) -> void:
	get_tree().create_timer(EXIT_WATCHDOG_SECONDS, true, false, true).timeout.connect(
		func() -> void:
			push_warning("automation: quit did not complete in %.0fs; killing process." % EXIT_WATCHDOG_SECONDS)
			OS.kill(OS.get_process_id()))
	get_tree().quit(code)


## The composed world (scenes/world.tscn instanced as "World" under the main scene), or null.
func _world() -> WorldScript:
	var scene := get_tree().current_scene
	if scene == null:
		return null
	return scene.get_node_or_null(^"World") as WorldScript


## Jumps every camera rig straight to the current mode's shot (no tween) before settling.
func _snap_cameras() -> void:
	for node in get_tree().get_nodes_in_group(&"camera_director"):
		if node.has_method(&"snap_to_mode_shot"):
			node.call(&"snap_to_mode_shot")


## Lets camera tweens and time-based visuals settle before a capture.
func _settle(seconds: float) -> void:
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw


func _write_report(lines: PackedStringArray) -> void:
	var text := "\n".join(lines)
	print("[smoke]\n" + text)
	var f := FileAccess.open("user://" + REPORT_NAME, FileAccess.WRITE)
	if f:
		f.store_string(text + "\n")
