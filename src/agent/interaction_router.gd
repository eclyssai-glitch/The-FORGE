class_name InteractionRouter
extends RefCounted
## The interaction pipeline of MIKU (Loop 5, ADR-016):
##   USER -> INTENT -> LOCAL | PROVIDER -> PATCH -> VALIDATION -> MUTATION -> GAME STATE
## and, for every request, a PLAN: the sequence of vocabulary actions that shows the request on
## MIKU's body, performed one at a time by an ActionExecutor (the real `Miku` node through
## MikuNodeExecutor, or the null executor). The router never moves anything itself.
##
## Entry points: submit_text(text) (call line), call_attention() (click on MIKU),
## indicate_world(id) (click on a world). Perception is immediate (executor.notice_user() /
## target_world(id) as the request arrives); plans run in arrival order (a queue of at most
## MAX_QUEUE; older waiting requests are dropped beyond it).
##
## Configuration requests are validated up front (to choose the plan) and COMMITTED when the
## EDIT_FILE step finishes — validated again against the configuration of that moment, then
## applied atomically by MikuConfig: the change happens when her hand edits the file. Then she
## inspects herself, reacts and discards the file. Refusals (REQUIRES_ASSET, invalid, provider
## unavailable) get a "decline" plan and change nothing.
##
## Plans (ActionVocabulary steps):
##   attention        LOOK_AT_USER, ACKNOWLEDGE(warm), WORK(resume)
##   world target     LOOK_AT_WORLD(world), POINT(world), SUMMON_HANDS(2, world), WORK(world)
##   config applied   LOOK_AT_USER, ACKNOWLEDGE(brief), SUMMON_HAND(left, hold), GRAB_FILE,
##                    SUMMON_HAND(right, edit), EDIT_FILE(path, value) <commit>, INSPECT(self, path),
##                    SATISFIED, DISCARD(applied), WORK(resume)
##   config unchanged LOOK_AT_USER, ACKNOWLEDGE(brief), SUMMON_HAND(left, hold), GRAB_FILE,
##                    INSPECT(file, path), ACKNOWLEDGE(decline), DISCARD(not applied), WORK(resume)
##   requires asset   LOOK_AT_USER, THINK, INSPECT(self), ACKNOWLEDGE(decline), WORK(resume)
##   rejected/unknown LOOK_AT_USER, THINK, ACKNOWLEDGE(puzzled), WORK(resume)
##   semantic, no provider  LOOK_AT_USER, THINK, ACKNOWLEDGE(decline, provider_unavailable), WORK(resume)
## Steps that do not finish within STEP_TIMEOUT seconds (tick) are skipped with a warning.

## A request was understood (before its plan runs).
signal intent_parsed(intent: Intent)
## A plan starts (report: see `report` fields below).
signal plan_started(plan: Array, report: Dictionary)
## One step is handed to the executor.
signal action_dispatched(index: int, action: StringName, args: Dictionary)
## A configuration value really changed (game state).
signal mutation_applied(path: String, old_value: Variant, new_value: Variant)
## A request's plan ended. report = {"id", "kind", "route", "text", "rule", "target", "status",
## "plan": Array[StringName], "path", "old_value", "new_value", "notes", "reason"}.
signal request_finished(report: Dictionary)

const STEP_TIMEOUT := 15.0
const MAX_QUEUE := 4

## Report statuses.
const ST_ATTENTION := "attention"
const ST_WORLD := "world_target"
const ST_APPLIED := "applied"
const ST_UNCHANGED := "unchanged"
const ST_REJECTED := "rejected"
const ST_REQUIRES_ASSET := "requires_asset"
const ST_PROVIDER_UNAVAILABLE := "provider_unavailable"
const ST_PROVIDER_INVALID := "provider_invalid"
const ST_UNKNOWN := "unknown"
const ST_COMMIT_FAILED := "commit_failed"
const ST_CANCELLED := "cancelled"

var config: MikuConfig
var executor: ActionExecutor
var port: ProviderPort
## Selectable worlds for the parser and for world validation:
## [{"id": StringName, "name": String, "side": StringName}].
var worlds: Array = []
## Reports of every finished request (newest last).
var history: Array[Dictionary] = []

var _queue: Array[Dictionary] = []
var _active: Dictionary = {}
var _plan: Array = []
var _index := -1
var _waiting := false
var _pumping := false
var _elapsed := 0.0
var _next_id := 1


func _init(p_config: MikuConfig = null, p_executor: ActionExecutor = null, p_port: ProviderPort = null) -> void:
	config = p_config if p_config != null else MikuConfig.new()
	port = p_port if p_port != null else ProviderPort.new()
	set_executor(p_executor if p_executor != null else ActionExecutor.new())


## Swaps the executor (the step in flight, if any, is considered finished).
func set_executor(e: ActionExecutor) -> void:
	if executor != null and executor.action_finished.is_connected(_on_action_finished):
		executor.action_finished.disconnect(_on_action_finished)
	executor = e if e != null else ActionExecutor.new()
	executor.action_finished.connect(_on_action_finished)
	if _waiting:
		_waiting = false
		_pump()


# ------------------------------------------------------------------ entry points


## Text from the call line. Returns the parsed intent (its plan runs now or after the queue).
func submit_text(text: String) -> Intent:
	var intent := LocalParser.parse(text, worlds)
	intent.source = &"text"
	handle(intent)
	return intent


## A click on MIKU (or any direct call).
func call_attention(source: StringName = &"click") -> Intent:
	var intent := Intent.make(Intent.Kind.ATTENTION, "", &"miku")
	intent.source = source
	intent.rule = "gesture"
	handle(intent)
	return intent


## A click on world `id`.
func indicate_world(id: StringName, source: StringName = &"click") -> Intent:
	var intent := Intent.make(Intent.Kind.WORLD_TARGET, "", id)
	intent.source = source
	intent.rule = "gesture"
	handle(intent)
	return intent


## Routes an intent: perception now, plan queued. Returns the request's initial report.
func handle(intent: Intent) -> Dictionary:
	intent_parsed.emit(intent)
	var req := _build_request(intent)
	match intent.kind:
		Intent.Kind.ATTENTION:
			executor.notice_user()
		Intent.Kind.WORLD_TARGET:
			if _has_world(intent.target):
				executor.target_world(intent.target)
	_queue.append(req)
	while _queue.size() > MAX_QUEUE:
		var dropped: Dictionary = _queue.pop_front()
		var rep: Dictionary = dropped["report"]
		rep["status"] = ST_CANCELLED
		rep["reason"] = "queue full"
		_finish_report(rep)
	_pump()
	return req["report"]


## Advances the step timeout (call every frame with the frame's delta).
func tick(delta: float) -> void:
	if not _waiting:
		return
	_elapsed += delta
	if _elapsed >= STEP_TIMEOUT:
		var s: Dictionary = _plan[_index]
		push_warning("InteractionRouter: %s did not finish in %.0fs; skipped." % [s["action"], STEP_TIMEOUT])
		executor.pending = &""
		_step_done()


## True while a plan runs or requests wait.
func busy() -> bool:
	return not _plan.is_empty() or not _queue.is_empty()


## The step in flight ({"action", "args"}) or {}.
func current_step() -> Dictionary:
	return _plan[_index] if _waiting and _index >= 0 and _index < _plan.size() else {}


## Drops the running plan and every waiting request (scenario reset/recomposition). Nothing that
## was not committed is applied.
func cancel() -> void:
	var pending: Array[Dictionary] = []
	if not _active.is_empty():
		pending.append(_active["report"])
	for q in _queue:
		pending.append(q["report"])
	_queue.clear()
	_active = {}
	_plan = []
	_index = -1
	_waiting = false
	executor.pending = &""
	for rep in pending:
		rep["status"] = ST_CANCELLED
		_finish_report(rep)


# ------------------------------------------------------------------ plans


## {"intent", "plan", "commit_at" (step index or -1), "validation", "report"}.
func _build_request(intent: Intent) -> Dictionary:
	var rep := {"id": _next_id, "kind": intent.kind_name(), "route": intent.route_name(), "text": intent.text,
		"rule": intent.rule, "target": intent.target, "status": "", "plan": [], "path": "",
		"old_value": null, "new_value": null, "notes": [], "reason": "", "source": intent.source}
	_next_id += 1
	var req := {"intent": intent, "plan": [], "commit_at": -1, "validation": null, "report": rep}
	match intent.kind:
		Intent.Kind.ATTENTION:
			rep["status"] = ST_ATTENTION
			req["plan"] = attention_plan()
		Intent.Kind.WORLD_TARGET:
			if _has_world(intent.target):
				rep["status"] = ST_WORLD
				req["plan"] = world_plan(intent.target)
			else:
				rep["status"] = ST_UNKNOWN
				rep["reason"] = "unknown world %s" % intent.target
				req["plan"] = puzzled_plan(rep["reason"])
		Intent.Kind.CONFIG_PATCH:
			_config_request(req, intent.patch, [])
		Intent.Kind.SEMANTIC:
			_semantic_request(req, intent)
		_:
			rep["status"] = ST_UNKNOWN
			rep["reason"] = "not understood"
			req["plan"] = puzzled_plan("not_understood")
	rep["plan"] = ActionVocabulary.names(req["plan"])
	return req


## Fills `req` for a configuration patch; `prefix` = provider actions shown first.
func _config_request(req: Dictionary, patch: StructuredPatch, prefix: Array) -> void:
	var rep: Dictionary = req["report"]
	var v := ConfigValidator.validate(patch, config.values())
	req["validation"] = v
	rep["path"] = v.path
	rep["old_value"] = v.old_value
	rep["notes"] = Array(v.notes)
	match v.status:
		ConfigValidator.Status.OK, ConfigValidator.Status.CLAMPED:
			rep["status"] = ST_APPLIED
			rep["new_value"] = v.value
			var plan := prefix.duplicate()
			var edit := prefix.size()
			for i in prefix.size():
				if prefix[i]["action"] == ActionVocabulary.EDIT_FILE:
					edit = i
					break
			if edit < prefix.size():
				# The provider placed the edit: its args become the validated change.
				plan[edit] = _edit_step(v)
				req["commit_at"] = edit
			else:
				var tail := config_plan(v.path, v.value, v.old_value)
				if not prefix.is_empty():
					tail = tail.slice(2)  # the provider already reacted
				req["commit_at"] = plan.size() + _index_of(tail, ActionVocabulary.EDIT_FILE)
				plan.append_array(tail)
			req["plan"] = plan
		ConfigValidator.Status.UNCHANGED:
			rep["status"] = ST_UNCHANGED
			rep["new_value"] = v.value
			req["plan"] = _without_edit(prefix) + unchanged_plan(v.path)
		ConfigValidator.Status.REQUIRES_ASSET:
			rep["status"] = ST_REQUIRES_ASSET
			rep["reason"] = v.reason
			req["plan"] = _without_edit(prefix) + decline_plan("requires_asset", true)
		_:
			rep["status"] = ST_REJECTED
			rep["reason"] = v.reason
			req["plan"] = _without_edit(prefix) + puzzled_plan("invalid")


func _semantic_request(req: Dictionary, intent: Intent) -> void:
	var rep: Dictionary = req["report"]
	if port == null or not port.is_available():
		rep["status"] = ST_PROVIDER_UNAVAILABLE
		rep["reason"] = ProviderPort.UNAVAILABLE
		req["plan"] = decline_plan(ProviderPort.UNAVAILABLE)
		return
	var context := {"config": config.values(), "worlds": worlds.duplicate(true), "vocabulary": ActionVocabulary.ALL}
	var checked := ProviderPort.validate_response(port.request(intent, context))
	if not bool(checked["ok"]):
		var unavailable := String(checked["reason"]) == ProviderPort.UNAVAILABLE
		rep["status"] = ST_PROVIDER_UNAVAILABLE if unavailable else ST_PROVIDER_INVALID
		rep["reason"] = String(checked["reason"])
		rep["notes"] = Array(checked["errors"])
		req["plan"] = decline_plan(String(checked["reason"]) if unavailable else "provider_invalid")
		return
	var actions: Array = checked["actions"]
	var patch: StructuredPatch = checked["patch"]
	if patch != null:
		_config_request(req, patch, actions)
		return
	rep["status"] = "provider_actions"
	req["plan"] = _without_edit(actions) if not actions.is_empty() else puzzled_plan("empty_response")


static func attention_plan() -> Array:
	return [
		ActionVocabulary.step(ActionVocabulary.LOOK_AT_USER),
		ActionVocabulary.step(ActionVocabulary.ACKNOWLEDGE, {"tone": "warm"}),
		ActionVocabulary.step(ActionVocabulary.WORK, {"resume": true}),
	]


static func world_plan(id: StringName) -> Array:
	return [
		ActionVocabulary.step(ActionVocabulary.LOOK_AT_WORLD, {"world": id}),
		ActionVocabulary.step(ActionVocabulary.POINT, {"target": String(id)}),
		ActionVocabulary.step(ActionVocabulary.SUMMON_HANDS, {"count": 2, "world": id}),
		ActionVocabulary.step(ActionVocabulary.WORK, {"world": id}),
	]


static func config_plan(path: String, value: Variant, old_value: Variant) -> Array:
	return [
		ActionVocabulary.step(ActionVocabulary.LOOK_AT_USER),
		ActionVocabulary.step(ActionVocabulary.ACKNOWLEDGE, {"tone": "brief"}),
		ActionVocabulary.step(ActionVocabulary.SUMMON_HAND, {"side": "left", "role": "hold"}),
		ActionVocabulary.step(ActionVocabulary.GRAB_FILE, {"file": ConfigSchema.FILE}),
		ActionVocabulary.step(ActionVocabulary.SUMMON_HAND, {"side": "right", "role": "edit"}),
		ActionVocabulary.step(ActionVocabulary.EDIT_FILE, {"file": ConfigSchema.FILE, "path": path,
			"value": value, "old_value": old_value}),
		ActionVocabulary.step(ActionVocabulary.INSPECT, {"target": "self", "path": path}),
		ActionVocabulary.step(ActionVocabulary.SATISFIED, {"intensity": 0.6}),
		ActionVocabulary.step(ActionVocabulary.DISCARD, {"file": ConfigSchema.FILE, "applied": true}),
		ActionVocabulary.step(ActionVocabulary.WORK, {"resume": true}),
	]


static func unchanged_plan(path: String) -> Array:
	return [
		ActionVocabulary.step(ActionVocabulary.LOOK_AT_USER),
		ActionVocabulary.step(ActionVocabulary.ACKNOWLEDGE, {"tone": "brief"}),
		ActionVocabulary.step(ActionVocabulary.SUMMON_HAND, {"side": "left", "role": "hold"}),
		ActionVocabulary.step(ActionVocabulary.GRAB_FILE, {"file": ConfigSchema.FILE}),
		ActionVocabulary.step(ActionVocabulary.INSPECT, {"target": "file", "path": path}),
		ActionVocabulary.step(ActionVocabulary.ACKNOWLEDGE, {"tone": "decline", "reason": "unchanged"}),
		ActionVocabulary.step(ActionVocabulary.DISCARD, {"file": ConfigSchema.FILE, "applied": false}),
		ActionVocabulary.step(ActionVocabulary.WORK, {"resume": true}),
	]


## "Not now / I can't": she listens, thinks, declines (optionally glancing at herself), resumes.
static func decline_plan(reason: String, inspect_self: bool = false) -> Array:
	var plan := [
		ActionVocabulary.step(ActionVocabulary.LOOK_AT_USER),
		ActionVocabulary.step(ActionVocabulary.THINK, {"seconds": 1.5}),
	]
	if inspect_self:
		plan.append(ActionVocabulary.step(ActionVocabulary.INSPECT, {"target": "self"}))
	plan.append(ActionVocabulary.step(ActionVocabulary.ACKNOWLEDGE, {"tone": "decline", "reason": reason}))
	plan.append(ActionVocabulary.step(ActionVocabulary.WORK, {"resume": true}))
	return plan


static func puzzled_plan(reason: String) -> Array:
	return [
		ActionVocabulary.step(ActionVocabulary.LOOK_AT_USER),
		ActionVocabulary.step(ActionVocabulary.THINK, {"seconds": 1.0}),
		ActionVocabulary.step(ActionVocabulary.ACKNOWLEDGE, {"tone": "puzzled", "reason": reason}),
		ActionVocabulary.step(ActionVocabulary.WORK, {"resume": true}),
	]


static func _edit_step(v: ConfigValidator.Result) -> Dictionary:
	return ActionVocabulary.step(ActionVocabulary.EDIT_FILE, {"file": ConfigSchema.FILE, "path": v.path,
		"value": v.value, "old_value": v.old_value})


static func _without_edit(plan: Array) -> Array:
	return plan.filter(func(s: Dictionary) -> bool: return s["action"] != ActionVocabulary.EDIT_FILE)


static func _index_of(plan: Array, action: StringName) -> int:
	for i in plan.size():
		if plan[i]["action"] == action:
			return i
	return -1


func _has_world(id: StringName) -> bool:
	for w: Dictionary in worlds:
		if StringName(w.get("id", &"")) == id:
			return true
	return false


# ------------------------------------------------------------------ execution


func _pump() -> void:
	if _pumping:
		return
	_pumping = true
	while not _waiting:
		if _active.is_empty():
			if _queue.is_empty():
				break
			_begin(_queue.pop_front())
			continue
		if _index + 1 >= _plan.size():
			_end_active()
			continue
		_index += 1
		var s: Dictionary = _plan[_index]
		_waiting = true
		_elapsed = 0.0
		action_dispatched.emit(_index, s["action"], s["args"])
		executor.perform(s["action"], s["args"])
	_pumping = false


func _begin(req: Dictionary) -> void:
	_active = req
	_plan = req["plan"]
	_index = -1
	plan_started.emit(_plan, req["report"])


func _end_active() -> void:
	var rep: Dictionary = _active["report"]
	_active = {}
	_plan = []
	_index = -1
	_finish_report(rep)


func _finish_report(rep: Dictionary) -> void:
	history.append(rep)
	request_finished.emit(rep)


func _on_action_finished(action: StringName) -> void:
	if not _waiting or _index < 0 or _index >= _plan.size():
		return
	if StringName(_plan[_index]["action"]) != action:
		return
	_step_done()


func _step_done() -> void:
	_waiting = false
	if not _active.is_empty() and int(_active["commit_at"]) == _index:
		_commit()
	_pump()


## The hand finished editing: validate again against the configuration of this moment and
## apply. On failure the rest of the plan becomes the "not applied" tail.
func _commit() -> void:
	var rep: Dictionary = _active["report"]
	var first: ConfigValidator.Result = _active["validation"]
	var patch := StructuredPatch.absolute(first.path, first.value)
	var v := ConfigValidator.validate(patch, config.values())
	var old: Variant = config.get_value(v.path)
	if v.applicable() and config.apply(v):
		rep["new_value"] = v.value
		rep["old_value"] = old
		mutation_applied.emit(v.path, old, v.value)
		executor.config_changed(v.path, old, v.value)
		return
	rep["status"] = ST_COMMIT_FAILED if v.applicable() else ST_UNCHANGED
	rep["reason"] = "write failed" if v.applicable() else "already %s" % str(v.value)
	rep["new_value"] = null
	var tail := [
		ActionVocabulary.step(ActionVocabulary.ACKNOWLEDGE, {"tone": "decline", "reason": rep["status"]}),
		ActionVocabulary.step(ActionVocabulary.DISCARD, {"file": ConfigSchema.FILE, "applied": false}),
		ActionVocabulary.step(ActionVocabulary.WORK, {"resume": true}),
	]
	_plan = _plan.slice(0, _index + 1) + tail
	_active["plan"] = _plan
	rep["plan"] = ActionVocabulary.names(_plan)
