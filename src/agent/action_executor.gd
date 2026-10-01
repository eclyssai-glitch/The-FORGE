class_name ActionExecutor
extends RefCounted
## Who performs MIKU's actions for the InteractionRouter. This base class is the NULL executor:
## it has no body — every action "finishes" at once (or when `finish()` is called, with
## `auto_finish = false`) and every call is recorded in `calls`. It keeps the interaction
## pipeline testable and running when the MIKU node does not exist yet.
## MikuNodeExecutor (same API) drives the real `Miku` node of the animator.
##
## API used by the router:
##   perform(action, args)            — one vocabulary action; must end with action_finished(action)
##   notice_user()                    — perception: the user called her (immediate, no plan step)
##   target_world(id)                 — perception: the user pointed at world `id`
##   apply_config(values)             — whole configuration (at bind time)
##   config_changed(path, old, new)   — one property really changed (after the store applied it)

signal action_finished(action: StringName)

## When true, perform() emits action_finished synchronously (the null executor's default).
var auto_finish := true
## Every call received, in order: [method, ...args] (e.g. [&"perform", &"THINK", {...}]).
var calls: Array = []
## Action performed and not finished yet (manual mode), or &"".
var pending: StringName = &""


## True when a real body performs the actions (false for the null executor).
func is_bound() -> bool:
	return false


func perform(action: StringName, args: Dictionary = {}) -> void:
	calls.append([&"perform", action, args])
	pending = action
	if auto_finish:
		finish()


## Ends the pending action (manual mode; also used by auto_finish).
func finish() -> void:
	if pending == &"":
		return
	var a := pending
	pending = &""
	action_finished.emit(a)


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
