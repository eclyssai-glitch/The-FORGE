class_name MikuNodeExecutor
extends ActionExecutor
## Executor bound to the animator's `Miku` node (res://src/miku/miku.gd).
##
## Correlated protocol (docs/contracts/loop-05-round2.md; the node implements it):
##   Miku.perform(action: StringName, args := {}) -> bool   args carries request_id and step
##   signal Miku.action_event(request_id: int, action: StringName, phase: StringName, info: Dictionary)
##   Miku.estimate_duration(action: StringName, args: Dictionary) -> float
##   Miku.cancel(request_id: int)
##   Miku.notice_user()   Miku.target_world(id)
## Optional (called when present): Miku.apply_config(values), Miku.on_config_changed(path, old, new).
## The node's action_event is forwarded as this executor's action_event (the router filters by its
## own request_id/step; the node's own performs use request_id 0 and are never consumed). A perform
## the node refuses (returns false) ends at once with &"failed" (reason "refused").
##
## LEGACY (a node without action_event): perform() emits accepted/started itself and the node's
## uncorrelated action_finished(action) is turned into &"finished" for the pending request when the
## names match — the old behaviour, kept only so an older body still runs; cancel() then just
## forgets the pending action. Without estimate_duration the vocabulary's nominal durations are used.
## A missing method degrades to the null behaviour (perform finishes at once) with one warning per
## method. Holds the node weakly: once the node is freed (scenario recomposed) the executor behaves
## as the null executor.

var _node: WeakRef
var _warned := {}
var _correlated := false


func _init(node: Object) -> void:
	auto_finish = false
	_node = weakref(node)
	if node == null:
		return
	if node.has_signal(&"action_event"):
		_correlated = true
		node.connect(&"action_event", _on_node_action_event)
	elif node.has_signal(&"action_finished"):
		node.connect(&"action_finished", _on_node_action_finished)


func node() -> Object:
	return _node.get_ref() if _node else null


func is_bound() -> bool:
	var n := node()
	return n != null and n.has_method(&"perform")


## True when the node emits action_event (false = legacy body or no body).
func is_correlated() -> bool:
	return _correlated and node() != null


func perform(action: StringName, args: Dictionary = {}) -> void:
	calls.append([&"perform", action, args])
	pending = action
	pending_request = int(args.get("request_id", 0))
	pending_step = int(args.get("step", -1))
	var n := node()
	if n == null or not n.has_method(&"perform"):
		_warn_once(&"perform")
		emit_event(pending_request, action, PH_ACCEPTED, {"step": pending_step})
		emit_event(pending_request, action, PH_STARTED, {"step": pending_step})
		finish()
		return
	if not is_correlated():
		emit_event(pending_request, action, PH_ACCEPTED, {"step": pending_step, "legacy": true})
		emit_event(pending_request, action, PH_STARTED, {"step": pending_step, "legacy": true})
	var rid := pending_request
	var step := pending_step
	var accepted: Variant = n.call(&"perform", action, args)
	if accepted is bool and not accepted and pending == action and pending_request == rid and pending_step == step:
		fail("refused")


func estimate_duration(action: StringName, args: Dictionary = {}) -> float:
	var n := node()
	if n != null and n.has_method(&"estimate_duration"):
		var v: Variant = n.call(&"estimate_duration", action, args)
		if (v is float or v is int) and float(v) >= 0.0:
			return float(v)
	return ActionVocabulary.nominal_duration(action, args)


func cancel(request_id: int) -> void:
	calls.append([&"cancel", request_id])
	var n := node()
	if is_correlated() and n.has_method(&"cancel"):
		n.call(&"cancel", request_id)
		# The node answers with &"cancelled"; if it did not (nothing of that request was running),
		# the executor forgets the pending action itself.
	if pending != &"" and pending_request == request_id:
		_emit_terminal(PH_CANCELLED, {"reason": "cancelled"})


## The router's clock: a real body keeps its own time (nothing to advance here).
func advance(_dt: float) -> void:
	pass


func notice_user() -> void:
	calls.append([&"notice_user"])
	_call_optional(&"notice_user", [])


func target_world(id: StringName) -> void:
	calls.append([&"target_world", id])
	_call_optional(&"target_world", [id])


func apply_config(values: Dictionary) -> void:
	calls.append([&"apply_config", values])
	_call_optional(&"apply_config", [values], false)


func config_changed(path: String, old_value: Variant, new_value: Variant) -> void:
	calls.append([&"config_changed", path, old_value, new_value])
	_call_optional(&"on_config_changed", [path, old_value, new_value], false)


func _on_node_action_event(request_id: int, action: StringName, phase: StringName, info: Dictionary) -> void:
	if request_id > 0 and pending != &"" and request_id == pending_request and phase in TERMINAL \
			and action == pending and int(info.get("step", pending_step)) == pending_step:
		pending = &""
		pending_request = 0
		pending_step = -1
	if request_id > 0:
		events.append([request_id, action, phase, info])
	action_event.emit(request_id, action, phase, info)


## LEGACY body: an uncorrelated action_finished ends the pending action when the names match.
func _on_node_action_finished(action: StringName) -> void:
	if pending != &"" and action == pending:
		finish()


func _call_optional(method: StringName, args: Array, warn: bool = true) -> void:
	var n := node()
	if n != null and n.has_method(method):
		n.callv(method, args)
	elif warn:
		_warn_once(method)


func _warn_once(method: StringName) -> void:
	if _warned.has(method):
		return
	_warned[method] = true
	push_warning("MikuNodeExecutor: Miku has no %s(); null behaviour." % method)
