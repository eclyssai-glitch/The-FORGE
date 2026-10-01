extends GutTest
## ActionVocabulary (Loop 5): the 16 actions of the contract and argument validation.


func test_sixteen_actions_of_the_contract() -> void:
	var expected: Array[StringName] = [&"LOOK_AT_USER", &"LOOK_AT_WORLD", &"ACKNOWLEDGE", &"THINK", &"WORK",
		&"INSPECT", &"SUMMON_HAND", &"SUMMON_HANDS", &"GRAB_FILE", &"EDIT_FILE", &"POINT", &"DISCARD",
		&"FRUSTRATED", &"ANGRY", &"RECOVER", &"SATISFIED"]
	assert_eq(ActionVocabulary.ALL, expected)
	for a in ActionVocabulary.ALL:
		assert_true(ActionVocabulary.ARGS.has(a), "%s has an argument spec" % a)
		assert_true(ActionVocabulary.is_valid(a))
		assert_true(ActionVocabulary.is_valid(String(a)), "text names are accepted")
	assert_eq(ActionVocabulary.ARGS.size(), 16)
	assert_false(ActionVocabulary.is_valid(&"DANCE"))
	assert_false(ActionVocabulary.is_valid(3))


func test_valid_calls() -> void:
	assert_eq(ActionVocabulary.validate(&"LOOK_AT_USER").size(), 0)
	assert_eq(ActionVocabulary.validate(&"LOOK_AT_WORLD", {"world": &"world_vesper"}).size(), 0)
	assert_eq(ActionVocabulary.validate(&"LOOK_AT_WORLD", {"world": "world_vesper"}).size(), 0, "String for StringName")
	assert_eq(ActionVocabulary.validate(&"SUMMON_HANDS", {"count": 4}).size(), 0)
	assert_eq(ActionVocabulary.validate(&"SUMMON_HANDS", {"count": 4.0}).size(), 0, "integral JSON float")
	assert_eq(ActionVocabulary.validate(&"EDIT_FILE", {"file": "miku.config.json", "path": "appearance.height",
		"value": 1.03}).size(), 0)
	assert_eq(ActionVocabulary.validate(&"ACKNOWLEDGE", {"tone": "decline", "reason": "x"}).size(), 0)
	assert_eq(ActionVocabulary.validate(&"THINK", {"seconds": 2}).size(), 0, "int for float")


func test_invalid_calls() -> void:
	assert_gt(ActionVocabulary.validate(&"DANCE").size(), 0, "unknown action")
	assert_gt(ActionVocabulary.validate(&"LOOK_AT_WORLD").size(), 0, "missing required")
	assert_gt(ActionVocabulary.validate(&"LOOK_AT_WORLD", {"world": 3}).size(), 0, "wrong type")
	assert_gt(ActionVocabulary.validate(&"LOOK_AT_WORLD", {"world": "  "}).size(), 0, "empty text")
	assert_gt(ActionVocabulary.validate(&"SUMMON_HANDS", {"count": 0}).size(), 0, "below range")
	assert_gt(ActionVocabulary.validate(&"SUMMON_HANDS", {"count": 2.5}).size(), 0, "not integral")
	assert_gt(ActionVocabulary.validate(&"SUMMON_HANDS", {"count": 99}).size(), 0, "above range")
	assert_gt(ActionVocabulary.validate(&"ACKNOWLEDGE", {"tone": "sarcastic"}).size(), 0, "not an allowed value")
	assert_gt(ActionVocabulary.validate(&"THINK", {"seconds": NAN}).size(), 0, "nan")
	assert_gt(ActionVocabulary.validate(&"RECOVER", {"bone": "spine"}).size(), 0, "no smuggled arguments")
	assert_gt(ActionVocabulary.validate(&"EDIT_FILE", {"file": "x", "path": "y"}).size(), 0, "value required")
	assert_gt(ActionVocabulary.validate(&"WORK", {"resume": "yes"}).size(), 0, "bool expected")


func test_step_normalizes_and_rejects() -> void:
	var s := ActionVocabulary.step(&"SUMMON_HANDS", {"count": 3.0, "world": "world_orrin"})
	assert_eq(s["action"], &"SUMMON_HANDS")
	assert_typeof(s["args"]["count"], TYPE_INT)
	assert_typeof(s["args"]["world"], TYPE_STRING_NAME)
	assert_eq(ActionVocabulary.step(&"SUMMON_HANDS", {}), {})
	assert_eq(ActionVocabulary.step("THINK")["action"], &"THINK")


func test_validate_plan() -> void:
	var plan := [ActionVocabulary.step(&"LOOK_AT_USER"), ActionVocabulary.step(&"THINK", {"seconds": 1.0})]
	assert_eq(ActionVocabulary.validate_plan(plan).size(), 0)
	assert_eq(ActionVocabulary.names(plan), [&"LOOK_AT_USER", &"THINK"] as Array[StringName])
	assert_gt(ActionVocabulary.validate_plan("nope").size(), 0)
	var bad := ActionVocabulary.validate_plan([{"action": &"THINK"}, {"action": &"FLY"}, 3, {"action": &"POINT", "args": []}])
	assert_eq(bad.size(), 3)
	assert_true(bad[0].begins_with("#1"), bad[0])
	assert_true(bad[1].begins_with("#2"), bad[1])
	assert_true(bad[2].begins_with("#3"), bad[2])
