class_name MikuNodeExecutor
extends ActionExecutor
## Executor bound to the animator's `Miku` node (res://src/miku/miku.gd, docs/contracts/loop-05.md):
##   Miku.perform(action: StringName, args := {})   Miku.notice_user()   Miku.target_world(id)
##   signals action_started(action), action_finished(action), mood_changed(state)
## Optional (called when present): Miku.apply_config(values: Dictionary),
## Miku.on_config_changed(path: String, old_value, new_value).
## The node's `action_finished` is forwarded as this executor's `action_finished`. A missing
## method degrades to the null behaviour (perform finishes at once) with one warning per method.
## Holds the node weakly: once the node is freed (scenario recomposed) the executor behaves as
## the null executor.

var _node: WeakRef
var _warned := {}


func _init(node: Object) -> void:
	auto_finish = false
	_node = weakref(node)
	if node != null and node.has_signal(&"action_finished"):
		node.connect(&"action_finished", _on_node_action_finished)


func node() -> Object:
	return _node.get_ref() if _node else null


func is_bound() -> bool:
	var n := node()
	return n != null and n.has_method(&"perform")


func perform(action: StringName, args: Dictionary = {}) -> void:
	calls.append([&"perform", action, args])
	pending = action
	var n := node()
	if n != null and n.has_method(&"perform"):
		n.call(&"perform", action, args)
	else:
		_warn_once(&"perform")
		finish()


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
