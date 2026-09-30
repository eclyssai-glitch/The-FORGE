extends Node
## Test automation driven from the command line (see main.gd). Runs inside the real
## game — same scenes, same renderer — so results reflect what a player sees.

const WorldScript := preload("res://src/world/world.gd")

const SMOKE_SPEED := 8.0
## Seconds allowed for get_tree().quit() to end the main loop before the process kills itself.
const EXIT_WATCHDOG_SECONDS := 3.0
const REPORT_NAME := "smoke_report.txt"

## Capture points: [file name, simulation time, mode, (selected id), (focused id), (options)].
## Without a selected id the selection is cleared; a non-empty focused id is requested after the
## camera snapped to the mode shot, and gets FOCUS_SETTLE seconds to frame it. The optional
## trailing Dictionary holds per-shot options: {"hud": false} hides the HUD for that shot
## (Session.set_hud_visible; the DEMO badge must stay). Every other shot shows the HUD.
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
	["13_hud_hidden", 49.0, SessionState.Mode.FORGE, {"hud": false}],
]
## GENESIS capture points (same entry format; key phases x modes, HUD visible except the last).
## Event times in GenesisScript: awaken 3, hands 8, dust 13, seeded 18, layers 22/27/32,
## moons 37/40, ring 43, belt 46, links 50, stable 53, completed 56.
const CAPTURES_GENESIS: Array = [
	["g01_still", 1.5, SessionState.Mode.FORGE],
	["g02_awaken", 5.5, SessionState.Mode.FORGE],
	["g03_hands", 10.5, SessionState.Mode.FORGE],
	["g04_dust", 15.5, SessionState.Mode.FORGE],
	["g05_seeded", 19.5, SessionState.Mode.FORGE],
	["g06_mantle", 24.5, SessionState.Mode.FORGE],
	["g07_crust", 29.5, SessionState.Mode.FORGE],
	["g08_sky", 34.5, SessionState.Mode.FORGE],
	["g09_moons", 41.5, SessionState.Mode.FORGE],
	["g10_ring", 44.5, SessionState.Mode.FORGE],
	["g11_belt_universe", 48.0, SessionState.Mode.UNIVERSE],
	["g12_links_observatory", 51.5, SessionState.Mode.OBSERVATORY],
	["g13_stable_forge", 55.5, SessionState.Mode.FORGE],
	["g14_stable_universe", 55.5, SessionState.Mode.UNIVERSE],
	["g15_stable_observatory", 55.5, SessionState.Mode.OBSERVATORY],
	["g16_planet_inspector", 55.5, SessionState.Mode.FORGE, &"planet_forming"],
	["g17_planet_focus", 55.5, SessionState.Mode.UNIVERSE, &"planet_forming", &"planet_forming"],
	["g18_hud_hidden", 55.5, SessionState.Mode.FORGE, {"hud": false}],
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
	if options.has("style-frames"):
		_run_style_frames.call_deferred(String(options["style-frames"]))
	elif options.has("capture"):
		_run_capture.call_deferred(String(options["capture"]))
	elif options.has("smoke-test"):
		_run_smoke.call_deferred()


## Capture list of a scenario.
static func captures_for(scenario: StringName) -> Array:
	return CAPTURES_GENESIS if scenario == Scenario.GENESIS else CAPTURES


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
	var expected := Scenario.build_events(Simulation.scenario).size()
	lines.append("scenario=%s" % Simulation.scenario)
	lines.append("renderer=%s adapter=%s" % [RenderingServer.get_current_rendering_method(), RenderingServer.get_video_adapter_name()])
	lines.append("quality=%s" % Quality.level_name())
	# Every expected world module must have loaded: a missing entity/fx/camera script would
	# otherwise only print a warning and the demo would still "complete".
	var expected_modules := WorldScript.expected_module_names(Simulation.scenario)
	var missing: Array[String] = expected_modules.duplicate()
	var world := _world()
	if world:
		missing = world.missing_modules()
		if world.scenario != Simulation.scenario:
			missing = expected_modules.duplicate()
			lines.append("FAIL world composed for %s, not %s" % [world.scenario, Simulation.scenario])
	lines.append("modules=%d/%d" % [expected_modules.size() - missing.size(), expected_modules.size()])
	if not missing.is_empty():
		lines.append("FAIL modules missing: %s" % ", ".join(PackedStringArray(missing)))
	var audio_ok := _smoke_audio(world, lines)
	lines.append("events_received=%d expected=%d" % [received.size(), expected])
	lines.append(phase_line(Simulation.state))
	lines.append("frames=%d wall_seconds=%.2f avg_fps=%.1f" % [frames, elapsed, frames / maxf(elapsed, 0.001)])
	var mission := Mission.evaluate(Simulation.emitted_events(), Simulation.scenario)
	lines.append("mission_objectives=%d/%d" % [Mission.completed_count(mission), mission.size()])
	ok = ok and missing.is_empty() and audio_ok and received.size() == expected and Simulation.state.is_complete() \
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
	var reset_ok := Simulation.time == 0.0 and Simulation.state.phase_index() == 0 \
		and Simulation.status == EventTimeline.Status.IDLE
	ok = ok and pause_holds and reset_ok
	lines.append("pause_holds=%s reset_ok=%s" % [pause_holds, reset_ok])
	ok = await _smoke_ui(lines) and ok
	lines.append("RESULT=%s" % ("PASS" if ok else "FAIL"))
	_write_report(lines)
	_quit(0 if ok else 1)


## Audio report: the AudioDirector (group "audio_director") and, in GENESIS, the anchors every
## scene must register (World.GENESIS_AUDIO_ANCHORS). Line `audio=present|absent anchors=...`.
## A missing director is already a missing module; missing GENESIS anchors fail here.
static func _smoke_audio(world: WorldScript, lines: PackedStringArray) -> bool:
	if world == null or world.audio_director == null:
		lines.append("audio=absent")
		return true
	var kinds := world.audio_anchor_kinds()
	lines.append("audio=present anchors=%s" % ",".join(PackedStringArray(kinds)))
	if Simulation.scenario != Scenario.GENESIS:
		return true
	var missing: PackedStringArray = []
	for k in WorldScript.GENESIS_AUDIO_ANCHORS:
		if not kinds.has(k):
			missing.append(String(k))
	if not missing.is_empty():
		lines.append("FAIL audio anchors missing: %s" % ", ".join(missing))
	return missing.is_empty()


## Report line with the final phase and the scenario's formation counters.
static func phase_line(state: ScenarioState) -> String:
	if state is GenesisState:
		var g := state as GenesisState
		return "phase=%s layers=%d/%d moons=%d/%d" % [g.phase_name(), g.layers_formed(), GenesisScript.LAYER_COUNT,
			g.moons_formed(), GenesisScript.MOON_COUNT]
	if state is WorldState:
		var w := state as WorldState
		return "phase=%s layers=%d/%d" % [w.phase_name(), w.layers_built(), OriginChamberScript.LAYER_COUNT]
	return "phase=%s" % state.phase_name()


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
	for c in captures_for(Simulation.scenario):
		if only != "" and not String(c[0]).begins_with(only):
			continue
		Session.set_mode(c[2])
		Simulation.seek(c[1])
		Session.select(capture_selected(c))
		Session.set_hud_visible(bool(capture_options(c).get("hud", true)))
		_snap_cameras()
		var focus_id := capture_focus(c)
		if focus_id != &"":
			Session.focus(focus_id)
			await _settle(FOCUS_SETTLE)
		else:
			await _settle(CAPTURE_SETTLE)
		var img := get_viewport().get_texture().get_image()
		var path := abs_dir.path_join("%s.png" % c[0])
		img.save_png(path)
		print("[capture] %s (t=%.1f, %s, selected=%s, hud=%s, %dx%d, quality=%s)" % [path, c[1], Session.mode_name(),
			Session.selected, Session.hud_visible, img.get_width(), img.get_height(), Quality.level_name()])
	Session.set_hud_visible(true)
	_quit(0)


## Style frames (GENESIS): for each StyleFrames pose (the CameraDirector's `style_frame_poses()`
## or StyleFrames.DEFAULT_POSES) seek, set the mode, hide the HUD (the DEMO badge stays), put an
## automation-owned Camera3D (current) on the pose and save `<name>.png`; the window is resized to
## StyleFrames.SIZE first. Writes StyleFrames.MANIFEST (one file name per line) at the end.
func _run_style_frames(dir: String) -> void:
	var abs_dir := dir if dir.is_absolute_path() else ProjectSettings.globalize_path("res://").path_join(dir)
	DirAccess.make_dir_recursive_absolute(abs_dir)
	if Simulation.scenario != Scenario.GENESIS:
		Simulation.set_scenario(Scenario.GENESIS)
	var main := get_parent()
	if main and main.has_method(&"finish_fade"):
		main.call(&"finish_fade")
	var window := get_window()
	if window.mode != Window.MODE_WINDOWED:
		window.mode = Window.MODE_WINDOWED
	window.size = StyleFrames.SIZE
	await _settle(1.5)
	var director: Node = null
	var directors := get_tree().get_nodes_in_group(&"camera_director")
	if not directors.is_empty():
		director = directors[0]
	var poses := StyleFrames.poses_from(director)
	var cam := Camera3D.new()
	cam.name = "StyleFrameCamera"
	cam.near = 0.05
	cam.far = 800.0
	var world := _world()
	var parent: Node = world if world else get_tree().current_scene
	parent.add_child(cam)
	Session.select(&"")
	Session.set_hud_visible(false)
	var names: PackedStringArray = []
	for pose in poses:
		Session.set_mode(int(pose["mode"]) as SessionState.Mode)
		Simulation.seek(float(pose["time"]))
		_snap_cameras()
		StyleFrames.apply_pose(cam, pose)
		cam.make_current()
		await _settle(CAPTURE_SETTLE)
		var img := get_viewport().get_texture().get_image()
		var file := "%s.png" % pose["name"]
		img.save_png(abs_dir.path_join(file))
		names.append(file)
		print("[style-frame] %s (t=%.1f, %s, %dx%d, quality=%s)" % [abs_dir.path_join(file), float(pose["time"]),
			Session.mode_name(), img.get_width(), img.get_height(), Quality.level_name()])
		if Vector2i(img.get_width(), img.get_height()) != StyleFrames.SIZE:
			push_warning("style frame %s is %dx%d, not %dx%d" % [file, img.get_width(), img.get_height(),
				StyleFrames.SIZE.x, StyleFrames.SIZE.y])
	var f := FileAccess.open(abs_dir.path_join(StyleFrames.MANIFEST), FileAccess.WRITE)
	if f:
		f.store_string("\n".join(names) + "\n")
		f.close()
	Session.set_hud_visible(true)
	_quit(0)


## Selected id of a capture entry (&"" = clear the selection).
static func capture_selected(c: Array) -> StringName:
	return StringName(c[3]) if c.size() > 3 and not (c[3] is Dictionary) else &""


## Focused id of a capture entry (&"" = none).
static func capture_focus(c: Array) -> StringName:
	return StringName(c[4]) if c.size() > 4 and not (c[4] is Dictionary) else &""


## Per-shot options of a capture entry: its trailing Dictionary, or {}.
static func capture_options(c: Array) -> Dictionary:
	return c.back() if c.size() > 3 and c.back() is Dictionary else {}


## Ends an automation run through Main.quit_game (audio silenced first, see there). quit()
## normally ends the main loop at the end of this frame; if
## the loop is still running EXIT_WATCHDOG_SECONDS later (seen under Xvfb + lavapipe), the
## process kills itself so scripts waiting on it never hang. Only reached in automation runs
## (--capture / --smoke-test). Hangs after the main loop (driver teardown) are covered by
## tools/_proc.sh, which kills the whole process session.
func _quit(code: int) -> void:
	get_tree().create_timer(EXIT_WATCHDOG_SECONDS, true, false, true).timeout.connect(
		func() -> void:
			push_warning("automation: quit did not complete in %.0fs; killing process." % EXIT_WATCHDOG_SECONDS)
			OS.kill(OS.get_process_id()))
	var main := get_parent()
	if main and main.has_method(&"quit_game"):
		main.call(&"quit_game", code)
	else:
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
