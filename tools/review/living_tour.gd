extends Node
## Recording tour of the MIKU LIVING CHARACTER prototype (Loop 5): the real game with
## `--scenario=living`, cinematic camera on, played once from T+0 to the end
## (LivingScript.DURATION, 140 s) plus TAIL seconds, with the user tests 5–7 played as REAL
## input at LivingScript.USER_CUES (LivingCuePlayer: a mouse click on MIKU, a click on a world,
## Enter + "Miku, aumente sua altura" typed on the call line + Enter, and a SEMANTIC request with
## no provider). Tools only (tools/ is excluded from the export); it never changes the game.
## Recorded by tools/record_living.sh with the Movie Maker (--write-movie, --fixed-fps 30: game
## time; MIKU's real-time motion runs on MotionClock = accumulated game time; audio in the AVI).
##
## MIKU's configuration: the player's user file is snapshotted, reset to the versioned defaults for
## the take (the recording always starts from the same MIKU) and restored before quitting.
## No seek (ADR-015): the take always starts at T+0.
## User args (after `--`): --living-until=<s> (tour seconds; stop early, previews),
## --hud=on|off (default on), --quality=<low|medium|high|ultra> (default high), --size=WxH.
## Prints `[living] start ...`, `[living] event ...` per simulation event, `[living] cue ...`
## per injected interaction, the interaction reports (`[living] <KIND> ...`, LivingInteraction)
## and `[living] done ...` just before quitting.

const MainScene := preload("res://scenes/main.tscn")
const GenesisTour := preload("res://tools/review/genesis_tour.gd")

## Seconds on the still first frame before Simulation.start() (the game's entry fade).
const LEAD_IN := 0.5
## Seconds after the end of the script before quitting.
const TAIL := 4.0

var main: Node
var cues: LivingCuePlayer
var time := 0.0
var until := LEAD_IN + LivingScript.DURATION + TAIL
var hud_on := true
var level: QualityProfiles.Level = QualityProfiles.Level.HIGH

var _store: MikuConfig
var _snapshot: Variant = null
var _reports := 0
var _started := false
var _finished := false
var _frames := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var args := GenesisTour.parse_args(OS.get_cmdline_user_args())
	if args.has("living-until"):
		until = String(args["living-until"]).to_float()
	hud_on = GenesisTour.hud_from_arg(String(args.get("hud", "on")))
	level = GenesisTour.level_from_arg(String(args.get("quality", "high")))
	var size := GenesisTour.size_from_arg(String(args.get("size", "")))
	if size != Vector2i.ZERO:
		get_window().size = size
	Quality.override_for_session(level)
	# The take starts from the versioned MIKU; the player's state comes back at the end.
	_store = MikuConfig.new()
	_store.reload()
	_snapshot = _store.snapshot()
	_store.reset()
	if Simulation.scenario != Scenario.LIVING:
		push_warning("living_tour: pass --scenario=living (switching now)")
		Simulation.set_scenario(Scenario.LIVING)
	main = MainScene.instantiate()
	add_child(main)
	Session.set_mode(SessionState.Mode.FORGE)
	Session.set_cinematic(true)
	Session.set_hud_visible(hud_on)
	Simulation.event_emitted.connect(_on_event)
	Session.interaction_reported.connect(func(_r: Dictionary) -> void: _reports += 1)
	cues = LivingCuePlayer.new()
	add_child(cues)
	print("[living] start quality=%s hud=%s until=%.2f movie=%s size=%s" % [Quality.level_name(),
		"on" if hud_on else "off", until, Engine.get_write_movie_path(), get_viewport().get_visible_rect().size])


func _process(delta: float) -> void:
	if _finished:
		return
	time += delta
	_frames += 1
	if not _started and time >= LEAD_IN:
		_started = true
		Simulation.start()
	if time >= until:
		_finish()


func _on_event(e: SimEvent) -> void:
	print("[living] event t=%6.2f sim=T+%06.2f %s %s" % [time, Simulation.time, e.type, e.label])


func _finish() -> void:
	_finished = true
	var real := 0
	for r: Array in cues.results:
		if r[1]:
			real += 1
	var restored := _store.restore_snapshot(_snapshot)
	print("[living] done t=%.2f frames=%d sim=T+%06.2f status=%s cues=%d/%d real=%d reports=%d config_restored=%s size=%s" % [
		time, _frames, Simulation.time, EventTimeline.Status.keys()[Simulation.status], cues.results.size(),
		cues.cues.size(), real, _reports, restored, get_viewport().get_visible_rect().size])
	if main and main.has_method(&"quit_game"):
		main.call(&"quit_game", 0)
	else:
		get_tree().quit()
