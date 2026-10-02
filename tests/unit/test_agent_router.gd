extends GutTest
## InteractionRouter (Loop 5): USER -> INTENT -> LOCAL|PROVIDER -> PATCH -> VALIDATION -> MUTATION,
## plans of vocabulary actions run by the null executor, the unbound ProviderPort and a test-only
## provider that goes through the same validation path. Config store in a temporary directory.

const TMP_DIR := "user://_test_agent_router"
const V := preload("res://src/agent/action_vocabulary.gd")


## Test-only provider (never part of the game): answers a canned response.
class FakeProvider:
	extends ProviderPort
	var response: Dictionary = {}
	var asked: Array = []

	func is_available() -> bool:
		return true

	func request(intent: Intent, context: Dictionary) -> Dictionary:
		asked.append([intent, context])
		return response


var config: MikuConfig
var executor: ActionExecutor
var router: InteractionRouter
var reports: Array[Dictionary]


func before_each() -> void:
	_clean()
	config = MikuConfig.new(MikuConfig.DEFAULT_PATH, TMP_DIR.path_join(ConfigSchema.FILE))
	config.reload()
	executor = ActionExecutor.new()
	router = InteractionRouter.new(config, executor)
	router.worlds = LivingScript.world_directory()
	reports = []
	router.request_finished.connect(func(r: Dictionary) -> void: reports.append(r))


func after_each() -> void:
	_clean()


func _clean() -> void:
	var p := TMP_DIR.path_join(ConfigSchema.FILE)
	for f in [p, p + MikuConfig.TEMP_SUFFIX]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(TMP_DIR)):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP_DIR))


func test_defaults_are_null_executor_and_unbound_port() -> void:
	var r := InteractionRouter.new()
	assert_false(r.executor.is_bound(), "null executor")
	assert_false(r.port.is_available(), "no provider in this project")
	assert_eq(r.port.request(Intent.make(Intent.Kind.SEMANTIC, "x"), {}), {"ok": false, "reason": ProviderPort.UNAVAILABLE})
	assert_true(r.port.describe().contains("not accessed"))


func test_attention_text_and_click() -> void:
	router.submit_text("Miku!")
	assert_eq(reports.size(), 1)
	assert_eq(reports[0]["kind"], "ATTENTION")
	assert_eq(reports[0]["route"], "LOCAL")
	assert_eq(reports[0]["status"], InteractionRouter.ST_ATTENTION)
	assert_eq(executor.calls[0], [&"notice_user"], "perception first")
	assert_eq(executor.performed(), [V.LOOK_AT_USER, V.ACKNOWLEDGE, V.WORK] as Array[StringName])
	router.call_attention()
	assert_eq(reports[1]["source"], &"click")
	assert_false(router.busy())


func test_world_target() -> void:
	router.submit_text("Miku, trabalhe no planeta da esquerda")
	assert_eq(reports[0]["status"], InteractionRouter.ST_WORLD)
	assert_eq(reports[0]["target"], &"world_vesper")
	assert_has(executor.calls, [&"target_world", &"world_vesper"])
	assert_eq(executor.performed(), [V.LOOK_AT_WORLD, V.POINT, V.SUMMON_HANDS, V.WORK] as Array[StringName])
	var work: Array = executor.calls.filter(func(c: Array) -> bool: return c[0] == &"perform" and c[1] == V.WORK)
	assert_eq(work[0][2]["world"], &"world_vesper")
	router.indicate_world(&"world_nowhere")
	assert_eq(reports[1]["status"], InteractionRouter.ST_UNKNOWN, "unknown world: puzzled")
	assert_false(executor.calls.has([&"target_world", &"world_nowhere"]))


func test_snapshot_reports_the_action_in_flight_read_only() -> void:
	var idle := router.snapshot()
	assert_eq(idle["action"], "")
	assert_eq(idle["plan"], [])
	assert_eq(idle["requests_finished"], 0)
	assert_false(idle["provider_available"])
	executor.auto_finish = false
	router.submit_text("Miku, aumente sua altura")
	executor.finish()  # LOOK_AT_USER -> ACKNOWLEDGE
	var s := router.snapshot()
	assert_eq(s["action"], String(V.ACKNOWLEDGE))
	assert_eq(s["step_index"], 1)
	assert_eq(s["plan"][0], V.LOOK_AT_USER)
	assert_true(s["waiting"])
	assert_eq(s["executor_pending"], String(V.ACKNOWLEDGE))
	assert_eq(s["active_request"]["kind"], "CONFIG_PATCH")
	# A copy: editing it changes nothing in the router.
	(s["active_request"] as Dictionary)["kind"] = "X"
	(s["plan"] as Array).clear()
	assert_eq(router.snapshot()["active_request"]["kind"], "CONFIG_PATCH")
	assert_eq((router.snapshot()["plan"] as Array).size(), 10)
	while router.busy():
		executor.finish()
	var done := router.snapshot()
	assert_eq(done["action"], "")
	assert_eq(done["requests_finished"], 1)
	assert_eq(done["last_report"]["status"], InteractionRouter.ST_APPLIED)


func test_local_config_route_mutates_after_edit_file() -> void:
	var mutations: Array = []
	router.mutation_applied.connect(func(p: String, o: Variant, n: Variant) -> void: mutations.append([p, o, n]))
	executor.auto_finish = false
	router.submit_text("Miku, aumente sua altura")
	var expected := [V.LOOK_AT_USER, V.ACKNOWLEDGE, V.SUMMON_HAND, V.GRAB_FILE, V.SUMMON_HAND, V.EDIT_FILE,
		V.INSPECT, V.SATISFIED, V.DISCARD, V.WORK]
	# Step through: nothing changes before EDIT_FILE has finished.
	for i in 6:
		assert_eq(router.current_step()["action"], expected[i])
		assert_eq(config.get_value("appearance.height"), 1.0, "not applied before the edit ends (step %d)" % i)
		executor.finish()
	assert_almost_eq(float(config.get_value("appearance.height")), 1.03, 1e-6, "applied when the hand finished editing")
	assert_eq(mutations.size(), 1)
	assert_eq(mutations[0][0], "appearance.height")
	assert_has(executor.calls, [&"config_changed", "appearance.height", 1.0, 1.03])
	while router.busy():
		executor.finish()
	assert_eq(executor.performed(), expected as Array[StringName])
	var edit: Array = executor.calls.filter(func(c: Array) -> bool: return c[0] == &"perform" and c[1] == V.EDIT_FILE)
	assert_eq(edit[0][2], {"file": ConfigSchema.FILE, "path": "appearance.height", "value": 1.03, "old_value": 1.0})
	var r := reports[0]
	assert_eq(r["kind"], "CONFIG_PATCH")
	assert_eq(r["route"], "LOCAL")
	assert_eq(r["status"], InteractionRouter.ST_APPLIED)
	assert_eq(r["path"], "appearance.height")
	assert_eq(r["old_value"], 1.0)
	assert_almost_eq(float(r["new_value"]), 1.03, 1e-6)
	assert_true(FileAccess.file_exists(config.user_path), "persisted")


func test_structured_commands_and_clamps() -> void:
	router.submit_text("appearance.height 1.04")
	assert_almost_eq(float(config.get_value("appearance.height")), 1.04, 1e-6)
	router.submit_text("chest_volume 0.52")
	assert_almost_eq(float(config.get_value("appearance.chest_volume")), 0.52, 1e-6)
	router.submit_text("set behaviour.patience 0.7")
	assert_eq(reports[2]["path"], "identity.patience")
	assert_true(String(reports[2]["notes"][0]).contains("belongs to identity"))
	assert_almost_eq(float(config.get_value("identity.patience")), 0.7, 1e-6)
	router.submit_text("appearance.height 3")
	assert_eq(reports[3]["status"], InteractionRouter.ST_APPLIED)
	assert_almost_eq(float(config.get_value("appearance.height")), 1.1, 1e-6, "clamped")
	assert_true(String(reports[3]["notes"][0]).contains("clamped"))
	router.submit_text("Miku, aumente sua altura")
	assert_eq(reports[4]["status"], InteractionRouter.ST_UNCHANGED, "already at the maximum")
	assert_false(executor.performed().slice(-8).has(V.EDIT_FILE))
	assert_eq(executor.performed().back(), V.WORK)


func test_requires_asset_and_rejected_are_refused() -> void:
	router.submit_text("Miku, me dê asas")
	assert_eq(reports[0]["status"], InteractionRouter.ST_REQUIRES_ASSET)
	assert_eq(reports[0]["route"], "LOCAL")
	assert_eq(reports[0]["plan"], [V.LOOK_AT_USER, V.THINK, V.INSPECT, V.ACKNOWLEDGE, V.WORK])
	router.submit_text("appearance.glow 0.x")
	router.submit_text("appearance.sparkle 1")
	assert_eq(reports[1]["status"], InteractionRouter.ST_REJECTED)
	assert_eq(reports[2]["status"], InteractionRouter.ST_REJECTED)
	assert_false(executor.performed().has(V.EDIT_FILE))
	assert_false(config.has_user_file(), "nothing written")
	assert_eq(config.values(), config.defaults())


func test_semantic_without_provider_declines_gracefully() -> void:
	router.submit_text("Miku, fique mais curiosa, mas menos impulsiva")
	var r := reports[0]
	assert_eq(r["kind"], "SEMANTIC")
	assert_eq(r["route"], "PROVIDER")
	assert_eq(r["status"], InteractionRouter.ST_PROVIDER_UNAVAILABLE)
	assert_eq(r["reason"], ProviderPort.UNAVAILABLE)
	assert_eq(r["plan"], [V.LOOK_AT_USER, V.THINK, V.ACKNOWLEDGE, V.WORK])
	var ack: Array = executor.calls.filter(func(c: Array) -> bool: return c[0] == &"perform" and c[1] == V.ACKNOWLEDGE)
	assert_eq(ack[0][2], {"tone": "decline", "reason": ProviderPort.UNAVAILABLE})
	assert_eq(config.values(), config.defaults(), "nothing applied")


func test_unknown_is_puzzled() -> void:
	router.submit_text("   ")
	assert_eq(reports[0]["kind"], "UNKNOWN")
	assert_eq(reports[0]["status"], InteractionRouter.ST_UNKNOWN)
	assert_eq(reports[0]["plan"], [V.LOOK_AT_USER, V.THINK, V.ACKNOWLEDGE, V.WORK])


func test_provider_response_goes_through_the_same_validation() -> void:
	var fake := FakeProvider.new()
	router.port = fake
	fake.response = {"ok": true, "actions": [{"action": "THINK", "args": {"seconds": 1.0}}, {"action": "LOOK_AT_USER"}],
		"mutation": {"file": "miku.config.json", "path": "identity.curiosity", "value": 0.85}}
	router.submit_text("Miku, fique mais curiosa")
	assert_eq(fake.asked.size(), 1)
	assert_true((fake.asked[0][1] as Dictionary).has("config"), "context carries the config")
	var r := reports[0]
	assert_eq(r["route"], "PROVIDER")
	assert_eq(r["status"], InteractionRouter.ST_APPLIED)
	assert_almost_eq(float(config.get_value("identity.curiosity")), 0.85, 1e-6)
	assert_eq(r["plan"].slice(0, 2), [V.THINK, V.LOOK_AT_USER], "provider actions first")
	assert_has(r["plan"], V.EDIT_FILE, "the edit is always shown")
	# Out of range -> clamped by the same validator.
	fake.response = {"ok": true, "actions": [], "mutation": {"path": "appearance.glow", "value": 7}}
	router.submit_text("Miku, brilhe como o sol, mas suave")
	assert_almost_eq(float(config.get_value("appearance.glow")), 1.0, 1e-6)
	# Provider placing its own EDIT_FILE: the validated value replaces its args.
	fake.response = {"ok": true, "actions": [{"action": "GRAB_FILE", "args": {"file": "miku.config.json"}},
		{"action": "EDIT_FILE", "args": {"file": "miku.config.json", "path": "appearance.glow", "value": 99}}],
		"mutation": {"path": "appearance.glow", "value": 0.2}}
	router.submit_text("Miku, menos brilho, por favor, mas não muito")
	assert_almost_eq(float(config.get_value("appearance.glow")), 0.2, 1e-6)
	var edits: Array = executor.calls.filter(func(c: Array) -> bool: return c[0] == &"perform" and c[1] == V.EDIT_FILE)
	assert_eq(edits.back()[2]["value"], 0.2)


func test_invalid_provider_responses_are_refused_whole() -> void:
	var fake := FakeProvider.new()
	router.port = fake
	var bad := [
		{"ok": true, "actions": [{"action": "SET_BONE", "args": {"bone": "spine"}}]},
		{"ok": true, "actions": [{"action": "THINK", "args": {"transform": "x"}}]},
		{"ok": true, "actions": [], "mutation": {"value": 1}},
		{"ok": true, "actions": [], "exec": "rm -rf"},
		{"ok": true, "actions": "THINK"},
	]
	for resp in bad:
		fake.response = resp
		router.submit_text("Miku, fique mais curiosa, mas calma")
	for r in reports:
		assert_eq(r["status"], InteractionRouter.ST_PROVIDER_INVALID, str(r))
	assert_eq(config.values(), config.defaults())
	fake.response = {"ok": true, "actions": [], "mutation": {"path": "appearance.wings", "value": 1}}
	router.submit_text("Miku, asas, mas pequenas")
	assert_eq(reports.back()["status"], InteractionRouter.ST_REQUIRES_ASSET)
	fake.response = {"ok": false, "reason": "provider_unavailable"}
	router.submit_text("Miku, conte algo")
	assert_eq(reports.back()["status"], InteractionRouter.ST_PROVIDER_UNAVAILABLE)


func test_queue_timeout_and_cancel() -> void:
	executor.auto_finish = false
	router.submit_text("Miku!")
	router.submit_text("Miku, aumente sua altura")
	assert_true(router.busy())
	assert_eq(reports.size(), 0)
	# The body never answers: each step is skipped after STEP_TIMEOUT.
	for i in 3:
		router.tick(InteractionRouter.STEP_TIMEOUT + 0.1)
	assert_eq(reports.size(), 1, "attention plan ended by timeouts")
	assert_eq(router.current_step()["action"], V.LOOK_AT_USER, "next request started")
	router.cancel()
	assert_false(router.busy())
	assert_eq(reports.back()["status"], InteractionRouter.ST_CANCELLED)
	assert_eq(config.get_value("appearance.height"), 1.0, "cancelled before the edit: nothing applied")
	# Queue limit.
	for i in InteractionRouter.MAX_QUEUE + 3:
		router.submit_text("Miku!")
	var cancelled := reports.filter(func(r: Dictionary) -> bool: return r["status"] == InteractionRouter.ST_CANCELLED)
	assert_eq(cancelled.size(), 1 + 2, "oldest waiting requests dropped beyond MAX_QUEUE")
	router.cancel()


func test_commit_revalidates_against_the_current_config() -> void:
	executor.auto_finish = false
	router.submit_text("appearance.glow 0.9")
	for i in 5:
		executor.finish()
	assert_eq(router.current_step()["action"], V.EDIT_FILE)
	# Meanwhile something else set the same value: the commit finds nothing to change.
	config.apply(ConfigValidator.validate(StructuredPatch.absolute("appearance.glow", 0.9), config.values()))
	executor.finish()
	while router.busy():
		executor.finish()
	assert_eq(reports[0]["status"], InteractionRouter.ST_UNCHANGED)
	assert_false(executor.performed().has(V.SATISFIED), "no satisfaction for a change that did not happen")
	assert_eq(executor.performed().slice(-2), [V.DISCARD, V.WORK] as Array[StringName])


func test_node_executor_forwards_and_degrades() -> void:
	var body := _FakeMiku.new()
	add_child_autofree(body)
	var e := MikuNodeExecutor.new(body)
	assert_true(e.is_bound())
	router.set_executor(e)
	e.apply_config(config.values())
	assert_eq(body.calls_log[0][0], &"apply_config")
	router.submit_text("Miku, trabalhe no planeta da direita")
	assert_eq(body.calls_log[1], [&"target_world", &"world_orrin"])
	assert_eq(router.current_step()["action"], V.LOOK_AT_WORLD, "waits for the body")
	body.finish_current()
	assert_eq(router.current_step()["action"], V.POINT)
	body.finish_current()
	body.finish_current()
	body.finish_current()
	assert_false(router.busy())
	assert_eq(reports[0]["status"], InteractionRouter.ST_WORLD)
	# A node without perform(): null behaviour, one warning.
	var empty := Node.new()
	add_child_autofree(empty)
	var n := MikuNodeExecutor.new(empty)
	assert_false(n.is_bound())
	router.set_executor(n)
	router.submit_text("Miku!")
	assert_false(router.busy(), "finished at once")


## Minimal stand-in for the animator's Miku node (perform + action_finished).
class _FakeMiku:
	extends Node
	signal action_finished(action: StringName)
	var calls_log: Array = []
	var current: StringName = &""

	func perform(action: StringName, args: Dictionary = {}) -> void:
		calls_log.append([&"perform", action, args])
		current = action

	func notice_user() -> void:
		calls_log.append([&"notice_user"])

	func target_world(id: StringName) -> void:
		calls_log.append([&"target_world", id])

	func apply_config(values: Dictionary) -> void:
		calls_log.append([&"apply_config", values])

	func finish_current() -> void:
		var a := current
		current = &""
		action_finished.emit(a)
