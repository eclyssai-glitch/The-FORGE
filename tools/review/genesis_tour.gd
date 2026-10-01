extends Node
## Recording tour of the GENESIS scene (Loop 4 r1): the real game, cinematic camera on, played
## once from T+0 to the end (GenesisScript.DURATION, 56 s) plus a breath of TAIL seconds.
## Tools only (tools/ is excluded from the export); it never changes the game. Recorded by
## tools/record_genesis.sh with the Movie Maker (--write-movie, --fixed-fps 30: game time, the
## Simulation advances exactly 1/30 s per frame, audio mixed into the AVI).
##
## Needs `--scenario=genesis` among the user args (read by the Simulation autoload before this
## scene exists). Instances res://scenes/main.tscn, forces a quality level for this run
## (Quality.override_for_session; HIGH by default: AUTO would measure the fixed 30 fps and step
## down), sets FORGE + Session.cinematic (the cinematic cues are the FORGE story shots), shows or
## hides the HUD (the DEMO badge always stays), waits LEAD_IN seconds on the still T+0 frame
## (the entry fade), starts the demo with Simulation.start() and quits through Main.quit_game.
## User args (after `--`): --genesis-until=<s> (tour seconds; stop early, previews),
## --genesis-from=<s> (seek the demo to T+s before starting it: inspect one stretch),
## --hud=on|off (default on), --quality=<low|medium|high|ultra> (default high),
## --size=WxH (window size; the Movie Maker records the window).
## Prints `[genesis] start ...`, one `[genesis] event ...` line per simulation event and
## `[genesis] done ...` just before quitting.

const MainScene := preload("res://scenes/main.tscn")

## Seconds on the still first frame before Simulation.start() (the game's entry fade).
const LEAD_IN := 0.5
## Seconds after the last event (the demo's end) before quitting: the stable world breathes.
const TAIL := 4.0

var main: Node
## Tour time (sum of delta = game time under the Movie Maker).
var time := 0.0
## Tour seconds at which the recording stops (LEAD_IN + DURATION + TAIL unless --genesis-until).
var until := LEAD_IN + GenesisScript.DURATION + TAIL
var hud_on := true
var level: QualityProfiles.Level = QualityProfiles.Level.HIGH
## Simulation time the demo starts from (seek), 0 = the whole story.
var from := 0.0

var _started := false
var _finished := false
var _frames := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var args := parse_args(OS.get_cmdline_user_args())
	if args.has("genesis-from"):
		from = clampf(String(args["genesis-from"]).to_float(), 0.0, GenesisScript.DURATION)
		until = LEAD_IN + GenesisScript.DURATION - from + TAIL
	if args.has("genesis-until"):
		until = String(args["genesis-until"]).to_float()
	hud_on = hud_from_arg(String(args.get("hud", "on")))
	level = level_from_arg(String(args.get("quality", "high")))
	var size := size_from_arg(String(args.get("size", "")))
	if size != Vector2i.ZERO:
		get_window().size = size
	Quality.override_for_session(level)
	if Simulation.scenario != Scenario.GENESIS:
		push_warning("genesis_tour: pass --scenario=genesis (switching now)")
		Simulation.set_scenario(Scenario.GENESIS)
	main = MainScene.instantiate()
	add_child(main)
	Session.set_mode(SessionState.Mode.FORGE)
	Session.set_cinematic(true)
	Session.set_hud_visible(hud_on)
	Simulation.event_emitted.connect(_on_event)
	print("[genesis] start quality=%s hud=%s from=T+%05.2f until=%.2f movie=%s size=%s" % [Quality.level_name(),
		"on" if hud_on else "off", from, until, Engine.get_write_movie_path(), get_viewport().get_visible_rect().size])


func _process(delta: float) -> void:
	if _finished:
		return
	time += delta
	_frames += 1
	if not _started and time >= LEAD_IN:
		_started = true
		if from > 0.0:
			Simulation.seek(from)
		Simulation.start()
	if time >= until:
		_finish()


func _on_event(e: SimEvent) -> void:
	print("[genesis] event t=%6.2f sim=T+%05.2f %s" % [time, Simulation.time, e.type])


func _finish() -> void:
	_finished = true
	print("[genesis] done t=%.2f frames=%d sim=T+%05.2f status=%s mode=%s cinematic=%s size=%s" % [time,
		_frames, Simulation.time, EventTimeline.Status.keys()[Simulation.status], Session.mode_name(),
		Session.cinematic, get_viewport().get_visible_rect().size])
	if main and main.has_method(&"quit_game"):
		main.call(&"quit_game", 0)
	else:
		get_tree().quit()


static func hud_from_arg(v: String) -> bool:
	return v.to_lower() not in ["off", "0", "false", "no"]


static func level_from_arg(v: String) -> QualityProfiles.Level:
	var idx := QualityProfiles.LEVEL_NAMES.find(v.to_upper())
	return (idx if idx >= 0 else QualityProfiles.Level.HIGH) as QualityProfiles.Level


## "WxH" -> Vector2i (ZERO when empty or malformed).
static func size_from_arg(v: String) -> Vector2i:
	var parts := v.split("x")
	if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
		return Vector2i.ZERO
	var s := Vector2i(parts[0].to_int(), parts[1].to_int())
	return s if s.x > 0 and s.y > 0 else Vector2i.ZERO


static func parse_args(raw: PackedStringArray) -> Dictionary:
	var out := {}
	for a in raw:
		if not a.begins_with("--"):
			continue
		var kv := a.substr(2).split("=", true, 1)
		out[kv[0]] = kv[1] if kv.size() > 1 else true
	return out
