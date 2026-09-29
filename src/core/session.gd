class_name SessionState
extends Node
## Autoload "Session": player-facing state shared by the 3D world and the native UI —
## active environment (mode), selection and camera preference.

signal mode_changed(mode: Mode)
signal selection_changed(id: StringName)
signal hover_changed(id: StringName)
signal cinematic_changed(enabled: bool)

enum Mode { UNIVERSE, FORGE, OBSERVATORY }

const MODE_NAMES: Array[String] = ["UNIVERSE", "FORGE", "OBSERVATORY"]

var mode: Mode = Mode.FORGE
var selected: StringName = &""
var hovered: StringName = &""
## When true, the camera follows the event-driven shot list.
var cinematic: bool = true


func set_mode(m: Mode) -> void:
	if m == mode:
		return
	mode = m
	mode_changed.emit(mode)


func select(id: StringName) -> void:
	if id == selected:
		return
	selected = id
	selection_changed.emit(selected)


func hover(id: StringName) -> void:
	if id == hovered:
		return
	hovered = id
	hover_changed.emit(hovered)


func set_cinematic(enabled: bool) -> void:
	if enabled == cinematic:
		return
	cinematic = enabled
	cinematic_changed.emit(cinematic)


func mode_name() -> String:
	return MODE_NAMES[mode]
