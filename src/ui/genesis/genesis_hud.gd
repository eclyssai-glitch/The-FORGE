class_name GenesisHud
extends Control
## The GENESIS dialect of the HUD (UI v2, docs/VISUAL_DIRECTION.md §8): the scene is the hero, the
## UI is pearl ink at the edges and names written in space. Built by Hud and shown while GENESIS is
## the active scenario; Hud fades it as a whole for H (the DEMO badge lives outside it).
##
##   top-left      (DEMO seal, owned by Hud) · MissionVerse under it (OBSERVATORY)
##   top-centre    ModeWords: UNIVERSE · FORGE · OBSERVATORY
##   top-right     QuietSettings (astrolabe sign -> quiet card)
##   in space      SpaceLabels (FORGE/UNIVERSE: hover or selection; OBSERVATORY: every body + kind)
##                 BodyCard beside the selected body (FOCUS, close)
##   lower centre  Whisper (event labels that rise and dissolve)
##   bottom        OrbitTransport (thin arc; revealed near the edge or when not playing)
##   bottom-left   KindLegend (OBSERVATORY)
## Mode-bound parts cross-fade with a sine (Palette.T_BASE in, T_FAST out). Only the controls
## themselves catch the mouse; the space between them belongs to the world.

## Height (px) of the whisper line and its distance (centre) from the bottom edge.
const WHISPER_FROM_BOTTOM := 96.0
## Top of the mission verse (px), under the seal.
const MISSION_TOP := 64.0
## Bottom of the legend (px from the bottom edge), clear of the transport's controls.
const LEGEND_BOTTOM := 64.0

var labels: UiSpaceLabels
var whisper: UiWhisper
var modes: UiModeWords
var settings: UiQuietSettings
var mission: UiMissionVerse
var legend: UiKindLegend
var card: UiBodyCard
var transport: UiOrbitTransport


func _init() -> void:
	name = "Genesis"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var edge := float(Palette.UI_EDGE)

	labels = UiSpaceLabels.new()
	labels.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(labels)

	whisper = UiWhisper.new()
	_anchor(whisper, 0.0, 1.0, 1.0, 1.0)
	whisper.offset_top = -WHISPER_FROM_BOTTOM - UiWhisper.LINE_HEIGHT * 0.5
	whisper.offset_bottom = -WHISPER_FROM_BOTTOM + UiWhisper.LINE_HEIGHT * 0.5
	add_child(whisper)

	mission = UiMissionVerse.new()
	_anchor(mission, 0.0, 0.0, 0.0, 0.0)
	mission.offset_left = edge
	mission.offset_top = MISSION_TOP
	add_child(mission)

	legend = UiKindLegend.new()
	_anchor(legend, 0.0, 1.0, 0.0, 1.0)
	legend.grow_vertical = Control.GROW_DIRECTION_BEGIN
	legend.offset_left = edge
	legend.offset_bottom = -LEGEND_BOTTOM
	legend.offset_top = -LEGEND_BOTTOM
	add_child(legend)

	transport = UiOrbitTransport.new()
	_anchor(transport, 0.0, 1.0, 1.0, 1.0)
	transport.offset_top = -float(Palette.UI_REVEAL_ZONE)
	transport.offset_bottom = 0.0
	add_child(transport)

	card = UiBodyCard.new()
	card.visible = false
	card.modulate.a = 0.0
	card.labels = labels
	labels.card = card
	add_child(card)

	modes = UiModeWords.new()
	_anchor(modes, 0.5, 0.0, 0.5, 0.0)
	modes.grow_horizontal = Control.GROW_DIRECTION_BOTH
	modes.offset_top = 12.0
	add_child(modes)

	settings = UiQuietSettings.new()
	_anchor(settings, 1.0, 0.0, 1.0, 0.0)
	settings.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	settings.offset_right = -edge + 6.0
	settings.offset_left = settings.offset_right
	settings.offset_top = 12.0
	add_child(settings)


func _ready() -> void:
	card.visibility_wanted.connect(_on_card_wanted)
	Session.mode_changed.connect(func(_m: SessionState.Mode) -> void: apply_mode(true))
	apply_mode(false)
	_on_card_wanted(card.wants_visible())


## Parts shown only in `mode` (the rest of the GENESIS HUD is shown in every mode).
func mode_parts(mode: SessionState.Mode) -> Array[Control]:
	if mode == SessionState.Mode.OBSERVATORY:
		return [mission, legend]
	return []


func apply_mode(animated: bool) -> void:
	var show := mode_parts(Session.mode)
	for p: Control in [mission, legend]:
		var on := show.has(p)
		if animated:
			UiKit.fade_sine(p, on, Palette.T_BASE if on else Palette.T_FAST)
		else:
			p.visible = on
			p.modulate.a = 1.0 if on else 0.0


## Called by Hud when the whole GENESIS HUD hides (H or scenario change).
func on_hidden() -> void:
	settings.set_open(false)
	whisper.dissolve()


func _on_card_wanted(on: bool) -> void:
	UiKit.fade_sine(card, on, Palette.T_BASE if on else Palette.T_FAST)


static func _anchor(c: Control, left: float, top: float, right: float, bottom: float) -> void:
	c.anchor_left = left
	c.anchor_top = top
	c.anchor_right = right
	c.anchor_bottom = bottom
