class_name DemoBadge
extends PanelContainer
## Permanent DEMO MODE seal (group "demo_badge"). Always visible, in every mode and scenario and
## even when the rest of the HUD is hidden (H). Information, not energy: never EMBER/PALE/GOLD.
## It never catches the mouse. Two dialects (set_genesis):
##   ORIGIN  — BONE IBM Plex Mono on PANEL with a PANEL_LINE hairline and a small ASH square.
##   GENESIS — no box: a small pearl seal (ring + dot), "DEMO MODE" in spaced mono and a faint
##             "all events simulated"; quiet, elegant, never an alert.

const GROUP := &"demo_badge"
const TEXT := "DEMO MODE"
const SUBTEXT := "SIMULATED EVENTS"
const SUBTEXT_GENESIS := "all events simulated"

var label: Label
var sub: Label
var marker: ColorRect
var seal: Control
var genesis := false


func _init() -> void:
	name = "DemoBadge"
	theme_type_variation = &"BadgePanel"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_to_group(GROUP)
	var h := UiKit.hbox(8)
	add_child(h)
	marker = ColorRect.new()
	marker.color = Palette.ASH
	marker.custom_minimum_size = Vector2(5, 5)
	marker.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(marker)
	seal = Control.new()
	seal.name = "Seal"
	seal.custom_minimum_size = Vector2(12, 12)
	seal.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	seal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	seal.visible = false
	seal.draw.connect(_draw_seal)
	h.add_child(seal)
	label = UiKit.label(TEXT, &"BadgeText")
	label.name = "Text"
	h.add_child(label)
	sub = UiKit.label("·  " + SUBTEXT, &"DataDim")
	sub.name = "Subtext"
	h.add_child(sub)


## Switches the badge to the GENESIS dialect (true) or back to the ORIGIN one.
func set_genesis(on: bool) -> void:
	genesis = on
	theme_type_variation = &"Seal" if on else &"BadgePanel"
	marker.visible = not on
	seal.visible = on
	label.theme_type_variation = &"SealText" if on else &"BadgeText"
	sub.theme_type_variation = &"NoteFaint" if on else &"DataDim"
	sub.text = ("·  " + SUBTEXT_GENESIS) if on else ("·  " + SUBTEXT)


func _draw_seal() -> void:
	UiGlyphs.draw(seal, &"seal", seal.size * 0.5, 4.5, Palette.UI_INK_SOFT)
