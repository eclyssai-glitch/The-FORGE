class_name Shortcuts
extends Node
## Global keyboard shortcuts (added by main.gd as "Shortcuts"). Maps the input actions of
## project.godot to the autoloads — the only channel between input, UI and the 3D world:
##   demo_toggle (Space) -> Simulation.toggle()      demo_reset (R) -> Simulation.reset()
##   mode_universe/forge/observatory (1/2/3) -> Session.set_mode(...)
##   deselect (Esc) -> Session.select(&"")           toggle_fullscreen (F11) -> window mode
##   toggle_cinematic (V) -> Session.set_cinematic(not Session.cinematic)
##   toggle_hud (H) -> Session.toggle_hud() (emits Session.hud_visibility_changed)
## Uses `_unhandled_input`: whatever the UI consumes never gets here. While a text or value
## control of the UI (LineEdit, TextEdit, Range: Slider/SpinBox) has keyboard focus, shortcuts
## are ignored and the event is left untouched (not marked as handled). A shortcut that fires
## marks the event as handled. Key echoes (held keys) never repeat a shortcut.
## Camera keys (WASD, C, mouse) belong to the CameraDirector and are not handled here.

## Actions handled here, in match order.
const ACTIONS: Array[StringName] = [
	&"demo_toggle", &"demo_reset",
	&"mode_universe", &"mode_forge", &"mode_observatory",
	&"deselect", &"toggle_fullscreen", &"toggle_cinematic", &"toggle_hud",
]


func _init() -> void:
	name = "Shortcuts"


func _ready() -> void:
	# Shortcuts keep working while the tree is paused (they are how the player resumes).
	process_mode = Node.PROCESS_MODE_ALWAYS


func _unhandled_input(event: InputEvent) -> void:
	var action := action_for(event)
	if action == &"":
		return
	if blocks_shortcuts(get_viewport().gui_get_focus_owner()):
		return
	if apply(action):
		get_viewport().set_input_as_handled()


## First action of ACTIONS that `event` presses (no echo, exact modifiers); &"" if none.
static func action_for(event: InputEvent) -> StringName:
	if event == null or event is InputEventMouse:
		return &""
	for a in ACTIONS:
		if InputMap.has_action(a) and event.is_action_pressed(a, false, true):
			return a
	return &""


## True when the focused UI control edits text or values: shortcuts must not steal its keys.
static func blocks_shortcuts(focus_owner: Control) -> bool:
	if focus_owner == null or not focus_owner.is_visible_in_tree():
		return false
	return focus_owner is LineEdit or focus_owner is TextEdit or focus_owner is Range


## Runs `action` against the autoloads. Returns false for an unknown action.
static func apply(action: StringName) -> bool:
	match action:
		&"demo_toggle":
			Simulation.toggle()
		&"demo_reset":
			Simulation.reset()
		&"mode_universe":
			Session.set_mode(SessionState.Mode.UNIVERSE)
		&"mode_forge":
			Session.set_mode(SessionState.Mode.FORGE)
		&"mode_observatory":
			Session.set_mode(SessionState.Mode.OBSERVATORY)
		&"deselect":
			Session.select(&"")
		&"toggle_fullscreen":
			toggle_fullscreen()
		&"toggle_cinematic":
			Session.set_cinematic(not Session.cinematic)
		&"toggle_hud":
			Session.toggle_hud()
		_:
			return false
	return true


static func toggle_fullscreen() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var full := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED if full else DisplayServer.WINDOW_MODE_FULLSCREEN)
