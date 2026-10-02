extends GutTest
## Loop 5 — MIKU's mind (MikuMind), micro-behaviour agenda (MicroAgenda) and parameters
## (MikuParams): moods by work events, composure, reactions to the user, agenda bound to state.


func _mind(config := {}) -> MikuMind:
	var p := MikuParams.new()
	p.apply(config)
	return MikuMind.new(p)


func _settle(m: MikuMind, seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		m.step(0.1)
		t += 0.1


func test_starts_calm_and_composed() -> void:
	var m := _mind()
	assert_eq(m.mood, MikuMind.Mood.CALM)
	assert_eq(m.composure, 1.0)
	assert_eq(m.rigidity(), 0.0)


func test_task_focuses_and_its_end_calms() -> void:
	var m := _mind()
	m.begin_task(&"build", &"world_calyx")
	assert_eq(m.mood, MikuMind.Mood.FOCUSED, "work focuses her")
	assert_eq(m.focus_kind(), MikuMind.Focus.WORK)
	m.end_task(false)
	assert_eq(m.mood, MikuMind.Mood.CALM)


func test_escalation_crack_then_collapse_reaches_anger_with_defaults() -> void:
	# The roteiro's two failures (WorkPlan.EVENT_FAIL_SEVERITY): concern, then lost composure.
	var m := _mind()
	m.begin_task(&"build", &"world_calyx")
	m.on_failure(WorkPlan.EVENT_FAIL_SEVERITY[0])
	assert_eq(m.mood, MikuMind.Mood.FOCUSED, "a first crack: concern, not yet frustration")
	m.on_failure(WorkPlan.EVENT_FAIL_SEVERITY[1])
	assert_eq(m.mood, MikuMind.Mood.ANGRY, "the collapse: composure lost")
	_settle(m, 2.0)
	assert_lt(m.composure, 0.3, "angry composure is low (aggression_peak)")
	assert_gt(m.tempo(), 1.5, "angry = extremely efficient")


func test_autonomous_failure_goes_through_frustration() -> void:
	var m := _mind()
	m.begin_task(&"build", &"w")
	m.on_failure(0.35)
	assert_eq(m.mood, MikuMind.Mood.FOCUSED)
	m.on_failure(0.32)
	assert_eq(m.mood, MikuMind.Mood.FRUSTRATED)
	m.on_failure(0.6)
	assert_eq(m.mood, MikuMind.Mood.ANGRY)


func test_success_after_anger_recovers_then_calms() -> void:
	var m := _mind()
	m.begin_task(&"build", &"w")
	m.force_mood(&"angry")
	assert_eq(m.mood, MikuMind.Mood.ANGRY)
	m.on_success(1.0)
	assert_eq(m.mood, MikuMind.Mood.RECOVERING)
	m.end_task(true)
	_settle(m, 1.0)
	assert_eq(m.mood, MikuMind.Mood.RECOVERING, "the recovery is seen, never skipped")
	_settle(m, 30.0)
	assert_eq(m.mood, MikuMind.Mood.CALM)
	assert_gt(m.composure, 0.9)


func test_composure_falls_fast_and_returns_slowly() -> void:
	var m := _mind()
	m.force_mood(&"angry")
	m.step(0.5)
	var fallen := 1.0 - m.composure
	m.on_success(1.0)
	var before := m.composure
	m.step(0.5)
	var risen := m.composure - before
	assert_gt(fallen, risen * 2.0, "losing composure is quick, regaining it slow")


func test_recovery_speed_modulates_the_recovery() -> void:
	var fast := _mind({"behaviour": {"recovery_speed": 1.0}})
	var slow := _mind({"behaviour": {"recovery_speed": 0.1}})
	for m in [fast, slow]:
		m.force_mood(&"angry")
		m.on_success(0.0)
		_settle(m, 6.0)
	assert_lt(fast.frustration, slow.frustration)


func test_threshold_and_temperament_modulate_anger() -> void:
	var serene := _mind({"identity": {"temperament": 0.0}, "behaviour": {"frustration_threshold": 0.9}})
	var fiery := _mind({"identity": {"temperament": 1.0}, "behaviour": {"frustration_threshold": 0.2}})
	assert_gt(serene.anger_level(), fiery.anger_level())
	fiery.on_failure(0.5)
	serene.on_failure(0.5)
	assert_eq(fiery.mood, MikuMind.Mood.ANGRY)
	assert_eq(serene.mood, MikuMind.Mood.CALM)


func test_user_call_reaction_depends_on_mood() -> void:
	var m := _mind()
	assert_eq(m.user_call()["reaction"], MikuMind.REACT_CURIOUS)
	m.begin_task(&"build", &"w")
	var r := m.user_call()
	assert_eq(r["reaction"], MikuMind.REACT_BRIEF)
	assert_false(r["leave_work"], "focused: a brief look, the work goes on")
	m.force_mood(&"frustrated")
	assert_eq(m.user_call()["reaction"], MikuMind.REACT_CURT)
	m.force_mood(&"angry")
	var cold := m.user_call()
	assert_eq(cold["reaction"], MikuMind.REACT_COLD)
	assert_eq(cold["turn"], 0.0, "angry: the eyes only")
	assert_eq(m.focus_kind(), MikuMind.Focus.USER, "she does attend")


func test_interruption_tolerance_lengthens_the_look() -> void:
	var a := _mind({"behaviour": {"interruption_tolerance": 0.0}})
	var b := _mind({"behaviour": {"interruption_tolerance": 1.0}})
	a.begin_task(&"build", &"w")
	b.begin_task(&"build", &"w")
	assert_lt(float(a.user_call()["hold"]), float(b.user_call()["hold"]))


func test_attention_override_expires_back_to_task() -> void:
	var m := _mind()
	m.begin_task(&"build", &"world_calyx")
	m.attend(MikuMind.Focus.HAND, &"h", 1.0)
	assert_eq(m.focus_kind(), MikuMind.Focus.HAND)
	_settle(m, 1.2)
	assert_eq(m.focus_kind(), MikuMind.Focus.WORK)
	assert_eq(m.focus_id(), &"world_calyx")


func test_params_clamp_and_report_changes() -> void:
	var p := MikuParams.new()
	var changed := p.apply({"appearance": {"height": 9.0, "unknown": 1.0}, "identity": {"pride": "x"}})
	assert_eq(changed, PackedStringArray(["appearance.height"]))
	assert_almost_eq(p.value(&"appearance", "height"), 1.1, 1e-6, "clamped to the supported range")
	assert_eq(p.apply({"appearance": {"height": 1.1}}).size(), 0, "same value = no change")
	assert_almost_eq(MikuParams.chest_factor(0.5), 1.0, 1e-6, "0.5 = the sculpted chest")
	assert_almost_eq(MikuParams.chest_factor(0.65), 1.2, 1e-6)
	assert_almost_eq(MikuParams.chest_factor(0.35), 0.85, 1e-6)


# ---------------------------------------------------------------- agenda


func _run_agenda(m: MikuMind, ctx: Dictionary, seconds: float, seed_value := 5051) -> MicroAgenda:
	var a := MicroAgenda.new(seed_value)
	var t := 0.0
	while t < seconds:
		a.step(0.1, m, ctx)
		m.step(0.1)
		t += 0.1
	return a


func test_agenda_is_deterministic_with_its_seed() -> void:
	var a := _run_agenda(_mind(), {}, 120.0)
	var b := _run_agenda(_mind(), {}, 120.0)
	assert_eq(a.history, b.history, "same seed, same life")
	var c := _run_agenda(_mind(), {}, 120.0, 99)
	assert_ne(a.history, c.history)


func test_agenda_never_repeats_back_to_back_when_idle() -> void:
	var a := _run_agenda(_mind(), {}, 300.0)
	assert_gt(a.history.size(), 40, "a behaviour every few seconds")
	for i in range(1, a.history.size()):
		assert_ne(a.history[i], a.history[i - 1], "no idle loop at %d" % i)


func test_agenda_variety_when_calm() -> void:
	var a := _run_agenda(_mind(), {}, 300.0)
	var kinds := {}
	for b in a.history:
		kinds[b] = true
	assert_gte(kinds.size(), 8, "breath, weight, eyes, posture, fingers, hand, world...")
	assert_false(kinds.has(MicroAgenda.HOLD), "the angry hold never appears when calm")


func test_agenda_follows_the_work_when_focused() -> void:
	var m := _mind()
	m.begin_task(&"build", &"w")
	var a := _run_agenda(m, {"working": true, "hands": 2}, 300.0)
	var work := 0
	for b in a.history:
		if b in [MicroAgenda.LOOK_AT_WORK, MicroAgenda.ADJUST, MicroAgenda.HESITATE, MicroAgenda.CONTINUE]:
			work += 1
	assert_gt(float(work) / a.history.size(), 0.5, "working: most of her small acts serve the work")


func test_agenda_angry_is_still() -> void:
	var m := _mind()
	m.force_mood(&"angry")
	var a := _run_agenda(m, {"working": true}, 120.0)
	for b in a.history:
		assert_true(b in [MicroAgenda.HOLD, MicroAgenda.LOOK_AT_WORK, MicroAgenda.ADJUST],
			"angry: locked, not human (%s)" % b)


func test_hesitation_is_resolved_by_continue() -> void:
	var m := _mind()
	m.begin_task(&"build", &"w")
	var a := _run_agenda(m, {"working": true, "failed": true}, 400.0)
	var found := false
	for i in a.history.size() - 1:
		if a.history[i] == MicroAgenda.HESITATE:
			found = true
			assert_eq(a.history[i + 1], MicroAgenda.CONTINUE)
	assert_true(found, "she hesitates at least once while the work is broken")
