class_name ActionExecutor
extends RefCounted
## Who performs MIKU's actions for the InteractionRouter. This base class is the NULL executor:
## it has no body and every call is recorded in `calls`. It keeps the interaction pipeline
## testable and running when the MIKU node does not exist yet. MikuNodeExecutor (same API) drives
## the real `Miku` node of the animator.
##
## Correlated protocol (docs/contracts/loop-05-round2.md, docs/AGENT.md "Protocolo"):
##   perform(action, args)  args carries `request_id` (> 0, the router's request) and `step` (index in
##       the plan). The executor answers with action_event(request_id, action, phase, info):
##       &"accepted" -> &"started" -> (&"progress", info.t 0..1)* -> exactly ONE terminal
##       &"finished" | &"failed" (info.reason) | &"cancelled". `info.step` echoes args.step.
##   estimate_duration(action, args) -> float   honest real-time estimate (seconds)
##   cancel(request_id)                          ends that request's actions with &"cancelled"
##   advance(dt)                                 the router's clock (the null executor's simulated time)
##   notice_user() / target_world(id)            perception (immediate, no plan step)
##   apply_config(values) / config_changed(path, old, new)
##
## Null behaviour: perform() emits accepted + started at once, then finished
##   - synchronously when `auto_finish` and `simulated_duration <= 0` (the default),
##   - after `simulated_duration` seconds of advance(dt) when `auto_finish` and it is > 0,
##   - only on finish() / fail(reason) when `auto_finish` is false (manual mode, tests).
## `durations` (action -> seconds) overrides simulated_duration per action; estimate_duration()
## returns the same value (an honest estimate for a simulated body).

## Correlated lifecycle of one performed action (see the protocol above).
signal action_event(request_id: int, action: StringName, phase: StringName, info: Dictionary)
## LEGACY (rounds before Loop 5 R2): one per finished action, uncorrelated. Still emitted by the
## null executor for old listeners; the router never uses it.
signal action_finished(action: StringName)

const PH_ACCEPTED := &"accepted"
const PH_STARTED := &"started"
const PH_PROGRESS := &"progress"
const PH_FINISHED := &"finished"
const PH_FAILED := &"failed"
const PH_CANCELLED := &"cancelled"
const TERMINAL: Array[StringName] = [PH_FINISHED, PH_FAILED, PH_CANCELLED]

## When true, actions end by themselves (at once, or after their simulated duration).
var auto_finish := true
## Simulated duration (seconds of advance()) of every action; 0 = finishes inside perform().
var simulated_duration := 0.0
## Per-action simulated durations (action -> seconds); overrides simulated_duration.
var durations: Dictionary = {}
## Every call received, in order: [method, ...args] (e.g. [&"perform", &"THINK", {...}]).
var calls: Array = []
## Every action_event emitted, in order: [request_id, action, phase, info].
var events: Array = []
## Action performed and not finished yet, or &"".
var pending: StringName = &""
## request_id / step of the pending action (0 / -1 when none).
var pending_request := 0
var pending_step := -1
var _left := 0.0


## True when a real body performs the actions (false for the null executor).
func is_bound() -> bool:
	return false


## True when the executor speaks the correlated protocol (action_event). The router falls back to
## the legacy action_finished only when this is false.
func is_correlated() -> bool:
	return true


func perform(action: StringName, args: Dictionary = {}) -> void:
	calls.append([&"perform", action, args])
	if pending != &"":
		# A new perform supersedes an unfinished one (the router never does this; tests might).
		_emit_terminal(PH_CANCELLED, {"reason": "superseded"})
	pending = action
	pending_request = int(args.get("request_id", 0))
	pending_step = int(args.get("step", -1))
	_left = estimate_duration(action, args)
	emit_event(pending_request, action, PH_ACCEPTED, {"step": pending_step, "estimate": _left})
	emit_event(pending_request, action, PH_STARTED, {"step": pending_step})
	if auto_finish and _left <= 0.0:
		finish()


## Seconds the action takes on this (simulated) body.
func estimate_duration(action: StringName, _args: Dictionary = {}) -> float:
	return float(durations.get(action, simulated_duration))


## Advances the simulated time: an auto-finishing action ends when its duration has elapsed.
func advance(dt: float) -> void:
	if pending == &"" or not auto_finish or dt <= 0.0:
		return
	_left -= dt
	if _left <= 0.0:
		finish()


## Ends the pending action successfully (manual mode; also used by auto_finish).
func finish() -> void:
	if pending == &"":
		return
	var a := pending
	_emit_terminal(PH_FINISHED, {})
	action_finished.emit(a)


## Ends the pending action with a failure (manual mode).
func fail(reason: String = "failed") -> void:
	_emit_terminal(PH_FAILED, {"reason": reason})


## Cancels the actions of `request_id` (the pending one, if it belongs to it).
func cancel(request_id: int) -> void:
	calls.append([&"cancel", request_id])
	if pending != &"" and pending_request == request_id:
		_emit_terminal(PH_CANCELLED, {"reason": "cancelled"})


## Emits one action_event (and records it). Tests use it to fake a body's events.
func emit_event(request_id: int, action: StringName, phase: StringName, info: Dictionary = {}) -> void:
	events.append([request_id, action, phase, info])
	action_event.emit(request_id, action, phase, info)


func notice_user() -> void:
	calls.append([&"notice_user"])


func target_world(id: StringName) -> void:
	calls.append([&"target_world", id])


func apply_config(values: Dictionary) -> void:
	calls.append([&"apply_config", values])


func config_changed(path: String, old_value: Variant, new_value: Variant) -> void:
	calls.append([&"config_changed", path, old_value, new_value])


## Names of the actions performed so far (perform calls only).
func performed() -> Array[StringName]:
	var out: Array[StringName] = []
	for c: Array in calls:
		if c[0] == &"perform":
			out.append(c[1])
	return out


func _emit_terminal(phase: StringName, info: Dictionary) -> void:
	if pending == &"":
		return
	var a := pending
	var rid := pending_request
	var d := info.duplicate()
	d["step"] = pending_step
	pending = &""
	pending_request = 0
	pending_step = -1
	_left = 0.0
	emit_event(rid, a, phase, d)
