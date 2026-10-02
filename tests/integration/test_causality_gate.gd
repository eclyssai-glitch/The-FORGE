extends GutTest
## Causality gate (docs/BUILD.md, "Gate de causalidade"; docs/contracts/loop-05-round2.md):
## tools/inspector/causality.py checks MIKU's causal timelines in dev inspector dumps. Here:
## its own Python tests (tools/inspector/test_causality.py, fixtures in
## tools/inspector/testdata/causality) run through OS.execute("python3", ...), and a real dev
## inspector dump of a node that publishes a timeline through inspect_state() is read by the checker
## (the JSON the inspector writes is the format the checker expects). Without python3 on PATH the
## tests are pending (the gate is a development tool; tools/ never ships).

const AutomationScript := preload("res://src/core/automation.gd")
const CHECKER := "res://tools/inspector/causality.py"
const PY_TESTS := "res://tools/inspector/test_causality.py"
const TMP_DIR := "user://_test_causality_gate"


## A MIKU stand-in: section "miku" with clock + causality in the contract's shape (StringName
## actions, StringName keys in `t`, like Miku.causality()).
class FakeMiku:
	extends Node
	var timeline: Array = []
	var clock := 0.0

	func _ready() -> void:
		add_to_group(&"dev_inspect")

	func inspect_section() -> String:
		return "miku"

	func inspect_state() -> Dictionary:
		return {"mood": &"calm", "clock": clock, "causality": timeline}


var inspector: Node
var fake: FakeMiku


func after_each() -> void:
	if is_instance_valid(fake):
		fake.free()
	if is_instance_valid(inspector):
		inspector.free()
	var abs_dir := ProjectSettings.globalize_path(TMP_DIR)
	if DirAccess.dir_exists_absolute(abs_dir):
		for f in DirAccess.get_files_at(abs_dir):
			DirAccess.remove_absolute(abs_dir.path_join(f))
		DirAccess.remove_absolute(abs_dir)


func _python() -> bool:
	var out: Array = []
	return OS.execute("python3", PackedStringArray(["--version"]), out, true) == 0


func _run(script: String, args: Array) -> Dictionary:
	var argv := PackedStringArray([ProjectSettings.globalize_path(script)])
	for a: Variant in args:
		argv.append(String(a))
	var out: Array = []
	var code := OS.execute("python3", argv, out, true)
	return {"code": code, "out": "".join(PackedStringArray(out))}


func test_python_tests_of_the_checker_pass() -> void:
	if not _python():
		pending("python3 not on PATH: run `python3 tools/inspector/test_causality.py` by hand")
		return
	var r := _run(PY_TESTS, [])
	assert_eq(int(r["code"]), 0, "tools/inspector/test_causality.py:\n%s" % r["out"])
	assert_string_contains(String(r["out"]), "OK")


func test_checker_reads_real_inspector_dumps() -> void:
	if not _python():
		pending("python3 not on PATH")
		return
	fake = FakeMiku.new()
	add_child(fake)
	inspector = AutomationScript.load_inspector({"inspect": TMP_DIR, "inspect-png": "off"})
	add_child(inspector)
	# Dump 1: a summon under way; dump 2: it finished, plus a task stage of the work.
	fake.clock = 5.0
	fake.timeline = [{"request_id": 2, "step": 1, "action": &"SUMMON_HANDS", "channel": "main", "stage": "",
		"phase": "", "t": {&"intent": 1.0, &"anticipation": 1.0, &"gesture": 1.5}}]
	inspector.call(&"dump", ProjectSettings.globalize_path(TMP_DIR).path_join("inspect_0001"), {"trigger": "test"})
	await wait_process_frames(2)
	fake.clock = 12.0
	fake.timeline = [{"request_id": 2, "step": 1, "action": &"SUMMON_HANDS", "channel": "main", "stage": "",
			"phase": "finished", "t": {&"intent": 1.0, &"anticipation": 1.0, &"gesture": 1.5, &"thread": 1.62,
			&"hand": 2.2, &"result": 5.4}},
		{"request_id": 2, "step": 3, "action": &"WORK", "channel": "task", "stage": "CORE", "phase": "finished",
			"t": {&"intent": 6.0, &"anticipation": 6.0, &"gesture": 6.1, &"thread": 6.4, &"hand": 6.9,
			&"matter": 7.3, &"result": 11.0}}]
	inspector.call(&"dump", ProjectSettings.globalize_path(TMP_DIR).path_join("inspect_0002"), {"trigger": "test"})
	var r := _run(CHECKER, [ProjectSettings.globalize_path(TMP_DIR), "--require"])
	assert_eq(int(r["code"]), 0, String(r["out"]))
	assert_string_contains(String(r["out"]), "causality=PASS 2/2")
	assert_string_contains(String(r["out"]), "2/2 finished big actions")
	# A broken order in the next dump makes the gate fail (exit 1) with the reason.
	fake.clock = 20.0
	fake.timeline.append({"request_id": 0, "step": 0, "action": &"POINT", "channel": "main", "stage": "",
		"phase": "finished", "t": {&"intent": 13.0, &"anticipation": 13.4, &"gesture": 13.2, &"result": 15.0}})
	inspector.call(&"dump", ProjectSettings.globalize_path(TMP_DIR).path_join("inspect_0003"), {"trigger": "test"})
	r = _run(CHECKER, [ProjectSettings.globalize_path(TMP_DIR)])
	assert_eq(int(r["code"]), 1, String(r["out"]))
	assert_string_contains(String(r["out"]), "gesture 13.200 before anticipation 13.400")
	assert_string_contains(String(r["out"]), "causality=FAIL 2/3")
