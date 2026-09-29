extends Node
## Test automation driven from the command line (see main.gd). Runs inside the real
## game — same scenes, same renderer — so results reflect what a player sees.

const SMOKE_SPEED := 8.0
const REPORT_NAME := "smoke_report.txt"

## Capture points: [file name, simulation time, mode, settle seconds].
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
]

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
	lines.append("events_received=%d expected=%d" % [received.size(), expected])
	lines.append("phase=%s layers=%d/%d" % [Simulation.world.phase_name(), Simulation.world.layers_built(), OriginChamberScript.LAYER_COUNT])
	lines.append("frames=%d wall_seconds=%.2f avg_fps=%.1f" % [frames, elapsed, frames / maxf(elapsed, 0.001)])
	var mission := Mission.evaluate(Simulation.emitted_events())
	lines.append("mission_objectives=%d/%d" % [Mission.completed_count(mission), mission.size()])
	ok = ok and received.size() == expected and Simulation.world.phase == WorldState.Phase.COMPLETE \
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
	lines.append("RESULT=%s" % ("PASS" if ok else "FAIL"))
	_write_report(lines)
	get_tree().quit(0 if ok else 1)


func _run_capture(dir: String) -> void:
	var abs_dir := dir if dir.is_absolute_path() else ProjectSettings.globalize_path("res://").path_join(dir)
	DirAccess.make_dir_recursive_absolute(abs_dir)
	await _settle(1.5)
	var only := String(options.get("capture-only", ""))
	for c in CAPTURES:
		if only != "" and not String(c[0]).begins_with(only):
			continue
		Session.set_mode(c[2])
		Simulation.seek(c[1])
		await _settle(2.4)
		var img := get_viewport().get_texture().get_image()
		var path := abs_dir.path_join("%s.png" % c[0])
		img.save_png(path)
		print("[capture] %s (t=%.1f, %s)" % [path, c[1], Session.mode_name()])
	get_tree().quit(0)


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
