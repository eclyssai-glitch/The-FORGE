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
## target_world(id) as the request arrives).
##
## CORRELATED ACTIONS (docs/contracts/loop-05-round2.md). Every request gets a `request_id` (int > 0,
## unique in the process: a static counter shared by every router, so a recomposed scenario never
## reuses one). Each dispatched step carries `args.request_id` and `args.step` (index in the plan);
## the router listens to executor.action_event(request_id, action, phase, info) and accepts ONLY
## events of its active request and current step (`info.step`; without it, the action name must
## match). MIKU's own performs (roteiro, agenda) use request_id 0 and are never consumed.
## Step timeout = executor.estimate_duration(action, args) x TIMEOUT_FACTOR + TIMEOUT_MARGIN, on the
## router's clock (tick(delta); LivingInteraction feeds it MotionClock time, the body's clock). A
## timed-out step is cancelled on the body (executor.cancel(request_id)) and recorded as a failure.
## Failures (&"failed", a &"cancelled" the router did not ask for, timeout): the plan goes on, except
## GRAB_FILE / EDIT_FILE of a configuration plan before its commit — then the change is NOT applied
## and the rest of the plan becomes the "not applied" tail (status commit_failed, reason).
## Nothing waits on an external event without a timeout; perform() never blocks.
##
## QUEUE: one plan runs, the others wait in FIFO order (at most MAX_QUEUE waiting; the oldest
## waiting request is dropped beyond it). A new ATTENTION request may INTERRUPT the running plan
## (not another attention): never inside the file section of a configuration plan (GRAB_FILE ..
## EDIT_FILE); otherwise when the fraction of the plan still to run is greater than
## 1 - behaviour.interruption_tolerance (0 = never interrupted, 1 = always). The interrupted plan is
## cancelled on the body (executor.cancel) and re-queued right after the attention plan with a new
## request_id (it restarts from its first step; nothing was committed) — or, when its change was
## already committed, it simply ends (its report says `interrupted`). cancel() (reset /
## recomposition) cancels the running plan on the body and drops every waiting request.
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

## A request was understood (before its plan runs).
signal intent_parsed(intent: Intent)
## A request's plan starts — emitted BEFORE its first step is dispatched (so before any action can
## finish). started = {"id", "request_id", "kind", "route", "status": &"started", "target", "path",
## "plan": Array[StringName], "text", "source", "expected_status", "estimate" (s), "deadline" (worst
## case: sum of the step timeouts, s), "restart": bool}.
signal request_started(started: Dictionary)
## A plan starts (report: see `report` fields below).
signal plan_started(plan: Array, report: Dictionary)
## One step is handed to the executor (args include request_id and step).
signal action_dispatched(index: int, action: StringName, args: Dictionary)
## A configuration value really changed (game state).
signal mutation_applied(path: String, old_value: Variant, new_value: Variant)
## A request's plan ended. report = {"id", "request_id", "kind", "route", "text", "rule", "target",
## "status", "plan": Array[StringName], "path", "old_value", "new_value", "notes", "reason", "source",
## "steps": [{"step", "action", "estimate", "timeout", "elapsed", "latency", "result", "reason"}],
## "failures": [{"step", "action", "reason"}], "estimate", "duration", "interrupted", "request_ids"}.
signal request_finished(report: Dictionary)

## Step timeout = estimate x TIMEOUT_FACTOR + TIMEOUT_MARGIN (seconds).
const TIMEOUT_FACTOR := 2.0
const TIMEOUT_MARGIN := 3.0
const MAX_QUEUE := 4
## Default of behaviour.interruption_tolerance when the configuration has none.
const DEFAULT_INTERRUPTION_TOLERANCE := 0.5

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
## Status of request_started's payload.
const ST_STARTED := &"started"

## Step results (report["steps"][i]["result"]).
const R_FINISHED := "finished"
const R_FAILED := "failed"
const R_TIMEOUT := "timeout"
const R_CANCELLED := "cancelled"
const R_INTERRUPTED := "interrupted"

## Actions whose failure before the commit means the change cannot be applied.
const CRITICAL: Array[StringName] = [ActionVocabulary.GRAB_FILE, ActionVocabulary.EDIT_FILE]

## Last request_id handed out in this process (shared by every router: unique per session).
static var _request_seq := 0

var config: MikuConfig
var executor: ActionExecutor
var port: ProviderPort
## Selectable worlds for the parser and for world validation:
## [{"id": StringName, "name": String, "side": StringName}].
var worlds: Array = []
## Reports of every finished request (newest last).
var history: Array[Dictionary] = []
## Events received that were not for the step in flight (other request/step, request_id 0, late).
var ignored_events := 0

var _queue: Array[Dictionary] = []
var _active: Dictionary = {}
var _plan: Array = []
var _index := -1
var _waiting := false
var _pumping := false
## Router clock (sum of tick deltas) and the step in flight: dispatch time, estimate, timeout,
## time of its accepted/started events, last phase.
var _clock := 0.0
var _elapsed := 0.0
var _step_at := 0.0
var _step_estimate := 0.0
var _step_timeout := 0.0
var _step_started_at := -1.0
var _step_phase: StringName = &""
var _plan_at := 0.0
var _next_id := 1


func _init(p_config: MikuConfig = null, p_executor: ActionExecutor = null, p_port: ProviderPort = null) -> void:
	config = p_config if p_config != null else MikuConfig.new()
	port = p_port if p_port != null else ProviderPort.new()
	set_executor(p_executor if p_executor != null else ActionExecutor.new())


## A new request id (> 0, never reused in this process).
static func next_request_id() -> int:
	_request_seq += 1
	return _request_seq


## Swaps the executor. A step in flight is cancelled on the old executor and recorded as failed
## ("executor replaced"); the plan goes on with the new one.
func set_executor(e: ActionExecutor) -> void:
	var old := executor
	if old != null and old.action_event.is_connected(_on_action_event):
		old.action_event.disconnect(_on_action_event)
	executor = e if e != null else ActionExecutor.new()
	executor.action_event.connect(_on_action_event)
	if _waiting and old != null:
		_waiting = false
		old.cancel(int(_active["request_id"]))
		_step_failed(R_FAILED, "executor replaced")


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


## Routes an intent: perception now, plan queued (or run now; an ATTENTION may interrupt the
## running plan, see QUEUE). Returns the request's report (filled in as the plan runs).
func handle(intent: Intent) -> Dictionary:
	intent_parsed.emit(intent)
	var req := _build_request(intent)
	match intent.kind:
		Intent.Kind.ATTENTION:
			executor.notice_user()
		Intent.Kind.WORLD_TARGET:
			if _has_world(intent.target):
				executor.target_world(intent.target)
	if intent.kind == Intent.Kind.ATTENTION and should_interrupt():
		var interrupted := _interrupt_active()
		_queue.push_front(req)
		if not interrupted.is_empty():
			_queue.insert(1, interrupted)
	else:
		_queue.append(req)
	while _queue.size() > MAX_QUEUE:
		var dropped: Dictionary = _queue.pop_front()
		var rep: Dictionary = dropped["report"]
		rep["status"] = ST_CANCELLED
		rep["reason"] = "queue full"
		_finish_report(rep)
	_pump()
	return req["report"]


## Advances the router's clock (call every frame with the frame's delta, on the body's clock):
## the executor's simulated time, then the step timeout.
func tick(delta: float) -> void:
	if delta <= 0.0:
		return
	_clock += delta
	executor.advance(delta)
	if not _waiting:
		return
	_elapsed = _clock - _step_at
	if _elapsed >= _step_timeout:
		var s: Dictionary = _plan[_index]
		push_warning("InteractionRouter: request %d step %d %s did not finish in %.1fs (estimate %.1fs); cancelled." % [
			int(_active["request_id"]), _index, s["action"], _step_timeout, _step_estimate])
		var rid := int(_active["request_id"])
		_waiting = false  # the body's &"cancelled" answer is not for a step in flight any more
		executor.cancel(rid)
		_step_failed(R_TIMEOUT, "timeout after %.1fs (estimate %.1fs)" % [_elapsed, _step_estimate])


## True while a plan runs or requests wait.
func busy() -> bool:
	return not _plan.is_empty() or not _queue.is_empty()


## True while request `request_id` runs or waits.
func has_request(request_id: int) -> bool:
	if not _active.is_empty() and int(_active["request_id"]) == request_id:
		return true
	for q in _queue:
		if int(q["request_id"]) == request_id:
			return true
	return false


## request_id of the running plan (0 when idle).
func active_request_id() -> int:
	return int(_active.get("request_id", 0))


## The step in flight ({"action", "args"}) or {}.
func current_step() -> Dictionary:
	return _plan[_index] if _waiting and _index >= 0 and _index < _plan.size() else {}


## Seconds `plan` should take on the current executor (sum of its estimates).
func estimate_plan(plan: Array) -> float:
	var total := 0.0
	for s: Dictionary in plan:
		total += maxf(0.0, executor.estimate_duration(s["action"], s["args"]))
	return total


## Worst case of `plan` on the current executor: every step ends by its timeout at the latest
## (sum of step_timeout(estimate)). A request never runs longer than this once started.
func plan_deadline(plan: Array) -> float:
	var total := 0.0
	for s: Dictionary in plan:
		total += step_timeout(executor.estimate_duration(s["action"], s["args"]))
	return total


## The plan `intent` would get now, without side effects: no request id, nothing queued, no
## provider asked (a SEMANTIC intent previews as the "no provider" decline). For budgets (smoke).
func preview_plan(intent: Intent) -> Array:
	return _build_request(intent, true)["plan"]


## Timeout of one step whose estimate is `estimate` seconds.
static func step_timeout(estimate: float) -> float:
	return maxf(0.0, estimate) * TIMEOUT_FACTOR + TIMEOUT_MARGIN


## Read-only view of the pipeline (LivingInteraction.inspect_state, dev inspector): the vocabulary
## action in flight and its arguments, the plan, the queue, the active and the last request.
## Copies only: changing the result changes nothing here.
func snapshot() -> Dictionary:
	var step := current_step()
	return {
		"action": String(step.get("action", &"")),
		"action_args": (step.get("args", {}) as Dictionary).duplicate(true),
		"request_id": active_request_id(),
		"step_index": _index,
		"step_phase": String(_step_phase) if _waiting else "",
		"step_estimate": _step_estimate if _waiting else 0.0,
		"step_timeout": _step_timeout if _waiting else 0.0,
		"plan": ActionVocabulary.names(_plan),
		"waiting": _waiting,
		"step_elapsed": _elapsed,
		"queue": _queue.size(),
		"active_request": (_active["report"] as Dictionary).duplicate(true) if not _active.is_empty() else {},
		"last_report": history.back().duplicate(true) if not history.is_empty() else {},
		"requests_finished": history.size(),
		"ignored_events": ignored_events,
		"executor_bound": executor.is_bound(),
		"executor_correlated": executor.is_correlated(),
		"executor_pending": String(executor.pending),
		"provider_available": port.is_available(),
	}


## Cancels the running plan on the body and drops every waiting request (scenario reset /
## recomposition). Nothing that was not committed is applied. Never waits for the body.
func cancel() -> void:
	var pending: Array[Dictionary] = []
	if not _active.is_empty():
		var rid := int(_active["request_id"])
		var was_waiting := _waiting
		_waiting = false
		if was_waiting:
			_record_step(R_CANCELLED, "router cancelled")
		executor.cancel(rid)
		pending.append(_active["report"])
	for q in _queue:
		pending.append(q["report"])
	_queue.clear()
	_active = {}
	_plan = []
	_index = -1
	_waiting = false
	for rep in pending:
		rep["status"] = ST_CANCELLED
		if String(rep.get("reason", "")) == "":
			rep["reason"] = "cancelled"
		_finish_report(rep)


## True when a new ATTENTION request would interrupt the running plan now (see QUEUE).
func should_interrupt() -> bool:
	if _active.is_empty() or _plan.is_empty():
		return false
	var rep: Dictionary = _active["report"]
	if String(rep["kind"]) == "ATTENTION":
		return false
	if _in_file_section():
		return false
	var tolerance := clampf(float(_config_value("behaviour.interruption_tolerance",
		DEFAULT_INTERRUPTION_TOLERANCE)), 0.0, 1.0)
	var remaining := float(_plan.size() - maxi(_index, 0)) / float(_plan.size())
	return remaining > 1.0 - tolerance


# ------------------------------------------------------------------ plans


## {"intent", "plan", "commit_at" (step index or -1), "validation", "report"}.
func _build_request(intent: Intent, preview := false) -> Dictionary:
	var rid := 0 if preview else next_request_id()
	var rep := {"id": _next_id, "request_id": rid, "kind": intent.kind_name(), "route": intent.route_name(),
		"text": intent.text, "rule": intent.rule, "target": intent.target, "status": "", "plan": [], "path": "",
		"old_value": null, "new_value": null, "notes": [], "reason": "", "source": intent.source,
		"steps": [], "failures": [], "estimate": 0.0, "duration": 0.0, "interrupted": 0, "request_ids": [rid]}
	if not preview:
		_next_id += 1
	var req := {"intent": intent, "plan": [], "commit_at": -1, "validation": null, "report": rep,
		"request_id": rid, "committed": false}
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
		Intent.Kind.SEMANTIC when preview:
			rep["status"] = ST_PROVIDER_UNAVAILABLE if not port.is_available() else "provider_actions"
			req["plan"] = decline_plan(ProviderPort.UNAVAILABLE)
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
		_dispatch(_index + 1)
	_pumping = false


## Hands step `i` of the active plan to the executor, with its correlation and its timeout.
func _dispatch(i: int) -> void:
	_index = i
	var s: Dictionary = _plan[i]
	var args: Dictionary = (s["args"] as Dictionary).duplicate()
	args["request_id"] = int(_active["request_id"])
	args["step"] = i
	_step_estimate = maxf(0.0, executor.estimate_duration(s["action"], args))
	_step_timeout = step_timeout(_step_estimate)
	_step_at = _clock
	_elapsed = 0.0
	_step_started_at = -1.0
	_step_phase = &"dispatched"
	_waiting = true
	action_dispatched.emit(i, s["action"], args)
	executor.perform(s["action"], args)


func _begin(req: Dictionary) -> void:
	_active = req
	_plan = req["plan"]
	_index = -1
	_plan_at = _clock
	var rep: Dictionary = req["report"]
	rep["request_id"] = int(req["request_id"])
	request_started.emit({"id": rep["id"], "request_id": rep["request_id"], "kind": rep["kind"],
		"route": rep["route"], "status": ST_STARTED, "target": rep["target"], "path": rep["path"],
		"plan": ActionVocabulary.names(_plan), "text": rep["text"], "source": rep["source"],
		"expected_status": rep["status"], "estimate": snappedf(estimate_plan(_plan), 0.01),
		"deadline": snappedf(plan_deadline(_plan), 0.01), "restart": bool(req.get("restart", false))})
	plan_started.emit(_plan, rep)


func _end_active() -> void:
	var rep: Dictionary = _active["report"]
	rep["duration"] = snappedf(float(rep["duration"]) + _clock - _plan_at, 0.001)
	_active = {}
	_plan = []
	_index = -1
	_finish_report(rep)


func _finish_report(rep: Dictionary) -> void:
	rep["estimate"] = snappedf(float(rep.get("estimate", 0.0)), 0.01)
	history.append(rep)
	request_finished.emit(rep)


## Correlation: only events of the active request and of the step in flight count.
func _on_action_event(request_id: int, action: StringName, phase: StringName, info: Dictionary) -> void:
	if request_id <= 0 or not _waiting or _active.is_empty() or request_id != int(_active["request_id"]) \
			or _index < 0 or _index >= _plan.size():
		ignored_events += 1
		return
	if action != StringName(_plan[_index]["action"]) or (info.has("step") and int(info["step"]) != _index):
		ignored_events += 1
		return
	match phase:
		ActionExecutor.PH_ACCEPTED, ActionExecutor.PH_PROGRESS:
			_step_phase = phase
		ActionExecutor.PH_STARTED:
			_step_phase = phase
			if _step_started_at < 0.0:
				_step_started_at = _clock
		ActionExecutor.PH_FINISHED:
			_step_done()
		ActionExecutor.PH_FAILED:
			_step_failed(R_FAILED, str(info.get("reason", "failed")))
		ActionExecutor.PH_CANCELLED:
			_step_failed(R_CANCELLED, "cancelled by the body (%s)" % str(info.get("reason", "")))
		_:
			ignored_events += 1


func _step_done() -> void:
	_waiting = false
	_record_step(R_FINISHED, "")
	if int(_active["commit_at"]) == _index:
		_commit()
	_pump()


## The step in flight failed / timed out / was cancelled by the body. The plan goes on, unless the
## step is GRAB_FILE / EDIT_FILE of a change not committed yet: then nothing is applied and the
## rest of the plan becomes the "not applied" tail.
func _step_failed(result: String, reason: String) -> void:
	_waiting = false
	_record_step(result, reason)
	var rep: Dictionary = _active["report"]
	var s: Dictionary = _plan[_index]
	(rep["failures"] as Array).append({"step": _index, "action": String(s["action"]), "reason": "%s: %s" % [result, reason]})
	var commit_at := int(_active["commit_at"])
	if commit_at >= 0 and _index <= commit_at and not bool(_active["committed"]) and StringName(s["action"]) in CRITICAL:
		_not_applied(ST_COMMIT_FAILED, "%s %s: %s" % [s["action"], result, reason])
	_pump()


## Appends the step in flight to the report (timings on the router's clock).
func _record_step(result: String, reason: String) -> void:
	var rep: Dictionary = _active["report"]
	var s: Dictionary = _plan[_index]
	(rep["steps"] as Array).append({"step": _index, "action": String(s["action"]),
		"estimate": snappedf(_step_estimate, 0.01), "timeout": snappedf(_step_timeout, 0.01),
		"elapsed": snappedf(_clock - _step_at, 0.001),
		"latency": snappedf(_step_started_at - _step_at, 0.001) if _step_started_at >= 0.0 else -1.0,
		"result": result, "reason": reason})
	rep["estimate"] = float(rep["estimate"]) + _step_estimate
	_step_phase = StringName(result)


## Stops the running plan for an ATTENTION request: cancelled on the body; returns the request to
## re-queue (new request_id, restarts from its first step) or {} when its change was already
## committed (then its report ends here).
func _interrupt_active() -> Dictionary:
	var req := _active
	var rep: Dictionary = req["report"]
	var rid := int(req["request_id"])
	if _waiting:
		_waiting = false
		_record_step(R_INTERRUPTED, "attention")
	executor.cancel(rid)
	rep["interrupted"] = int(rep["interrupted"]) + 1
	rep["duration"] = float(rep["duration"]) + _clock - _plan_at
	_active = {}
	_plan = []
	_index = -1
	if bool(req["committed"]):
		(rep["notes"] as Array).append("interrupted by attention after the change was committed")
		rep["duration"] = snappedf(float(rep["duration"]), 0.001)
		_finish_report(rep)
		return {}
	var nrid := next_request_id()
	req["request_id"] = nrid
	rep["request_id"] = nrid
	(rep["request_ids"] as Array).append(nrid)
	req["restart"] = true
	return req


## True while the running configuration plan is between its GRAB_FILE and its commit (EDIT_FILE):
## the file is in her hands — she does not let go of it for a call.
func _in_file_section() -> bool:
	var commit_at := int(_active.get("commit_at", -1))
	if commit_at < 0 or bool(_active.get("committed", false)) or _index < 0:
		return false
	var first := _index_of(_plan, ActionVocabulary.GRAB_FILE)
	if first < 0 or first > commit_at:
		first = commit_at
	return _index >= first and _index <= commit_at


func _config_value(path: String, fallback: Variant) -> Variant:
	var v: Variant = config.get_value(path) if config != null else null
	return v if v != null else fallback


## The hand finished editing: validate again against the configuration of this moment and
## apply. On failure the rest of the plan becomes the "not applied" tail.
func _commit() -> void:
	_active["committed"] = true
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
	_not_applied(ST_COMMIT_FAILED if v.applicable() else ST_UNCHANGED,
		"write failed" if v.applicable() else "already %s" % str(v.value))


## Nothing is applied: status/reason set and the rest of the plan replaced by
## ACKNOWLEDGE(decline), DISCARD(not applied), WORK(resume).
func _not_applied(status: String, reason: String) -> void:
	var rep: Dictionary = _active["report"]
	rep["status"] = status
	rep["reason"] = reason
	rep["new_value"] = null
	_active["commit_at"] = -1
	var tail := [
		ActionVocabulary.step(ActionVocabulary.ACKNOWLEDGE, {"tone": "decline", "reason": status}),
		ActionVocabulary.step(ActionVocabulary.DISCARD, {"file": ConfigSchema.FILE, "applied": false}),
		ActionVocabulary.step(ActionVocabulary.WORK, {"resume": true}),
	]
	_plan = _plan.slice(0, _index + 1) + tail
	_active["plan"] = _plan
	rep["plan"] = ActionVocabulary.names(_plan)
