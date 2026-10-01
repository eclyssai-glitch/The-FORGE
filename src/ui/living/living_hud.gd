class_name LivingHud
extends Control
## The LIVING dialect of the HUD (Loop 5, MIKU LIVING CHARACTER prototype; docs/VISUAL_DIRECTION.md
## section 12). MIKU is the whole interface: no panels, no menus, no mode words, no event whispers —
## she shows what she understood by what she does. Built by Hud and shown while the living scenario
## is active; Hud fades it as a whole for H (the DEMO seal lives outside it, always visible).
##
##   top-right     QuietSettings (quality, camera, volumes, the few keys)
##   lower centre  CallLine: the call line (Enter) and the whisper of what MIKU understood
##   bottom        OrbitTransport of the scripted work orders, collapsed while playing; it never
##                 seeks here (ADR-015: the living character is real-time state; Reset recomposes)
## Only the controls themselves catch the mouse; the space between them belongs to the world.

## Scenario id of the living prototype (the registry entry is the game-engineer's).
const SCENARIO := &"living"
const KEYS := "enter  call miku      h  hide\nspace  play · pause      r  reset"

var call_line: UiCallLine
var transport: UiOrbitTransport
var settings: UiQuietSettings


func _init() -> void:
	name = "Living"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var edge := float(Palette.UI_EDGE)

	transport = UiOrbitTransport.new()
	transport.name = "LivingTransport"
	transport.seekable = false
	transport.anchor_left = 0.0
	transport.anchor_top = 1.0
	transport.anchor_right = 1.0
	transport.anchor_bottom = 1.0
	transport.offset_top = -float(Palette.UI_REVEAL_ZONE)
	transport.offset_bottom = 0.0
	# Not in the smoke group until Hud makes it the active transport.
	transport.remove_from_group(UiOrbitTransport.GROUP)
	add_child(transport)

	call_line = UiCallLine.new()
	call_line.anchor_left = 0.0
	call_line.anchor_top = 1.0
	call_line.anchor_right = 1.0
	call_line.anchor_bottom = 1.0
	call_line.offset_bottom = -Palette.UI_CALL_FROM_BOTTOM + UiCallLine.LINE_INSET
	call_line.offset_top = call_line.offset_bottom - UiCallLine.STRIP_HEIGHT
	add_child(call_line)

	settings = UiQuietSettings.new()
	settings.name = "LivingSettings"
	settings.anchor_left = 1.0
	settings.anchor_top = 0.0
	settings.anchor_right = 1.0
	settings.anchor_bottom = 0.0
	settings.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	settings.offset_right = -edge + 6.0
	settings.offset_left = settings.offset_right
	settings.offset_top = 12.0
	settings.set_keys(KEYS)
	add_child(settings)


## Called by Hud when the whole LIVING HUD hides (H or scenario change).
func on_hidden() -> void:
	settings.set_open(false)
	call_line.on_hidden()
