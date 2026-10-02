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
var started: Array[Dictionary]


func before_each() -> void:
	_clean()
	config = MikuConfig.new(MikuConfig.DEFAULT_PATH, TMP_DIR.path_join(ConfigSchema.FILE))
	config.reload()
	executor = ActionExecutor.new()
	router = InteractionRouter.new(config, executor)
	router.worlds = LivingScript.world_directory()
	reports = []
	started = []
	router.request_finished.connect(func(r: Dictionary) -> void: reports.append(r))
	router.request_started.connect(func(r: Dictionary) -> void: started.append(r))


func after_each() -> void:
	_clean()


func _clean() -> void:
	var p := TMP_DIR.path_join(ConfigSchema.FILE)
	for f in [p, p + MikuConfig.TEMP_SUFFIX]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(TMP_DIR)):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP_DIR))


## Args of a dispatched step without the correlation keys (request_id, step).
func _vocab_args(args: Dictionary) -> Dictionary:
	var d := args.duplicate()
	for k in ActionVocabulary.CORRELATION_ARGS:
		d.erase(k)
	return d


## request_id of the n-th started request (from the router's request_started).
func r_id(n: int) -> int:
	return int(started[n]["request_id"])


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
	assert_eq(_vocab_args(edit[0][2]), {"file": ConfigSchema.FILE, "path": "appearance.height", "value": 1.03, "old_value": 1.0})
	assert_eq(edit[0][2]["request_id"], r_id(0), "correlated")
	assert_eq(edit[0][2]["step"], 5)
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
	assert_eq(_vocab_args(ack[0][2]), {"tone": "decline", "reason": ProviderPort.UNAVAILABLE})
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
	# The body never answers: each step times out after estimate x 2 + 3 s (null estimate 0 -> 3 s).
	assert_eq(InteractionRouter.step_timeout(0.0), 3.0)
	for i in 3:
		router.tick(InteractionRouter.step_timeout(0.0) + 0.1)
	assert_eq(reports.size(), 1, "attention plan ended by timeouts")
	assert_eq(reports[0]["status"], InteractionRouter.ST_ATTENTION, "non-critical failures: the plan goes on")
	assert_eq((reports[0]["failures"] as Array).size(), 3)
	assert_true(String(reports[0]["failures"][0]["reason"]).begins_with("timeout"))
	assert_eq(router.current_step()["action"], V.LOOK_AT_USER, "next request started")
	router.cancel()
	assert_false(router.busy())
	assert_eq(reports.back()["status"], InteractionRouter.ST_CANCELLED)
	assert_eq(config.get_value("appearance.height"), 1.0, "cancelled before the edit: nothing applied")
	# Queue limit.
	for i in InteractionRouter.MAX_QUEUE + 3:
		router.submit_text("Miku, aumente sua altura")
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


## Correlated stand-in for the animator's Miku (docs/contracts/loop-05-round2.md): action_event,
## estimate_duration, cancel; `own(action)` simulates a perform of MIKU herself (request_id 0).
class _FakeMikuCorrelated:
	extends Node
	signal action_event(request_id: int, action: StringName, phase: StringName, info: Dictionary)
	signal action_finished(action: StringName)
	var calls_log: Array = []
	var running: Array = []  # [request_id, action, step]
	var refuse := false

	func perform(action: StringName, args: Dictionary = {}) -> bool:
		calls_log.append([&"perform", action, args])
		if refuse:
			return false
		var rid := int(args.get("request_id", 0))
		var step := int(args.get("step", -1))
		running.append([rid, action, step])
		action_event.emit(rid, action, &"accepted", {"step": step})
		action_event.emit(rid, action, &"started", {"step": step})
		return true

	func estimate_duration(action: StringName, _args: Dictionary = {}) -> float:
		return 2.0 if action == &"SUMMON_HANDS" else 1.0

	func cancel(request_id: int) -> void:
		calls_log.append([&"cancel", request_id])
		for r: Array in running.duplicate():
			if r[0] == request_id:
				running.erase(r)
				action_event.emit(r[0], r[1], &"cancelled", {"step": r[2], "reason": "cancel"})

	func notice_user() -> void:
		calls_log.append([&"notice_user"])

	func target_world(id: StringName) -> void:
		calls_log.append([&"target_world", id])

	## Ends the oldest running action of the router (request_id > 0).
	func finish_current(phase: StringName = &"finished", info: Dictionary = {}) -> void:
		for r: Array in running:
			if r[0] > 0:
				running.erase(r)
				var d := info.duplicate()
				d["step"] = r[2]
				action_event.emit(r[0], r[1], phase, d)
				action_finished.emit(r[1])
				return

	## A perform of MIKU herself (roteiro / agenda): request_id 0, start to finish.
	func own(action: StringName) -> void:
		action_event.emit(0, action, &"accepted", {"step": -1})
		action_event.emit(0, action, &"started", {"step": -1})
		action_event.emit(0, action, &"finished", {"step": -1})
		action_finished.emit(action)


func test_request_ids_are_unique_and_args_correlated() -> void:
	router.submit_text("Miku!")
	router.submit_text("Miku!")
	var other := InteractionRouter.new(config, ActionExecutor.new())
	var other_started: Array = []
	other.request_started.connect(func(r: Dictionary) -> void: other_started.append(r))
	other.submit_text("Miku!")
	assert_gt(r_id(0), 0)
	assert_gt(r_id(1), r_id(0))
	assert_gt(int(other_started[0]["request_id"]), r_id(1), "unique across routers (recomposition)")
	assert_eq(reports[0]["request_id"], r_id(0))
	var performs: Array = executor.calls.filter(func(c: Array) -> bool: return c[0] == &"perform")
	for i in 3:
		assert_eq(performs[i][2]["request_id"], r_id(0))
		assert_eq(performs[i][2]["step"], i)
	assert_eq(performs[3][2]["request_id"], r_id(1))
	assert_eq(performs[3][2]["step"], 0)
	# A provider cannot forge the correlation keys.
	assert_false(ActionVocabulary.validate(V.THINK, {"request_id": 7}).is_empty())


func test_events_of_other_requests_and_steps_are_ignored() -> void:
	executor.auto_finish = false
	router.submit_text("Miku!")
	var rid := r_id(0)
	assert_eq(router.current_step()["action"], V.LOOK_AT_USER)
	executor.emit_event(rid + 1000, V.LOOK_AT_USER, &"finished", {"step": 0})
	executor.emit_event(rid, V.LOOK_AT_USER, &"finished", {"step": 1})
	executor.emit_event(rid, V.ACKNOWLEDGE, &"finished", {"step": 0})
	executor.emit_event(0, V.LOOK_AT_USER, &"finished", {"step": 0})
	executor.emit_event(0, V.LOOK_AT_USER, &"finished", {})
	assert_eq(router.current_step()["action"], V.LOOK_AT_USER, "still waiting for its own step")
	assert_eq(router.snapshot()["step_index"], 0)
	assert_gte(router.ignored_events, 5)
	executor.finish()
	assert_eq(router.current_step()["action"], V.ACKNOWLEDGE, "its own event advances")
	# A late event of a finished step changes nothing.
	executor.emit_event(rid, V.LOOK_AT_USER, &"finished", {"step": 0})
	assert_eq(router.current_step()["action"], V.ACKNOWLEDGE)
	while router.busy():
		executor.finish()
	assert_eq(reports[0]["status"], InteractionRouter.ST_ATTENTION)
	assert_eq((reports[0]["steps"] as Array).size(), 3)
	assert_eq((reports[0]["failures"] as Array).size(), 0)


func test_miku_own_performs_are_never_consumed() -> void:
	var body := _FakeMikuCorrelated.new()
	add_child_autofree(body)
	var e := MikuNodeExecutor.new(body)
	assert_true(e.is_correlated())
	router.set_executor(e)
	router.submit_text("Miku, trabalhe no planeta da direita")
	body.finish_current()  # LOOK_AT_WORLD
	body.finish_current()  # POINT
	assert_eq(router.current_step()["action"], V.SUMMON_HANDS)
	# The roteiro (living.hands) makes MIKU summon hands herself: request_id 0.
	body.own(V.SUMMON_HANDS)
	assert_eq(router.current_step()["action"], V.SUMMON_HANDS, "her own SUMMON_HANDS is not the router's")
	body.finish_current()
	assert_eq(router.current_step()["action"], V.WORK)
	body.own(V.WORK)
	assert_true(router.busy())
	body.finish_current()
	assert_false(router.busy())
	assert_eq(reports[0]["status"], InteractionRouter.ST_WORLD)
	assert_eq((reports[0]["failures"] as Array).size(), 0)


func test_node_executor_correlated_estimate_cancel_and_refusal() -> void:
	var body := _FakeMikuCorrelated.new()
	add_child_autofree(body)
	var e := MikuNodeExecutor.new(body)
	router.set_executor(e)
	assert_eq(e.estimate_duration(V.SUMMON_HANDS, {}), 2.0, "the body's estimate")
	router.indicate_world(&"world_vesper")
	var s := router.snapshot()
	assert_eq(s["step_estimate"], 1.0)
	assert_eq(s["step_timeout"], 1.0 * InteractionRouter.TIMEOUT_FACTOR + InteractionRouter.TIMEOUT_MARGIN)
	assert_eq(s["step_phase"], "started")
	var rid := r_id(0)
	router.cancel()
	assert_has(body.calls_log, [&"cancel", rid], "reset cancels on the body")
	assert_eq(body.running.size(), 0)
	assert_eq(reports[0]["status"], InteractionRouter.ST_CANCELLED)
	assert_false(router.busy())
	# A refused perform fails at once; the plan goes on.
	body.refuse = true
	router.submit_text("Miku!")
	assert_false(router.busy(), "every step refused -> failed -> plan over, nothing blocks")
	assert_eq((reports[1]["failures"] as Array).size(), 3)
	assert_true(String(reports[1]["failures"][0]["reason"]).contains("refused"))


func test_step_timeout_is_derived_from_the_estimate() -> void:
	executor.auto_finish = false
	executor.durations = {V.LOOK_AT_USER: 1.0, V.ACKNOWLEDGE: 0.5, V.WORK: 2.0}
	router.submit_text("Miku!")
	var rid := r_id(0)
	assert_eq(router.snapshot()["step_timeout"], 5.0, "1.0 x 2 + 3")
	router.tick(4.9)
	assert_eq(router.current_step()["action"], V.LOOK_AT_USER, "not yet")
	router.tick(0.2)
	assert_eq(router.current_step()["action"], V.ACKNOWLEDGE, "timed out -> next step")
	assert_has(executor.calls, [&"cancel", rid], "the timed-out action is cancelled on the body")
	assert_eq(router.snapshot()["step_timeout"], 4.0, "0.5 x 2 + 3")
	executor.finish()
	executor.finish()
	var r := reports[0]
	assert_eq(r["status"], InteractionRouter.ST_ATTENTION)
	assert_eq(r["steps"][0]["result"], InteractionRouter.R_TIMEOUT)
	assert_eq(r["steps"][1]["result"], InteractionRouter.R_FINISHED)
	assert_eq(r["failures"].size(), 1)
	assert_eq(r["failures"][0]["action"], String(V.LOOK_AT_USER))
	assert_true(String(r["failures"][0]["reason"]).contains("estimate 1.0s"))


func test_edit_timeout_or_failure_applies_nothing() -> void:
	executor.auto_finish = false
	router.submit_text("Miku, aumente sua altura")
	for i in 5:
		executor.finish()
	assert_eq(router.current_step()["action"], V.EDIT_FILE)
	router.tick(InteractionRouter.step_timeout(0.0) + 0.1)
	assert_eq(config.get_value("appearance.height"), 1.0, "the edit never finished: nothing applied")
	assert_eq(router.current_step()["action"], V.ACKNOWLEDGE, "not-applied tail")
	while router.busy():
		executor.finish()
	var r := reports[0]
	assert_eq(r["status"], InteractionRouter.ST_COMMIT_FAILED)
	assert_true(String(r["reason"]).contains("EDIT_FILE timeout"))
	assert_eq(r["plan"].slice(-3), [V.ACKNOWLEDGE, V.DISCARD, V.WORK])
	assert_false(executor.performed().has(V.SATISFIED))
	assert_false(config.has_user_file())
	# GRAB_FILE failing: same (the file never reached her hand).
	router.submit_text("Miku, aumente sua altura")
	for i in 3:
		executor.finish()
	assert_eq(router.current_step()["action"], V.GRAB_FILE)
	executor.fail("no hand")
	while router.busy():
		executor.finish()
	assert_eq(reports[1]["status"], InteractionRouter.ST_COMMIT_FAILED)
	assert_true(String(reports[1]["reason"]).contains("no hand"))
	assert_false(executor.performed().slice(-4).has(V.EDIT_FILE))
	assert_eq(config.get_value("appearance.height"), 1.0)


func test_non_critical_failure_goes_on() -> void:
	executor.auto_finish = false
	router.indicate_world(&"world_calyx")
	executor.finish()
	executor.fail("arm busy")  # POINT
	assert_eq(router.current_step()["action"], V.SUMMON_HANDS)
	executor.finish()
	executor.finish()
	assert_eq(reports[0]["status"], InteractionRouter.ST_WORLD)
	assert_eq(reports[0]["failures"][0]["reason"], "failed: arm busy")
	# A cancellation the router did not ask for counts as a failure too.
	router.submit_text("Miku!")
	executor.cancel(r_id(1))
	assert_eq(router.current_step()["action"], V.ACKNOWLEDGE)
	assert_eq(reports.size(), 1)
	while router.busy():
		executor.finish()
	assert_eq(reports[1]["steps"][0]["result"], InteractionRouter.R_CANCELLED)


func test_simulated_duration_and_report_timings() -> void:
	executor.simulated_duration = 1.0
	router.submit_text("Miku!")
	assert_eq(started[0]["estimate"], 3.0)
	assert_eq(started[0]["deadline"], 3 * 5.0)
	assert_eq(router.current_step()["action"], V.LOOK_AT_USER)
	router.tick(0.5)
	assert_eq(router.current_step()["action"], V.LOOK_AT_USER)
	router.tick(0.6)
	assert_eq(router.current_step()["action"], V.ACKNOWLEDGE)
	for i in 10:
		router.tick(0.5)
	assert_false(router.busy())
	var r := reports[0]
	assert_almost_eq(float(r["duration"]), 3.0, 0.6)
	assert_almost_eq(float(r["estimate"]), 3.0, 1e-6)
	assert_eq(r["steps"][0]["latency"], 0.0, "started at once")
	var phases: Array = executor.events.filter(func(x: Array) -> bool: return x[1] == V.LOOK_AT_USER).map(
		func(x: Array) -> StringName: return x[2])
	assert_eq(phases, [&"accepted", &"started", &"finished"])


func test_interaction_started_comes_before_any_finished() -> void:
	var log: Array = []
	router.request_started.connect(func(r: Dictionary) -> void: log.append(["started", r]))
	executor.action_event.connect(func(_rid: int, a: StringName, ph: StringName, _i: Dictionary) -> void:
		log.append([String(ph), a]))
	router.request_finished.connect(func(r: Dictionary) -> void: log.append(["reported", r]))
	router.submit_text("Miku, aumente sua altura")
	assert_eq(log[0][0], "started", "first: the request is recognised")
	var st: Dictionary = log[0][1]
	assert_eq(st["status"], InteractionRouter.ST_STARTED)
	assert_eq(st["kind"], "CONFIG_PATCH")
	assert_eq(st["route"], "LOCAL")
	assert_eq(st["path"], "appearance.height")
	assert_eq(st["expected_status"], InteractionRouter.ST_APPLIED)
	assert_eq(st["plan"].size(), 10)
	assert_gt(int(st["request_id"]), 0)
	assert_eq(st["id"], reports[0]["id"])
	var first_finished := log.map(func(x: Array) -> String: return x[0]).find("finished")
	assert_gt(first_finished, 0)
	assert_eq(log.back()[0], "reported")


func test_fifo_queue_one_active_plan() -> void:
	executor.auto_finish = false
	router.indicate_world(&"world_vesper")
	router.submit_text("Miku, me dê asas")
	router.submit_text("appearance.glow 0.9")
	assert_eq(started.size(), 1, "one plan runs")
	assert_eq(router.snapshot()["queue"], 2)
	while router.busy():
		executor.finish()
	assert_eq(started.map(func(x: Dictionary) -> String: return x["kind"]), ["WORLD_TARGET", "CONFIG_PATCH", "CONFIG_PATCH"])
	assert_eq(reports.map(func(x: Dictionary) -> String: return x["status"]),
		[InteractionRouter.ST_WORLD, InteractionRouter.ST_REQUIRES_ASSET, InteractionRouter.ST_APPLIED])


func _set_tolerance(v: float) -> void:
	assert_true(config.apply(ConfigValidator.validate(StructuredPatch.absolute("behaviour.interruption_tolerance", v),
		config.values())))


func test_attention_interrupts_by_tolerance() -> void:
	executor.auto_finish = false
	router.indicate_world(&"world_vesper")
	executor.finish()  # LOOK_AT_WORLD; POINT in flight: 3 of 4 steps remain (0.75 > 1 - 0.5)
	var world_rid := r_id(0)
	assert_true(router.should_interrupt())
	router.call_attention()
	assert_has(executor.calls, [&"cancel", world_rid], "the running plan is cancelled on the body")
	assert_eq(started[1]["kind"], "ATTENTION", "attention runs now")
	assert_eq(router.snapshot()["queue"], 1, "the interrupted plan waits right after it")
	while router.busy():
		executor.finish()
	assert_eq(reports[0]["status"], InteractionRouter.ST_ATTENTION)
	var w := reports[1]
	assert_eq(w["status"], InteractionRouter.ST_WORLD, "restarted and completed")
	assert_eq(w["interrupted"], 1)
	assert_eq(w["request_ids"].size(), 2)
	assert_ne(int(w["request_id"]), world_rid, "a new request_id for the restart")
	assert_true(started[2]["restart"])
	assert_eq(started[2]["plan"][0], V.LOOK_AT_WORLD, "from its first step")
	# Tolerance 0: never interrupted (FIFO).
	_set_tolerance(0.0)
	router.indicate_world(&"world_vesper")
	assert_false(router.should_interrupt())
	router.call_attention()
	assert_eq(router.current_step()["action"], V.LOOK_AT_WORLD, "she finishes first")
	while router.busy():
		executor.finish()
	assert_eq(reports[2]["kind"], "WORLD_TARGET")
	assert_eq(reports[2]["interrupted"], 0)
	assert_eq(reports[3]["kind"], "ATTENTION")


func test_attention_never_interrupts_the_file_section_or_attention() -> void:
	_set_tolerance(1.0)
	executor.auto_finish = false
	router.submit_text("Miku, aumente sua altura")
	executor.finish()
	assert_true(router.should_interrupt(), "before the file: interruptible")
	executor.finish()
	executor.finish()
	assert_eq(router.current_step()["action"], V.GRAB_FILE)
	assert_false(router.should_interrupt(), "file in her hands")
	router.call_attention()
	assert_eq(router.current_step()["action"], V.GRAB_FILE)
	executor.finish()
	executor.finish()
	executor.finish()  # EDIT_FILE -> commit
	assert_almost_eq(float(config.get_value("appearance.height")), 1.03, 1e-6)
	assert_eq(router.current_step()["action"], V.INSPECT)
	# After the commit the queued attention waits FIFO; a new one interrupts and the applied
	# request simply ends (nothing to restart).
	assert_true(router.should_interrupt())
	router.call_attention()
	assert_eq(reports[0]["status"], InteractionRouter.ST_APPLIED)
	assert_eq(reports[0]["interrupted"], 1)
	assert_true(str(reports[0]["notes"]).contains("interrupted"))
	assert_false(router.should_interrupt(), "attention is not interrupted by attention")
	while router.busy():
		executor.finish()
	assert_eq(reports.size(), 3)


func test_cancel_on_reset_ignores_late_events_and_executor_swap() -> void:
	executor.auto_finish = false
	router.submit_text("Miku, aumente sua altura")
	router.submit_text("Miku, me dê asas")
	var rid := r_id(0)
	executor.finish()
	router.cancel()
	assert_has(executor.calls, [&"cancel", rid])
	assert_eq(reports.size(), 2)
	for r in reports:
		assert_eq(r["status"], InteractionRouter.ST_CANCELLED)
	assert_eq(reports[0]["steps"].back()["result"], InteractionRouter.R_CANCELLED)
	var ignored := router.ignored_events
	executor.emit_event(rid, V.ACKNOWLEDGE, &"finished", {"step": 1})
	assert_eq(router.ignored_events, ignored + 1, "late event after reset: ignored")
	assert_false(router.busy())
	assert_eq(config.get_value("appearance.height"), 1.0)
	# Executor swapped mid-step: the step fails ("executor replaced"), the plan goes on.
	router.submit_text("Miku!")
	var fresh := ActionExecutor.new()
	fresh.auto_finish = false
	router.set_executor(fresh)
	assert_eq(router.current_step()["action"], V.ACKNOWLEDGE)
	assert_eq(fresh.performed(), [V.ACKNOWLEDGE] as Array[StringName])
	while router.busy():
		fresh.finish()
	assert_eq(reports.back()["failures"][0]["reason"], "failed: executor replaced")
