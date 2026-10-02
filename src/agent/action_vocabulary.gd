class_name ActionVocabulary
extends RefCounted
## The closed vocabulary of MIKU's actions (Loop 5, ADR-016). Pure data + validation.
##
## Everything that asks MIKU to *do* something — the local parser, a future provider (through
## ProviderPort), the interaction router — speaks only these 16 actions with validated
## arguments. How an action is performed (bones, hands, threads, camera) is decided by MIKU's
## runtime (animator, `Miku.perform(action, args)`); nothing outside it touches her body.
##
## An action step is a Dictionary {"action": StringName, "args": Dictionary}; a plan is an
## Array of steps, executed in order (InteractionRouter).

const LOOK_AT_USER := &"LOOK_AT_USER"
const LOOK_AT_WORLD := &"LOOK_AT_WORLD"
const ACKNOWLEDGE := &"ACKNOWLEDGE"
const THINK := &"THINK"
const WORK := &"WORK"
const INSPECT := &"INSPECT"
const SUMMON_HAND := &"SUMMON_HAND"
const SUMMON_HANDS := &"SUMMON_HANDS"
const GRAB_FILE := &"GRAB_FILE"
const EDIT_FILE := &"EDIT_FILE"
const POINT := &"POINT"
const DISCARD := &"DISCARD"
const FRUSTRATED := &"FRUSTRATED"
const ANGRY := &"ANGRY"
const RECOVER := &"RECOVER"
const SATISFIED := &"SATISFIED"

## Every action, in contract order (docs/contracts/loop-05.md).
const ALL: Array[StringName] = [
	LOOK_AT_USER, LOOK_AT_WORLD, ACKNOWLEDGE, THINK, WORK, INSPECT, SUMMON_HAND, SUMMON_HANDS,
	GRAB_FILE, EDIT_FILE, POINT, DISCARD, FRUSTRATED, ANGRY, RECOVER, SATISFIED,
]

## Tones of ACKNOWLEDGE ("decline" = the graceful "not now" of a refused request).
const TONES: Array[String] = ["warm", "brief", "curious", "decline", "puzzled"]
## Sides of a summoned hand.
const SIDES: Array[String] = ["left", "right"]
## Upper bound of hands in one SUMMON_HANDS (a sanity limit for validation, not a design limit:
## the pool itself has none).
const MAX_HANDS := 16

## Argument specs per action: arg name -> {"type": Variant.Type, "required": bool,
## optional "min"/"max" (numbers), "values" (allowed strings), "any": true (any type)}.
## STRING args also accept StringName and vice versa (both are text). Unknown arg names are
## rejected (a provider cannot smuggle extra fields through).
const ARGS := {
	LOOK_AT_USER: {},
	LOOK_AT_WORLD: {"world": {"type": TYPE_STRING_NAME, "required": true}},
	ACKNOWLEDGE: {
		"tone": {"type": TYPE_STRING, "required": false, "values": TONES},
		"reason": {"type": TYPE_STRING, "required": false},
	},
	THINK: {"seconds": {"type": TYPE_FLOAT, "required": false, "min": 0.0, "max": 10.0}},
	WORK: {
		"world": {"type": TYPE_STRING_NAME, "required": false},
		"resume": {"type": TYPE_BOOL, "required": false},
	},
	INSPECT: {
		"target": {"type": TYPE_STRING, "required": false},
		"path": {"type": TYPE_STRING, "required": false},
	},
	SUMMON_HAND: {
		"side": {"type": TYPE_STRING, "required": false, "values": SIDES},
		"role": {"type": TYPE_STRING, "required": false},
	},
	SUMMON_HANDS: {
		"count": {"type": TYPE_INT, "required": true, "min": 1, "max": MAX_HANDS},
		"world": {"type": TYPE_STRING_NAME, "required": false},
	},
	GRAB_FILE: {"file": {"type": TYPE_STRING, "required": true}},
	EDIT_FILE: {
		"file": {"type": TYPE_STRING, "required": true},
		"path": {"type": TYPE_STRING, "required": true},
		"value": {"any": true, "required": true},
		"old_value": {"any": true, "required": false},
	},
	POINT: {"target": {"type": TYPE_STRING, "required": true}},
	DISCARD: {
		"file": {"type": TYPE_STRING, "required": false},
		"applied": {"type": TYPE_BOOL, "required": false},
	},
	FRUSTRATED: {"intensity": {"type": TYPE_FLOAT, "required": false, "min": 0.0, "max": 1.0}},
	ANGRY: {"intensity": {"type": TYPE_FLOAT, "required": false, "min": 0.0, "max": 1.0}},
	RECOVER: {},
	SATISFIED: {"intensity": {"type": TYPE_FLOAT, "required": false, "min": 0.0, "max": 1.0}},
}


## Correlation keys the InteractionRouter adds to the args of every dispatched action
## (docs/contracts/loop-05-round2.md): `request_id` (int > 0) and `step` (index in the plan). They
## are not vocabulary arguments — validate() rejects them, so a provider cannot forge them.
const CORRELATION_ARGS: Array[String] = ["request_id", "step"]

## Nominal real-time duration (seconds) of each action on MIKU's body at tempo 1 — the end beat of
## the animator's ActionScript plus a typical wait. Used ONLY when the executor gives no
## estimate (legacy body without Miku.estimate_duration); the body's own estimate always wins.
const NOMINAL_SECONDS := {
	LOOK_AT_USER: 2.5, LOOK_AT_WORLD: 2.7, ACKNOWLEDGE: 1.5, THINK: 3.1, WORK: 1.0, INSPECT: 3.0,
	SUMMON_HAND: 1.8, SUMMON_HANDS: 4.4, GRAB_FILE: 2.8, EDIT_FILE: 2.0, POINT: 2.6, DISCARD: 1.6,
	FRUSTRATED: 3.1, ANGRY: 2.6, RECOVER: 5.0, SATISFIED: 2.8,
}


## Nominal duration of `action` with `args` (see NOMINAL_SECONDS); THINK follows its `seconds`.
static func nominal_duration(action: Variant, args: Dictionary = {}) -> float:
	var a := StringName(str(action))
	if a == THINK and args.has("seconds"):
		return 3.1 * clampf(float(args["seconds"]) / 3.0, 0.35, 3.0)
	return float(NOMINAL_SECONDS.get(a, 3.0))


static func is_valid(action: Variant) -> bool:
	return (action is StringName or action is String) and ALL.has(StringName(action))


## Errors of one action call (empty = valid): unknown action, unknown arg, missing required arg,
## wrong type, value out of range or not among the allowed values.
static func validate(action: Variant, args: Dictionary = {}) -> PackedStringArray:
	var errors := PackedStringArray()
	if not is_valid(action):
		errors.append("unknown action %s" % str(action))
		return errors
	var spec: Dictionary = ARGS[StringName(action)]
	for key: Variant in args:
		if not (key is String or key is StringName) or not spec.has(String(key)):
			errors.append("%s: unknown argument %s" % [action, str(key)])
	for name: String in spec:
		var rule: Dictionary = spec[name]
		if not args.has(name) and not args.has(StringName(name)):
			if bool(rule.get("required", false)):
				errors.append("%s: missing argument %s" % [action, name])
			continue
		var value: Variant = args.get(name, args.get(StringName(name)))
		var err := _check_value(rule, value)
		if err != "":
			errors.append("%s.%s: %s" % [action, name, err])
	return errors


## A plan step {"action", "args"} (args already normalized: StringName/String coerced to the
## spec's type, ints accepted for floats), or {} when the call is invalid.
static func step(action: Variant, args: Dictionary = {}) -> Dictionary:
	if not validate(action, args).is_empty():
		return {}
	var spec: Dictionary = ARGS[StringName(action)]
	var out := {}
	for key: Variant in args:
		var name := String(key)
		var rule: Dictionary = spec[name]
		out[name] = _coerce(rule, args[key])
	return {"action": StringName(action), "args": out}


## Errors of a whole plan (an Array of {"action", "args"} steps); empty = valid. Each error is
## prefixed with the step index.
static func validate_plan(plan: Variant) -> PackedStringArray:
	var errors := PackedStringArray()
	if not plan is Array:
		errors.append("plan is not an array")
		return errors
	var i := 0
	for s: Variant in plan:
		if not s is Dictionary or not (s as Dictionary).has("action"):
			errors.append("#%d: not an action step" % i)
		else:
			var d := s as Dictionary
			var a: Variant = d.get("args", {})
			if not a is Dictionary:
				errors.append("#%d: args is not a dictionary" % i)
			else:
				for e in validate(d["action"], a):
					errors.append("#%d: %s" % [i, e])
		i += 1
	return errors


## Action names of a plan, in order (for logs and tests).
static func names(plan: Array) -> Array[StringName]:
	var out: Array[StringName] = []
	for s: Dictionary in plan:
		out.append(StringName(s.get("action", &"")))
	return out


static func _check_value(rule: Dictionary, value: Variant) -> String:
	if bool(rule.get("any", false)):
		return "" if value != null else "null value"
	var t: int = int(rule.get("type", TYPE_NIL))
	match t:
		TYPE_STRING, TYPE_STRING_NAME:
			if not (value is String or value is StringName):
				return "expected text, got %s" % type_string(typeof(value))
			if String(value).strip_edges() == "" and bool(rule.get("required", false)):
				return "empty text"
			if rule.has("values") and not (rule["values"] as Array).has(String(value)):
				return "%s not in %s" % [value, rule["values"]]
		TYPE_BOOL:
			if not value is bool:
				return "expected bool, got %s" % type_string(typeof(value))
		TYPE_INT:
			# JSON numbers arrive as floats: integral floats are accepted.
			if not (value is int or (value is float and is_equal_approx(value, roundf(value)))):
				return "expected int, got %s" % str(value)
			if not _in_range(rule, float(value)):
				return "%s out of [%s, %s]" % [value, rule.get("min"), rule.get("max")]
		TYPE_FLOAT:
			if not (value is float or value is int):
				return "expected number, got %s" % type_string(typeof(value))
			if is_nan(float(value)) or is_inf(float(value)):
				return "not a finite number"
			if not _in_range(rule, float(value)):
				return "%s out of [%s, %s]" % [value, rule.get("min"), rule.get("max")]
	return ""


static func _in_range(rule: Dictionary, v: float) -> bool:
	if rule.has("min") and v < float(rule["min"]):
		return false
	if rule.has("max") and v > float(rule["max"]):
		return false
	return true


static func _coerce(rule: Dictionary, value: Variant) -> Variant:
	if bool(rule.get("any", false)):
		return value
	match int(rule.get("type", TYPE_NIL)):
		TYPE_STRING:
			return String(value)
		TYPE_STRING_NAME:
			return StringName(value)
		TYPE_INT:
			return int(value)
		TYPE_FLOAT:
			return float(value)
	return value
