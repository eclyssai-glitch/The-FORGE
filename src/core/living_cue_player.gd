class_name LivingCuePlayer
extends Node
## Plays LivingScript.USER_CUES (the LIVING user tests 5–7) as REAL input while the scenario
## plays: automation only (captures, recording tour). Each cue fires once when Simulation.time
## reaches it:
##   [t, "click", id]  — a mouse click (InputInjector) on a point of the entity's pick body that
##                       the Picker really resolves to `id` (checked in _physics_process). If no
##                       point is clickable (body missing, hidden, occluded) the cue falls back to
##                       Session.click(id) and says so.
##   [t, "say", text]  — Enter (Shortcuts opens the call line), then the text typed one character
##                       every TYPE_INTERVAL s into the focused LineEdit, then Enter (LineEdit
##                       submits -> Session.submit_call). If no LineEdit took the focus, the cue
##                       falls back to Session.submit_call(text) and says so.
## Every cue prints one `[living] cue ...` line (`real` or `fallback`).

signal cue_finished(cue: Array, real: bool)

const TYPE_INTERVAL := 0.05
## Seconds between Enter and the first character (the line opens), and before the final Enter.
const OPEN_WAIT := 0.5
const SUBMIT_WAIT := 0.4

var cues: Array = LivingScript.USER_CUES.duplicate(true)
## Cues finished: [cue, real].
var results: Array = []

var _next := 0
var _pending_click: Array = []
var _say: Array = []
var _say_stage := 0
var _say_clock := 0.0
var _typed := 0
var _submitted := ""
var _clicked: Array[StringName] = []


func _init() -> void:
	name = "LivingCuePlayer"


func _ready() -> void:
	Session.entity_clicked.connect(func(id: StringName) -> void: _clicked.append(id))
	Session.call_submitted.connect(func(t: String) -> void: _submitted = t)


func done() -> bool:
	return _next >= cues.size() and _pending_click.is_empty() and _say.is_empty()


func _process(delta: float) -> void:
	if not _say.is_empty():
		_step_say(delta)
		return
	if not _pending_click.is_empty() or _next >= cues.size():
		return
	if Simulation.scenario != Scenario.LIVING or Simulation.time < float(cues[_next][0]):
		return
	var cue: Array = cues[_next]
	_next += 1
	match String(cue[1]):
		"click":
			_pending_click = cue
		"say":
			_say = cue
			_say_stage = 0
			_say_clock = 0.0
			_typed = 0
			_submitted = ""
			InputInjector.tap(KEY_ENTER)
			print("[living] cue t=T+%06.2f say: Enter" % Simulation.time)
		_:
			push_warning("LivingCuePlayer: unknown cue %s" % [cue])


func _physics_process(_delta: float) -> void:
	if _pending_click.is_empty():
		return
	var cue := _pending_click
	_pending_click = []
	var id := StringName(cue[2])
	var picker := InputInjector.find_picker(get_tree())
	var points := InputInjector.entity_click_points(get_viewport(), id, picker)
	if points.is_empty():
		print("[living] cue t=T+%06.2f click %s: no clickable point — fallback Session.click" % [Simulation.time, id])
		Session.click(id)
		_finish(cue, false)
		return
	_clicked.clear()
	InputInjector.click(points[0])
	print("[living] cue t=T+%06.2f click %s at (%.0f, %.0f) — real input" % [Simulation.time, id, points[0].x, points[0].y])
	_verify_click.call_deferred(cue, 0)


## The Picker resolves clicks in its next physics step: check a few frames later.
func _verify_click(cue: Array, tries: int) -> void:
	var id := StringName(cue[2])
	if _clicked.has(id):
		_finish(cue, true)
		return
	if tries < 6:
		await get_tree().physics_frame
		_verify_click(cue, tries + 1)
		return
	print("[living] cue click %s: the click did not reach the entity — fallback Session.click" % id)
	Session.click(id)
	_finish(cue, false)


func _step_say(delta: float) -> void:
	_say_clock += delta
	var text := String(_say[2])
	match _say_stage:
		0:
			if _say_clock < OPEN_WAIT:
				return
			if not get_viewport().gui_get_focus_owner() is LineEdit:
				print("[living] cue say \"%s\": no call line took the focus — fallback Session.submit_call" % text)
				Session.open_call_line()
				Session.submit_call(text)
				_end_say(false)
				return
			_say_stage = 1
			_say_clock = 0.0
		1:
			while _say_clock >= TYPE_INTERVAL and _typed < text.length():
				_say_clock -= TYPE_INTERVAL
				InputInjector.type_char(text[_typed])
				_typed += 1
			if _typed >= text.length():
				_say_stage = 2
				_say_clock = 0.0
		2:
			if _say_clock < SUBMIT_WAIT:
				return
			InputInjector.tap(KEY_ENTER)
			_say_stage = 3
			_say_clock = 0.0
		3:
			if _say_clock < 0.2:
				return
			if _submitted == text:
				print("[living] cue t=T+%06.2f say \"%s\" — typed and submitted (real input)" % [Simulation.time, text])
				_end_say(true)
			else:
				print("[living] cue say \"%s\": submitted \"%s\" — fallback Session.submit_call" % [text, _submitted])
				Session.submit_call(text)
				_end_say(false)


func _end_say(real: bool) -> void:
	var cue := _say
	_say = []
	_finish(cue, real)


func _finish(cue: Array, real: bool) -> void:
	results.append([cue, real])
	cue_finished.emit(cue, real)
