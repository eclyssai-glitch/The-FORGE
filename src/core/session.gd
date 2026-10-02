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
## A pick body of entity `id` was clicked (Picker). Emitted on EVERY click — also when `id` is
## already selected — so a second click on MIKU calls her again. Followed by select(id).
signal entity_clicked(id: StringName)
## LIVING call line (Loop 5): the thin line where the user speaks to MIKU opens/closes (Enter /
## Esc / submit). The UI (or the placeholder of src/world/living_call_line.gd) shows it.
signal call_line_changed(open: bool)
## Text sent from the call line (the line closes first). The interaction system routes it.
signal call_submitted(text: String)
## An interaction was recognised and its plan STARTS (InteractionRouter.request_started), emitted
## before any of its actions can finish — the UI shows "→ <subject>" (recognized) at once.
## report = {"id", "request_id", "kind", "route", "status": &"started", "target", "path", "plan",
## "text", "source", "expected_status", "estimate", "deadline", "restart"}. Never contains anything sent
## anywhere.
signal interaction_started(report: Dictionary)
## Outcome of an interaction (InteractionRouter report: id, request_id, kind, route, status, plan,
## path, values, reason, steps, failures...), emitted when its plan ENDS, for diegetic feedback in
## the UI (the result). Never contains anything sent anywhere.
signal interaction_reported(report: Dictionary)

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
## True while the LIVING call line is open.
var call_line_open: bool = false
## Longest text the call line accepts (longer submissions are cut).
const CALL_MAX_CHARS := 200


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


## A click on entity `id` (Picker): entity_clicked(id) always, then select(id).
func click(id: StringName) -> void:
	entity_clicked.emit(id)
	select(id)


func open_call_line() -> void:
	if call_line_open:
		return
	call_line_open = true
	call_line_changed.emit(true)


func close_call_line() -> void:
	if not call_line_open:
		return
	call_line_open = false
	call_line_changed.emit(false)


## Closes the call line and sends `text` (trimmed, at most CALL_MAX_CHARS). Empty text only closes.
## Returns true when something was sent.
func submit_call(text: String) -> bool:
	close_call_line()
	var t := text.strip_edges().left(CALL_MAX_CHARS)
	if t == "":
		return false
	call_submitted.emit(t)
	return true


func report_interaction_started(report: Dictionary) -> void:
	interaction_started.emit(report)


func report_interaction(report: Dictionary) -> void:
	interaction_reported.emit(report)


func mode_name() -> String:
	return MODE_NAMES[mode]


## Group of the visual root of entity `id` (e.g. &"entity_seed_aurel"); the camera finds focus
## targets with get_tree().get_nodes_in_group(Session.entity_group(id)).
static func entity_group(id: StringName) -> StringName:
	return StringName(ENTITY_GROUP_PREFIX + String(id))
