class_name SessionState
extends Node
## Autoload "Session": player-facing state shared by the 3D world and the native UI —
## active environment (mode), selection, camera preference, focus requests and HUD visibility.
## UI and 3D never reference each other: they only read/write this state and listen to it.

signal mode_changed(mode: Mode)
signal selection_changed(id: StringName)
signal hover_changed(id: StringName)
signal cinematic_changed(enabled: bool)
## Someone (UI "Focus" button, site list...) asked the camera to frame entity `id`.
## Emitted on every call, even when repeated with the same id (re-frame).
signal focus_requested(id: StringName)
## The HUD must show/hide itself (`toggle_hud` action, H). The 3D world ignores it.
signal hud_visibility_changed(visible: bool)

enum Mode { UNIVERSE, FORGE, OBSERVATORY }

const MODE_NAMES: Array[String] = ["UNIVERSE", "FORGE", "OBSERVATORY"]
## Every focusable entity root joins the group ENTITY_GROUP_PREFIX + id (see entity_group()).
const ENTITY_GROUP_PREFIX := "entity_"

var mode: Mode = Mode.FORGE
var selected: StringName = &""
var hovered: StringName = &""
## When true, the camera follows the event-driven shot list.
var cinematic: bool = true
## When false the HUD hides itself (the DEMO badge policy is the UI's; see docs/ARCHITECTURE.md).
var hud_visible: bool = true


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


## Asks the camera to frame entity `id`. Always emits focus_requested (a repeated request
## re-frames after the user moved the camera). Does not change the selection.
func focus(id: StringName) -> void:
	focus_requested.emit(id)


func set_hud_visible(v: bool) -> void:
	if v == hud_visible:
		return
	hud_visible = v
	hud_visibility_changed.emit(hud_visible)


func toggle_hud() -> void:
	set_hud_visible(not hud_visible)


func mode_name() -> String:
	return MODE_NAMES[mode]


## Group of the visual root of entity `id` (e.g. &"entity_seed_aurel"); the camera finds focus
## targets with get_tree().get_nodes_in_group(Session.entity_group(id)).
static func entity_group(id: StringName) -> StringName:
	return StringName(ENTITY_GROUP_PREFIX + String(id))
