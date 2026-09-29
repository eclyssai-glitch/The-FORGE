class_name DemoBadge
extends PanelContainer
## Permanent DEMO MODE seal (group "demo_badge"): BONE IBM Plex Mono on PANEL with a PANEL_LINE
## hairline and a small ASH square marker. Always visible, in every mode and even when the rest
## of the HUD is hidden (H). Information, not energy: never EMBER, never PALE.
## It never catches the mouse.

const GROUP := &"demo_badge"
const TEXT := "DEMO MODE"
const SUBTEXT := "SIMULATED EVENTS"

var label: Label


func _init() -> void:
	name = "DemoBadge"
	theme_type_variation = &"BadgePanel"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_to_group(GROUP)
	var h := UiKit.hbox(8)
	add_child(h)
	var marker := ColorRect.new()
	marker.color = Palette.ASH
	marker.custom_minimum_size = Vector2(5, 5)
	marker.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(marker)
	label = UiKit.label(TEXT, &"BadgeText")
	label.name = "Text"
	h.add_child(label)
	var sub := UiKit.label("·  " + SUBTEXT, &"DataDim")
	sub.name = "Subtext"
	h.add_child(sub)
