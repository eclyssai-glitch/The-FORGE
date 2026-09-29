extends Node
## Root of the game. Composes the 3D world and the native UI, fades in, and enables
## automation when user arguments are passed after `--`:
##   --smoke-test            run the demo accelerated, verify it completes, exit 0/1
##   --capture=<dir>         save evidence screenshots of each demo phase to <dir>, then exit
##   --capture-only=<prefix> with --capture: only captures whose name starts with <prefix>
##   --quality=<low|medium|high|ultra>   force a quality level for this run (not persisted)

@onready var world: Node3D = $World
@onready var hud: CanvasLayer = $HUD
@onready var fade: ColorRect = $FadeLayer/Fade


func _ready() -> void:
	var args := _parse_args(OS.get_cmdline_user_args())
	if args.has("quality"):
		var idx := QualityProfiles.LEVEL_NAMES.find(String(args["quality"]).to_upper())
		if idx >= 0:
			Quality.override_for_session(idx as QualityProfiles.Level)
	if args.has("smoke-test") or args.has("capture"):
		var automation := preload("res://src/core/automation.gd").new()
		automation.name = "Automation"
		automation.options = args
		add_child(automation)
	var tw := create_tween()
	tw.tween_property(fade, "color:a", 0.0, 1.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_callback(fade.hide)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_fullscreen"):
		var full := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED if full else DisplayServer.WINDOW_MODE_FULLSCREEN)


static func _parse_args(raw: PackedStringArray) -> Dictionary:
	var out := {}
	for a in raw:
		if not a.begins_with("--"):
			continue
		var kv := a.substr(2).split("=", true, 1)
		out[kv[0]] = kv[1] if kv.size() > 1 else true
	return out
