class_name LivingInteraction
extends Node
## Interaction system of the LIVING scenario (Loop 5, game-engineer / INTERACTION_SYSTEM).
## A world module (last of World.LIVING_MODULES): it owns MIKU's configuration store and the
## InteractionRouter, binds the router to the animator's `Miku` node and turns the user's
## diegetic input into requests:
##   - click on MIKU            (Session.entity_clicked(&"miku"))   -> router.call_attention()
##   - click on a world         (Session.entity_clicked(world id))  -> router.indicate_world(id)
##   - text from the call line  (Session.call_submitted(text))      -> router.submit_text(text)
## The call line itself is UI: Enter (Shortcuts, `call_line`) opens it through
## Session.open_call_line(); the art-director's UI shows it when a node of group CALL_LINE_UI_GROUP
## exists, otherwise this module shows a minimal placeholder (LivingCallLine).
## Every finished request is reported with Session.report_interaction(report) (UI feedback) and
## re-emitted here. No menus, no settings panel: configuration changes only happen through MIKU.
##
## Binding to MIKU: the sibling node named MIKU_NODE (or the first node of group MIKU_GROUP) that
## has `perform()` is driven through MikuNodeExecutor; without it the router uses the null
## executor (actions finish at once) — the pipeline still validates and applies configuration.
## At bind time the executor receives `apply_config(values)`; after each real change
## `config_changed(path, old, new)` (Miku.apply_config / Miku.on_config_changed when present).
##
## Worlds: LivingScript.WORLDS; "left/right/center" for the parser are computed from where the
## current camera shows each world's visual root (group Session.entity_group(id)); the catalog
## sides are used when fewer than two roots are on screen.

signal plan_started(plan: Array, report: Dictionary)
signal action_dispatched(index: int, action: StringName, args: Dictionary)
signal config_changed(path: String, old_value: Variant, new_value: Variant)
signal request_finished(report: Dictionary)

const GROUP := &"living_interaction"
## Group of the art-director's call line UI. When a node of it exists, no placeholder is shown.
const CALL_LINE_UI_GROUP := &"living_call_line_ui"
const MIKU_NODE := "Miku"
const MIKU_GROUP := &"living_miku"
## Dev inspector contract (docs/ARCHITECTURE.md, "Contrato inspect_state()"): members expose a
## read-only `inspect_state() -> Dictionary`. Nothing calls it in the game; the development-only
## inspector (tools/inspector, never exported) does when it is loaded.
const DEV_INSPECT_GROUP := &"dev_inspect"

var config: MikuConfig
var router: InteractionRouter
## The placeholder call line (null while the UI provides one or before the first opening).
var call_line: LivingCallLine


func _init() -> void:
	name = "LivingInteraction"


func _ready() -> void:
	add_to_group(GROUP)
	add_to_group(DEV_INSPECT_GROUP)
	config = MikuConfig.new()
	config.reload()
	router = InteractionRouter.new(config)
	router.worlds = LivingScript.world_directory()
	router.plan_started.connect(func(plan: Array, rep: Dictionary) -> void: plan_started.emit(plan, rep))
	router.action_dispatched.connect(func(i: int, a: StringName, args: Dictionary) -> void:
		action_dispatched.emit(i, a, args))
	router.mutation_applied.connect(func(p: String, o: Variant, n: Variant) -> void: config_changed.emit(p, o, n))
	router.request_finished.connect(_on_request_finished)
	Session.entity_clicked.connect(_on_entity_clicked)
	Session.call_submitted.connect(_on_call_submitted)
	Session.call_line_changed.connect(_on_call_line_changed)
	bind_miku()


func _exit_tree() -> void:
	if router:
		router.cancel()
	for pair: Array in [[Session.entity_clicked, _on_entity_clicked], [Session.call_submitted, _on_call_submitted],
			[Session.call_line_changed, _on_call_line_changed]]:
		var sig: Signal = pair[0]
		if sig.is_connected(pair[1]):
			sig.disconnect(pair[1])
	Session.close_call_line()


func _process(delta: float) -> void:
	router.tick(delta)


## (Re)binds the router to the MIKU node; returns true when a real body was found.
func bind_miku() -> bool:
	var miku := find_miku()
	var executor: ActionExecutor
	if miku != null and miku.has_method(&"perform"):
		executor = MikuNodeExecutor.new(miku)
	else:
		executor = ActionExecutor.new()
	router.set_executor(executor)
	executor.apply_config(config.values())
	return executor.is_bound()


## The animator's MIKU node (sibling MIKU_NODE, else group MIKU_GROUP), or null.
func find_miku() -> Node:
	var parent := get_parent()
	if parent:
		var n := parent.get_node_or_null(NodePath(MIKU_NODE))
		if n != null:
			return n
	if is_inside_tree():
		for n in get_tree().get_nodes_in_group(MIKU_GROUP):
			return n
	return null


func is_bound() -> bool:
	return router != null and router.executor.is_bound()


## Dev inspector section "interaction": the vocabulary action in flight (InteractionRouter.snapshot)
## plus the binding, the call line and the configuration values. Read-only, no side effects.
func inspect_state() -> Dictionary:
	var s := router.snapshot() if router else {}
	s["bound_to"] = String(find_miku().name) if find_miku() else ""
	s["call_line_open"] = Session.call_line_open
	s["config"] = config.values() if config else {}
	return s


func inspect_section() -> String:
	return "interaction"


# ------------------------------------------------------------------ requests


## Call-line text -> router (sides of the worlds from the current camera).
func submit_text(text: String) -> Intent:
	router.worlds = world_directory()
	return router.submit_text(text)


func call_attention(source: StringName = &"click") -> Intent:
	return router.call_attention(source)


func indicate_world(id: StringName, source: StringName = &"click") -> Intent:
	return router.indicate_world(id, source)


## LivingScript.world_directory() with "side" taken from the screen: the leftmost world on screen
## is left, the rightmost right, the others center.
func world_directory() -> Array:
	var dir := LivingScript.world_directory()
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam == null:
		return dir
	var seen: Array = []  # [x, index]
	for i in dir.size():
		var root := _visual_root(StringName(dir[i]["id"]))
		if root == null or cam.is_position_behind(root.global_position):
			continue
		seen.append([cam.unproject_position(root.global_position).x, i])
	if seen.size() < 2:
		return dir
	seen.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	for w: Dictionary in dir:
		w["side"] = &"center"
	dir[seen[0][1]]["side"] = &"left"
	dir[seen[-1][1]]["side"] = &"right"
	return dir


func _visual_root(id: StringName) -> Node3D:
	for n in get_tree().get_nodes_in_group(SessionState.entity_group(id)):
		if n is Node3D and (n as Node3D).is_visible_in_tree():
			return n
	return null


func _on_entity_clicked(id: StringName) -> void:
	if id == &"miku":
		call_attention()
	elif LivingScript.world_ids().has(id):
		indicate_world(id)


func _on_call_submitted(text: String) -> void:
	submit_text(text)


func _on_request_finished(report: Dictionary) -> void:
	print("[living] %s %s/%s %s plan=%s%s" % [report.get("kind", ""), report.get("route", ""),
		report.get("status", ""), ("\"%s\"" % report["text"]) if String(report.get("text", "")) != "" else report.get("target", ""),
		",".join(PackedStringArray(report.get("plan", []))),
		(" %s %s->%s" % [report["path"], str(report["old_value"]), str(report["new_value"])]) if String(report.get("path", "")) != "" else ""])
	Session.report_interaction(report)
	request_finished.emit(report)


# ------------------------------------------------------------------ call line placeholder


func _on_call_line_changed(open: bool) -> void:
	if not open or not get_tree().get_nodes_in_group(CALL_LINE_UI_GROUP).is_empty():
		return
	if call_line == null:
		# Created on the first opening; from then on it follows Session.call_line_changed itself.
		call_line = LivingCallLine.new()
		add_child(call_line)
		call_line.open()
