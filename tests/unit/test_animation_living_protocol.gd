extends GutTest
## Loop 5 r2 (Bloco 1) — the correlated-action protocol of Miku: action_event phases per
## request/step (accepted -> started -> progress* -> exactly one terminal), estimate_duration
## honesty, cancel(request_id) (and what it dissolves), the immediate acknowledgement of a user
## plan's first look, and the causal timeline of inspect_state().causality.

const DT := 1.0 / 30.0
const CHAIN: Array[StringName] = [&"intent", &"anticipation", &"gesture", &"thread", &"hand", &"matter"]

var root: Node3D
var miku: Miku
## [request_id, action, phase, info, time]
var events: Array = []
var _t := 0.0


func before_each() -> void:
	root = Node3D.new()
	add_child_autofree(root)
	miku = Miku.new()
	root.add_child(miku)
	miku.set_process(false)
	events.clear()
	_t = 0.0
	miku.action_event.connect(func(rid: int, a: StringName, ph: StringName, info: Dictionary) -> void:
		events.append([rid, a, ph, info, _t]))
	miku.tick(DT)


func _tick(seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		miku.tick(DT)
		t += DT
		_t += DT


func _of(rid: int, step := -1) -> Array:
	var out := []
	for e: Array in events:
		if e[0] == rid and (step < 0 or int((e[3] as Dictionary)["step"]) == step):
			out.append(e)
	return out


func _terminal_of(rid: int, step: int) -> Array:
	for e: Array in _of(rid, step):
		if e[2] in Miku.TERMINAL:
			return e
	return []


## Ticks until request rid/step has its terminal (or `limit` s).
func _until_terminal(rid: int, step: int, limit := 20.0) -> float:
	var t0 := _t
	while _terminal_of(rid, step).is_empty() and _t - t0 < limit:
		_tick(DT)
	return _t - t0


const PLAN: Array = [
	[&"LOOK_AT_USER", {}], [&"ACKNOWLEDGE", {"tone": "warm"}], [&"ACKNOWLEDGE", {"tone": "brief"}],
	[&"THINK", {"seconds": 1.0}], [&"LOOK_AT_WORLD", {"world": &"world_vesper"}],
	[&"POINT", {"target": &"world_vesper"}], [&"INSPECT", {"target": &"world_orrin"}],
	[&"SUMMON_HAND", {"side": "left", "role": "hold"}], [&"GRAB_FILE", {"file": "f"}],
	[&"SUMMON_HAND", {"side": "right", "role": "edit"}],
	[&"EDIT_FILE", {"file": "f", "path": "appearance.height", "value": 1.03}],
	[&"INSPECT", {"target": "self", "path": "appearance.height"}],
	[&"SATISFIED", {"intensity": 0.6}], [&"DISCARD", {"applied": true}],
	[&"SUMMON_HANDS", {"count": 3}], [&"FRUSTRATED", {}], [&"RECOVER", {}], [&"ANGRY", {}], [&"RECOVER", {}],
	[&"WORK", {"world": &"world_calyx"}],
]


func test_phases_per_request_and_step() -> void:
	for i in PLAN.size():
		var step: Array = PLAN[i]
		var args: Dictionary = (step[1] as Dictionary).duplicate()
		args["request_id"] = 40
		args["step"] = i
		assert_true(miku.perform(step[0], args))
		_until_terminal(40, i)
		var seq := _of(40, i)
		assert_gt(seq.size(), 2, "%s has events" % step[0])
		assert_eq(seq[0][2], Miku.PH_ACCEPTED, "%s accepted first" % step[0])
		assert_true((seq[0][3] as Dictionary).has("estimate"))
		assert_eq(seq[1][2], Miku.PH_STARTED, "%s then started" % step[0])
		var terminals := 0
		for k in seq.size():
			assert_eq(seq[k][1], step[0], "events carry the action")
			if seq[k][2] in Miku.TERMINAL:
				terminals += 1
				assert_eq(k, seq.size() - 1, "%s: the terminal is the last event" % step[0])
			elif k >= 2:
				assert_eq(seq[k][2], Miku.PH_PROGRESS)
				var pt := float((seq[k][3] as Dictionary)["t"])
				assert_between(pt, 0.0, 1.0)
		assert_eq(terminals, 1, "%s: exactly one terminal" % step[0])
	_tick(3.0)
	for i in PLAN.size():
		var n := 0
		for e: Array in _of(40, i):
			if e[2] in Miku.TERMINAL:
				n += 1
		assert_eq(n, 1, "step %d: still one terminal after the plan" % i)


func test_own_actions_use_request_zero_and_unknown_is_silent() -> void:
	assert_false(miku.perform(&"FLY", {"request_id": 3}))
	_tick(0.5)
	assert_true(events.is_empty(), "nothing accepted")
	miku.call(&"_on_sim_event", SimEvent.new(&"t", 0.0, &"living.hands", "living.hands", "", &"miku",
		{"count": 2, "world": &"world_calyx"}))
	_until_terminal(0, 0)
	assert_false(_terminal_of(0, 0).is_empty(), "the roteiro's summon is her own (request 0)")
	assert_eq(_terminal_of(0, 0)[1], &"SUMMON_HANDS")


func test_estimates_are_honest() -> void:
	# Each action alone, at rest: the real duration stays well inside the router's timeout
	# (estimate x 2 + 3 s) and close to the estimate.
	var report := []
	for i in PLAN.size():
		var step: Array = PLAN[i]
		var args: Dictionary = (step[1] as Dictionary).duplicate()
		args["request_id"] = 50
		args["step"] = i
		var est := miku.estimate_duration(step[0], args)
		assert_gt(est, 0.0)
		miku.perform(step[0], args)
		var real := _until_terminal(50, i, est * 2.0 + 3.0)
		assert_false(_terminal_of(50, i).is_empty(), "%s ended inside the router's timeout" % step[0])
		report.append("%s est %.2f real %.2f" % [step[0], est, real])
		assert_between(real, est * 0.6 - 0.35, est * 1.4 + 0.5, "%s: real %.2f vs estimate %.2f" % [step[0], real, est])
	gut.p("estimates: " + ", ".join(report))


func test_estimate_counts_the_queue() -> void:
	miku.perform(&"SUMMON_HANDS", {"count": 2, "request_id": 1, "step": 0})
	_tick(0.5)
	var alone := miku.call(&"_beats_estimate", ActionScript.beats(&"THINK", {"seconds": 1.0}), 0.0, 0.0) as float
	var queued := miku.estimate_duration(&"THINK", {"seconds": 1.0})
	assert_gt(queued, alone + 2.0, "a queued action waits for the running one")


func test_user_look_starts_at_once_while_busy() -> void:
	miku.perform(&"SUMMON_HANDS", {"count": 2})
	_tick(0.8)
	var before := miku.body.motor.eye_dir
	var t0 := _t
	miku.perform(&"LOOK_AT_WORLD", {"world": &"world_orrin", "request_id": 7, "step": 0})
	var started := -1.0
	for e: Array in _of(7, 0):
		if e[2] == Miku.PH_STARTED:
			started = float(e[4]) - t0
	assert_between(started, 0.0, Miku.ACK_LATENCY, "the look starts at once (not queued behind the summon)")
	_tick(Miku.ACK_LATENCY)
	var turned := rad_to_deg(before.angle_to(miku.body.motor.eye_dir))
	assert_gt(turned, 4.0, "her eyes have visibly moved within %.1f s (%.1f deg)" % [Miku.ACK_LATENCY, turned])
	assert_eq(miku.current_action(), &"SUMMON_HANDS", "the running action goes on")
	_until_terminal(7, 0)
	assert_eq(_terminal_of(7, 0)[2], Miku.PH_FINISHED)


func test_user_look_cuts_the_other_perception() -> void:
	miku.target_world(&"world_orrin")
	_tick(0.2)
	var t0 := _t
	miku.perform(&"LOOK_AT_USER", {"request_id": 8, "step": 0})
	var started := false
	for e: Array in _of(8, 0):
		started = started or e[2] == Miku.PH_STARTED
	assert_true(started, "started in the same frame")
	assert_eq(miku.inspect_state()["overlay"], &"LOOK_AT_USER")
	_until_terminal(8, 0)
	assert_lt(_t - t0, 4.0)


func test_look_joins_the_reaction() -> void:
	miku.notice_user()
	_tick(0.1)
	miku.perform(&"LOOK_AT_USER", {"request_id": 9, "step": 0})
	assert_eq(_of(9, 0)[1][2], Miku.PH_STARTED)
	assert_eq((_of(9, 0)[1][3] as Dictionary)["channel"], &"follower")
	_until_terminal(9, 0)
	assert_eq(_terminal_of(9, 0)[2], Miku.PH_FINISHED)


func test_cancel_dissolves_what_belongs_to_the_request() -> void:
	miku.perform(&"SUMMON_HANDS", {"count": 3, "request_id": 11, "step": 0})
	miku.perform(&"THINK", {"request_id": 11, "step": 1})
	miku.perform(&"ACKNOWLEDGE", {"request_id": 12, "step": 0, "tone": "brief"})
	_tick(1.6)
	assert_eq(miku.hands.active_count(), 3)
	assert_gt(miku.threads.alive_count(), 0)
	var n := miku.cancel(11)
	assert_eq(n, 2, "the running summon and the queued think")
	assert_eq(_terminal_of(11, 0)[2], Miku.PH_CANCELLED)
	assert_eq(_terminal_of(11, 1)[2], Miku.PH_CANCELLED)
	for h in miku.hands.active_hands():
		assert_eq(h.goal_presence, 0.0, "its hands dissolve")
	assert_eq(miku.current_action(), &"", "nothing of request 11 runs")
	_tick(4.0)
	assert_eq(miku.hands.active_count(), 0)
	assert_eq(miku.threads.alive_count(), 0, "their threads are gone")
	assert_eq(_terminal_of(12, 0)[2], Miku.PH_FINISHED, "another request is untouched")
	assert_eq(miku.cancel(11), 0, "nothing left to cancel")


func test_cancel_vanishes_the_artifact_and_the_task() -> void:
	miku.perform(&"GRAB_FILE", {"file": "f", "request_id": 21, "step": 0})
	_tick(1.2)
	assert_true(miku.artifact.is_present())
	miku.cancel(21)
	assert_eq(_terminal_of(21, 0)[2], Miku.PH_CANCELLED)
	_tick(2.0)
	assert_false(miku.artifact.is_present(), "the card it called is gone")
	miku.perform(&"WORK", {"world": &"world_vesper", "request_id": 22, "step": 0})
	_until_terminal(22, 0)
	assert_true(miku.is_working())
	_tick(3.0)
	miku.cancel(22)
	assert_false(miku.is_working(), "the work it started stops")
	assert_eq(_of(22, 0).filter(func(e: Array) -> bool: return e[2] in Miku.TERMINAL).size(), 1,
		"WORK already had its terminal: none more")


## The configuration plans of docs/AGENT.md, driven like the InteractionRouter does: the next
## step is performed SYNCHRONOUSLY from the previous step's terminal (re-entrancy), each step's
## estimate taken just before it is performed.
const CONFIG_APPLIED: Array = [
	[&"LOOK_AT_USER", {}], [&"ACKNOWLEDGE", {"tone": "brief"}], [&"SUMMON_HAND", {"side": "left", "role": "hold"}],
	[&"GRAB_FILE", {"file": "miku"}], [&"SUMMON_HAND", {"side": "right", "role": "edit"}],
	[&"EDIT_FILE", {"file": "miku", "path": "appearance.height", "value": 1.05, "old_value": 1.0}],
	[&"INSPECT", {"target": "self", "path": "appearance.height"}], [&"SATISFIED", {"intensity": 0.6}],
	[&"DISCARD", {"applied": true}], [&"WORK", {"resume": true}],
]
const CONFIG_UNCHANGED: Array = [
	[&"LOOK_AT_USER", {}], [&"ACKNOWLEDGE", {"tone": "brief"}], [&"SUMMON_HAND", {"side": "left", "role": "hold"}],
	[&"GRAB_FILE", {"file": "miku"}], [&"INSPECT", {"target": "file", "path": "appearance.height"}],
	[&"ACKNOWLEDGE", {"tone": "decline"}], [&"DISCARD", {"applied": false}], [&"WORK", {"resume": true}],
]


func _router_plan(plan: Array, rid: int) -> Array:
	var state := {"step": 0, "t0": 0.0, "est": [], "real": []}
	var run_step := func(i: int) -> void:
		var args: Dictionary = (plan[i][1] as Dictionary).duplicate()
		args["request_id"] = rid
		args["step"] = i
		state["est"].append(miku.estimate_duration(plan[i][0], args))
		state["t0"] = _t
		assert_true(miku.perform(plan[i][0], args))
	var on_event := func(r: int, a: StringName, ph: StringName, info: Dictionary) -> void:
		if r != rid or int(info["step"]) != int(state["step"]) or not ph in Miku.TERMINAL:
			return
		assert_eq(a, plan[int(state["step"])][0])
		state["real"].append(_t - float(state["t0"]))
		state["step"] = int(state["step"]) + 1
		if int(state["step"]) < plan.size():
			run_step.call(int(state["step"]))
	miku.action_event.connect(on_event)
	run_step.call(0)
	var t := 0.0
	while int(state["step"]) < plan.size() and t < 90.0:
		_tick(DT)
		t += DT
	miku.action_event.disconnect(on_event)
	assert_eq(int(state["step"]), plan.size(), "the whole plan ran (re-entrant performs)")
	return [state["est"], state["real"]]


func test_router_plans_reentrant_and_estimated() -> void:
	var rid := 90
	for plan: Array in [CONFIG_APPLIED, CONFIG_UNCHANGED]:
		var r := _router_plan(plan, rid)
		var est: Array = r[0]
		var real: Array = r[1]
		var se := 0.0
		var sr := 0.0
		var lines := []
		for i in real.size():
			se += float(est[i])
			sr += float(real[i])
			lines.append("%s %.2f/%.2f" % [plan[i][0], est[i], real[i]])
			assert_lt(float(real[i]), float(est[i]) * 2.0 + 3.0, "%s inside the router's timeout" % plan[i][0])
			assert_lt(float(real[i]), float(est[i]) * 1.35 + 0.5, "%s: real %.2f vs estimate %.2f" % [plan[i][0], real[i], est[i]])
		gut.p("plan est %.1f s real %.1f s: %s" % [se, sr, ", ".join(lines)])
		assert_between(sr, se * 0.8, se * 1.2, "the plan's total is estimated honestly")
		for i in plan.size():
			var n := 0
			for e: Array in _of(rid, i):
				if e[2] in Miku.TERMINAL:
					n += 1
			assert_eq(n, 1, "%s: one terminal" % plan[i][0])
		rid += 1
		_tick(8.0)


func test_cancel_all() -> void:
	miku.perform(&"SUMMON_HANDS", {"count": 2, "request_id": 81, "step": 0})
	miku.perform(&"THINK", {"request_id": 82, "step": 0})
	miku.perform(&"ACKNOWLEDGE", {"request_id": 83, "step": 0})
	_tick(0.5)
	assert_eq(miku.cancel_all(), 3)
	for rid in [81, 82, 83]:
		assert_eq(_terminal_of(rid, 0)[2], Miku.PH_CANCELLED)
	assert_false(miku.is_busy())


func test_discard_cancels_the_edit_it_interrupts() -> void:
	miku.perform(&"GRAB_FILE", {"file": "f", "request_id": 31, "step": 0})
	_tick(0.8)
	miku.perform(&"DISCARD", {"request_id": 32, "step": 0})
	assert_eq(_terminal_of(31, 0)[2], Miku.PH_CANCELLED)
	assert_eq((_terminal_of(31, 0)[3] as Dictionary)["reason"], "discarded")
	_until_terminal(32, 0)
	assert_eq(_terminal_of(32, 0)[2], Miku.PH_FINISHED)


func test_failed_when_the_change_is_never_applied() -> void:
	# EDIT_FILE outside the router waits for the change to be applied (Miku.apply_config): nobody
	# applies it here, so the edit ends as failed (and still ends).
	miku.perform(&"EDIT_FILE", {"file": "f", "request_id": 41, "step": 0})
	_until_terminal(41, 0, 30.0)
	var term := _terminal_of(41, 0)
	assert_eq(term[2], Miku.PH_FAILED)
	assert_eq((term[3] as Dictionary)["reason"], "timeout:applied")


func _check_chain(e: Dictionary) -> String:
	var t: Dictionary = e["t"]
	var prev := -1.0
	var missing := false
	for s in CHAIN:
		if not t.has(s):
			missing = true
			continue
		if missing:
			return "%s without its previous stage" % s
		if float(t[s]) < prev:
			return "%s before the previous stage" % s
		prev = float(t[s])
	if e["phase"] != "" and (not t.has("result") or float(t["result"]) < prev):
		return "result before the chain"
	return ""


func test_causal_timelines_are_ordered() -> void:
	for i in PLAN.size():
		var step: Array = PLAN[i]
		var args: Dictionary = (step[1] as Dictionary).duplicate()
		args["request_id"] = 60
		args["step"] = i
		miku.perform(step[0], args)
		_until_terminal(60, i)
	_tick(25.0)
	var tl: Array = miku.inspect_state()["causality"]
	assert_gt(tl.size(), 10)
	var seen := {}
	for e: Dictionary in tl:
		var why := _check_chain(e)
		assert_eq(why, "", "%s/%s %s %s: %s" % [e["request_id"], e["step"], e["action"], e["stage"], e["t"]])
		for s: String in e["t"]:
			seen[s] = true
	for s in [&"intent", &"anticipation", &"gesture", &"thread", &"hand", &"matter", &"result"]:
		assert_true(seen.has(s), "some action reached %s" % s)


func test_failure_story_timeline() -> void:
	miku.perform(&"WORK", {"world": &"world_calyx", "fail": true, "request_id": 70, "step": 0})
	_tick(70.0)
	var stages := []
	for e: Dictionary in miku.causality():
		assert_eq(_check_chain(e), "", "%s %s: %s" % [e["action"], e["stage"], e["t"]])
		if e["channel"] == "task":
			stages.append(e["stage"])
			assert_eq(e["request_id"], 70, "the task belongs to WORK's request")
	assert_true(stages.has("GATHER") and stages.has("LAYERS"), "one entry per stage: %s" % [stages])
