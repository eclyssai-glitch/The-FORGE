extends Node
## Root of the game. Composes the 3D world and the native UI, fades in, and enables
## automation when user arguments are passed after `--`:
##   --smoke-test            run the demo accelerated, verify it completes, exit 0/1
##   --capture=<dir>         save evidence screenshots of each demo phase to <dir>, then exit
##   --capture-only=<prefix> with --capture: only captures whose name starts with <prefix>
##   --quality=<low|medium|high|ultra>   force a quality level for this run (not persisted)
##   --scenario=<origin_chamber|genesis|living> play that scenario instead of the default one (read
##                           by the Simulation autoload at startup, so the world composes it
##                           directly); unknown ids are warned about and ignored
##   --style-frames=<dir>    save the GENESIS style frames (StyleFrames, HUD hidden, 1920x1080)
##                           to <dir>, then exit
##   --allow-missing-ui      with --smoke-test: a HUD without the "ui_transport"/"demo_badge"
##                           groups is reported as `ui=absent` instead of failing
## Global keyboard shortcuts live in the "Shortcuts" child (src/core/shortcuts.gd).

@onready var world: Node3D = $World
@onready var hud: CanvasLayer = $HUD
@onready var fade: ColorRect = $FadeLayer/Fade

var shortcuts: Shortcuts

var _fade_tween: Tween


func _ready() -> void:
	shortcuts = Shortcuts.new()
	add_child(shortcuts)
	var args := _parse_args(OS.get_cmdline_user_args())
	if args.has("quality"):
		var idx := QualityProfiles.LEVEL_NAMES.find(String(args["quality"]).to_upper())
		if idx >= 0:
			Quality.override_for_session(idx as QualityProfiles.Level)
	if args.has("smoke-test") or args.has("capture") or args.has("style-frames"):
		var automation := preload("res://src/core/automation.gd").new()
		automation.name = "Automation"
		automation.options = args
		add_child(automation)
	_fade_tween = create_tween()
	_fade_tween.tween_property(fade, "color:a", 0.0, 1.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_fade_tween.tween_callback(fade.hide)


## Real seconds between silencing the audio and quitting (a few AudioServer mix steps).
const AUDIO_RELEASE_SECONDS := 0.25

var _quitting := false


## Scripted quit (automation, review tour): stops every audio player of the world, waits
## AUDIO_RELEASE_SECONDS so the AudioServer frees the stopped playbacks, then quits with `code`.
## Without this, a sound still playing at shutdown is reported as "resources still in use at
## exit" (AudioStreamOggVorbis + OggPacketSequence of the ambience). Repeated calls are ignored.
func quit_game(code: int = 0) -> void:
	if _quitting:
		return
	_quitting = true
	if world and world.has_method(&"silence_audio"):
		world.call(&"silence_audio")
	await get_tree().create_timer(AUDIO_RELEASE_SECONDS, true, false, true).timeout
	get_tree().quit(code)


## Ends the entry fade at once (fully transparent and hidden). Used by capture automation
## so the first screenshot never catches the fade half-way (deterministic brightness).
func finish_fade() -> void:
	if _fade_tween and _fade_tween.is_valid():
		_fade_tween.kill()
	fade.color.a = 0.0
	fade.hide()


static func _parse_args(raw: PackedStringArray) -> Dictionary:
	var out := {}
	for a in raw:
		if not a.begins_with("--"):
			continue
		var kv := a.substr(2).split("=", true, 1)
		out[kv[0]] = kv[1] if kv.size() > 1 else true
	return out
