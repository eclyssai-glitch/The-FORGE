extends Node
## Scripted recording tour of the v0.1.0 video review (docs/contracts/review-video.md).
## Tools only: lives under tools/ (excluded from the export) and never changes the game.
## Recorded by tools/record_review.sh with the Movie Maker (--write-movie, --fixed-fps 30).
##
## Instances res://scenes/main.tscn, forces HIGH quality for this run
## (Quality.override_for_session: AUTO would measure the fixed 30 fps and step down), and plays
## STEPS by GAME time (the sum of `delta`, never the wall clock). Every interaction goes through
## the real input pipeline: keys with Input.parse_input_event (InputEventKey, physical keycodes of
## project.godot), clicks as InputEventMouseButton press/release at the centre of the real HUD
## controls, the timeline drag and the orbit as press + InputEventMouseMotion + release. The
## phase captions of the demo enter with Simulation.event_emitted.
## Overlay (CanvasLayer OVERLAY_LAYER, above the HUD and the entry fade; nothing catches the
## mouse): lower-third caption centred in the free lane above the transport, full-screen title /
## verdict cards, and a discreet BONE ring at the pointer with a pulse on each click.
## Colours only from Palette (BONE / TEXT_DIM on PANEL / VOID; never EMBER or PALE); Inter for
## text, IBM Plex Mono for labels (UiTheme fonts).
## User args (after `--`): --review-until=<s> stops the tour early (short validation recordings).
## Prints one `[review] ...` line per step and `[review] done ...` just before get_tree().quit().

const MainScene := preload("res://scenes/main.tscn")

const OVERLAY_LAYER := 110
## Seconds between press and release of a click / tap.
const CLICK_HOLD := 0.1
const KEY_TAP := 0.08
## The pointer ring stays this long after the last pointer activity, then fades (RING_FADE).
const RING_LINGER := 1.4
const RING_FADE := 0.4
const PULSE_TIME := 0.5
## Caption cross-fade: out, then in (seconds).
const CAPTION_OUT := 0.2
const CAPTION_IN := 0.35
## Card fades (seconds).
const CARD_IN := 0.8
const CARD_OUT := 0.7
## Reference height of the layout sizes below (px at 1600×900; everything scales with height).
const SNAP_AFTER := 0.9
const REF_HEIGHT := 900.0
const CAPTION_MAX_W := 880.0

const TITLE := "KORIUM UNIVERSE"
const SUBTITLE := "v0.1.0 — Review"
const TITLE_META := "Godot 4.7 · Windows · DEMO MODE"

const TXT_UNIVERSE := "Um universo onde agentes e projetos viram estruturas vivas. Nesta versão, tudo é simulado e local — nada se conecta a lugar nenhum."
const TXT_FORGE := "FORGE: a ORIGIN CHAMBER, onde o primeiro construto nasce."
const TXT_TIME := "Tudo é função do tempo da simulação: pausar, voltar e avançar reconstrói o mundo exatamente."
const TXT_INSPECT := "Qualquer entidade pode ser inspecionada e enquadrada."
const TXT_OBSERVATORY := "OBSERVATORY: missão, verificações e o log completo — dados simulados, locais e determinísticos."
const TXT_SEEDS := "As sementes dormentes guardam lugar para os próximos construtos."
const TXT_HUD := "Com o HUD oculto, só o selo DEMO MODE permanece."

## Phase captions of step 3, keyed by event type (LAYER_ADDED only for the first layer).
const PHASE_CAPTIONS := {
	SimEvent.CORE_ACTIVATION: ["ATIVAÇÃO", "O núcleo desperta. O âmbar só aparece onde há energia."],
	SimEvent.FRAGMENTS_EMITTED: ["FRAGMENTOS", "96 fragmentos se soltam do núcleo."],
	SimEvent.LAYER_ADDED: ["CAMADAS", "Cinco anéis se montam, um evento de cada vez."],
	SimEvent.MATERIALS_APPLIED: ["MATERIAIS · LUZ", "Os fragmentos brutos viram metal; a luz da câmara sobe com a história."],
	SimEvent.VERIFICATION_STARTED: ["VERIFICAÇÃO", "Uma varredura clara executa quatro checagens simuladas."],
	SimEvent.STRUCTURE_FINALIZED: ["FORMA FINAL", "Forma final: as colunas travam a estrutura."],
}

const PROS: Array[String] = [
	"direção visual coesa e original", "construção legível em 7 fases", "pausa/seek exatos",
	"UI nativa clara", "100% offline",
]
const CONS: Array[String] = [
	"conteúdo curto (uma demo de 50 s)", "sem áudio", "ainda não há decisões do jogador",
	"execução nativa no Windows por validar",
]
const VERDICT := "Veredito: fatia vertical promissora — 7/10 como protótipo."

## Every HUD control the tour clicks (resolved by target_control()).
const TARGETS: Array[StringName] = [
	&"tab_forge", &"start", &"pause", &"timeline", &"row_layer_iii", &"focus", &"speed_2",
	&"row_seed_aurel",
]

## When false (tests), the tour only builds the scene and the overlay: no quality override, no steps.
var autorun := true
## Game seconds after which the tour ends (< 0 = run every step).
var until := -1.0

var main: Node
var hud: Hud
## Game time of the tour (sum of delta).
var time := 0.0

var _steps: Array[Dictionary] = []
var _next := 0
var _frames := 0
var _finished := false
## Timed input to send later: [{"t": float, "event": InputEvent}] (releases).
var _pending: Array[Dictionary] = []
## Running pointer gesture (move / drag / orbit), or {}.
var _gesture: Dictionary = {}
var _pointer := Vector2(-1, -1)
var _pointer_seen := false
var _pointer_last := -100.0
var _pointer_alpha := 0.0
var _pulses: Array[Vector3] = []
var _phase_captions := false
## --review-snap=<dir> (debug, without the Movie Maker): PNG of the viewport SNAP_AFTER s after
## each caption / card / click step, to inspect the tour quickly. "" = off.
var _snap_dir := ""
var _snaps: Array[Dictionary] = []

var _layer: CanvasLayer
var _overlay: Control
var _caption: PanelContainer
var _cap_label: Label
var _cap_text: Label
var _cap_alpha := 0.0
var _cap_want := false
## Caption waiting for the current one to fade out: [label, text], or [].
var _cap_next: Array = []
var _pointer_canvas: Control
var _cards: Dictionary = {}
## Per card: {"shown": float, "hidden": float} (game time; hidden < 0 = still shown).
var _card_state: Dictionary = {}


## The tour, in game seconds. `t` is non-decreasing (tests check it). Actions:
##   card / card_hide · caption / caption_clear · phase_captions (on) · key (key, hold)
##   move (target | at, dur) · click (target) · drag_timeline (to, dur) · orbit (dx, dur) · quit
## `at` is a point in viewport fractions. Pause lands before the demo ends (T+50), so PAUSE exists.
static func steps() -> Array[Dictionary]:
	return [
		# 0 — title card; behind it, key 1 takes the game to UNIVERSE so the shot is settled.
		{"t": 0.0, "do": &"card", "card": &"title"},
		{"t": 0.4, "do": &"key", "key": KEY_1},
		{"t": 4.3, "do": &"card_hide", "card": &"title"},
		# 1 — UNIVERSE.
		{"t": 5.0, "do": &"caption", "label": "UNIVERSE", "text": TXT_UNIVERSE},
		# 2 — FORGE tab.
		{"t": 13.2, "do": &"move", "target": &"tab_forge", "dur": 0.8},
		{"t": 14.0, "do": &"click", "target": &"tab_forge"},
		{"t": 14.0, "do": &"caption", "label": "FORGE", "text": TXT_FORGE},
		# 3 — START, the whole construction at 1× with the cinematic camera.
		{"t": 17.6, "do": &"move", "target": &"start", "dur": 0.9},
		{"t": 18.6, "do": &"caption_clear"},
		{"t": 18.6, "do": &"phase_captions", "on": true},
		{"t": 19.0, "do": &"click", "target": &"start"},
		# 4 — PAUSE at ~T+48 (after the final form), drag back to T+20, LAYER III, FOCUS, 2×.
		{"t": 66.4, "do": &"move", "target": &"pause", "dur": 0.6},
		{"t": 67.0, "do": &"click", "target": &"pause"},
		{"t": 67.0, "do": &"phase_captions", "on": false},
		{"t": 67.0, "do": &"caption", "label": "TIMELINE", "text": TXT_TIME},
		{"t": 68.2, "do": &"move", "target": &"timeline", "dur": 0.7},
		{"t": 69.0, "do": &"drag_timeline", "to": 20.0, "dur": 1.6},
		{"t": 71.2, "do": &"move", "target": &"row_layer_iii", "dur": 0.7},
		{"t": 72.0, "do": &"click", "target": &"row_layer_iii"},
		{"t": 72.0, "do": &"caption", "label": "INSPECTOR", "text": TXT_INSPECT},
		{"t": 73.4, "do": &"move", "target": &"focus", "dur": 0.7},
		{"t": 74.2, "do": &"click", "target": &"focus"},
		{"t": 76.4, "do": &"move", "target": &"speed_2", "dur": 0.7},
		{"t": 77.2, "do": &"click", "target": &"speed_2"},
		{"t": 77.8, "do": &"move", "target": &"start", "dur": 0.6},
		{"t": 78.4, "do": &"click", "target": &"start"},
		# 5 — OBSERVATORY while the demo reaches its end (T+50 at 2× ≈ 93.4 s).
		{"t": 83.0, "do": &"key", "key": KEY_3},
		{"t": 83.0, "do": &"caption", "label": "OBSERVATORY", "text": TXT_OBSERVATORY},
		# 6 — UNIVERSE, SEED · AUREL, FOCUS, a short WASD flight.
		{"t": 95.0, "do": &"key", "key": KEY_1},
		{"t": 95.0, "do": &"caption", "label": "UNIVERSE · SEEDS", "text": TXT_SEEDS},
		{"t": 96.2, "do": &"move", "target": &"row_seed_aurel", "dur": 0.8},
		{"t": 97.0, "do": &"click", "target": &"row_seed_aurel"},
		{"t": 99.4, "do": &"move", "target": &"focus", "dur": 0.8},
		{"t": 100.2, "do": &"click", "target": &"focus"},
		{"t": 103.2, "do": &"key", "key": KEY_W, "hold": 1.2},
		{"t": 104.8, "do": &"key", "key": KEY_D, "hold": 1.0},
		# 7 — FORGE, H hides the HUD, slow orbit drag over the world.
		{"t": 109.0, "do": &"key", "key": KEY_2},
		{"t": 109.0, "do": &"caption_clear"},
		{"t": 110.0, "do": &"key", "key": KEY_H},
		{"t": 110.2, "do": &"caption", "label": "HUD", "text": TXT_HUD},
		{"t": 110.8, "do": &"move", "at": Vector2(0.56, 0.5), "dur": 0.6},
		{"t": 111.6, "do": &"orbit", "dx": -0.11, "dur": 4.4},
		# 8 — verdict card.
		{"t": 117.0, "do": &"caption_clear"},
		{"t": 117.0, "do": &"card", "card": &"verdict"},
		{"t": 133.0, "do": &"quit"},
	]


## Phase caption [label, text] for a demo event, or [] (LAYER_ADDED: first layer only).
static func phase_caption(e: SimEvent) -> Array:
	if not PHASE_CAPTIONS.has(e.type):
		return []
	if e.type == SimEvent.LAYER_ADDED and int(e.payload.get("layer", -1)) != 0:
		return []
	return PHASE_CAPTIONS[e.type]


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if autorun:
		Quality.override_for_session(QualityProfiles.Level.HIGH)
		var args := _parse_args(OS.get_cmdline_user_args())
		if args.has("review-until"):
			until = String(args["review-until"]).to_float()
		if args.has("review-snap"):
			_snap_dir = String(args["review-snap"])
			DirAccess.make_dir_recursive_absolute(_snap_dir)
	main = MainScene.instantiate()
	add_child(main)
	hud = main.get_node(^"HUD") as Hud
	_build_overlay()
	Simulation.event_emitted.connect(_on_event)
	_steps = steps()
	set_process(autorun)
	if autorun:
		print("[review] start quality=%s until=%s movie=%s size=%s" % [Quality.level_name(),
			str(until) if until >= 0.0 else "end", Engine.get_write_movie_path(), _view_size()])


func _process(delta: float) -> void:
	if _finished:
		return
	time += delta
	_frames += 1
	if until >= 0.0 and time >= until:
		_finish("until")
		return
	while _next < _steps.size() and time >= float(_steps[_next]["t"]):
		_run(_steps[_next])
		_next += 1
		if _finished:
			return
	_update_gesture()
	_flush_pending()
	_update_caption(delta)
	_update_cards()
	_update_pointer()
	_take_snaps()


func _take_snaps() -> void:
	if _snaps.is_empty() or time < float(_snaps[0]["t"]):
		return
	var snap: Dictionary = _snaps.pop_front()
	var path := _snap_dir.path_join(String(snap["name"]))
	get_viewport().get_texture().get_image().save_png(path)
	print("[review] snap %s" % path)


# --- Steps -------------------------------------------------------------------------------------

func _run(s: Dictionary) -> void:
	var what: StringName = s["do"]
	match what:
		&"card":
			_card_state[s["card"]] = {"shown": time, "hidden": -1.0}
		&"card_hide":
			if _card_state.has(s["card"]):
				_card_state[s["card"]]["hidden"] = time
		&"caption":
			_set_caption(String(s["label"]), String(s["text"]))
		&"caption_clear":
			_set_caption("", "")
		&"phase_captions":
			_phase_captions = bool(s["on"])
		&"key":
			_send_key(int(s["key"]) as Key, true)
			_later(float(s.get("hold", KEY_TAP)), _key_event(int(s["key"]) as Key, false))
		&"move":
			var to := _step_point(s)
			_gesture = {"kind": &"move", "from": _pointer_or(to), "to": to, "t0": time,
				"dur": float(s["dur"]), "target": s.get("target", &"")}
		&"click":
			_click(target_point(s["target"]))
		&"drag_timeline":
			var from := target_point(&"timeline")
			var tl := target_control(&"timeline") as TimelineBar
			var to := _to_viewport(tl, Vector2(tl.x_at(float(s["to"])), tl.size.y * 0.5))
			_move_pointer(from, 0)
			_send_button(from, true)
			_gesture = {"kind": &"drag", "from": from, "to": to, "t0": time, "dur": float(s["dur"])}
		&"orbit":
			var from := _pointer_or(_view_size() * 0.5)
			var to := from + Vector2(float(s["dx"]) * _view_size().x, 0.0)
			_send_button(from, true)
			_gesture = {"kind": &"drag", "from": from, "to": to, "t0": time, "dur": float(s["dur"])}
		&"quit":
			_finish("end")
			return
	if _snap_dir != "" and what in [&"caption", &"card", &"click", &"orbit"]:
		_snaps.append({"t": time + SNAP_AFTER, "name": "%03d_%05.1f_%s.png" % [_next, time, what]})
	print("[review] t=%6.2f %-14s %-14s mode=%s sim=%s T+%04.1f sel=%s hud=%s" % [time, what,
		String(s.get("target", s.get("card", s.get("label", "")))), Session.mode_name(),
		EventTimeline.Status.keys()[Simulation.status], Simulation.time, Session.selected, Session.hud_visible])


func _finish(reason: String) -> void:
	_finished = true
	print("[review] done reason=%s t=%.2f frames=%d sim=T+%04.1f mode=%s size=%s" % [reason, time, _frames,
		Simulation.time, Session.mode_name(), _view_size()])
	get_tree().quit()


func _on_event(e: SimEvent) -> void:
	if not _phase_captions:
		return
	var c := phase_caption(e)
	if not c.is_empty():
		_set_caption("%s · %s" % [e.format_time(), c[0]], c[1])


# --- Targets -----------------------------------------------------------------------------------

## The real HUD control behind a tour target (found by the node names of src/ui), or null.
func target_control(id: StringName) -> Control:
	if hud == null:
		return null
	var transport := _transport()
	match id:
		&"tab_forge":
			var bar := hud.find_child("ModeBar", true, false)
			return bar.get_node_or_null(NodePath(SessionState.MODE_NAMES[SessionState.Mode.FORGE].capitalize())) as Control if bar else null
		&"start", &"pause":
			return transport.find_child(String(id).capitalize(), true, false) as Control if transport else null
		&"timeline":
			return transport.find_child("Timeline", true, false) as Control if transport else null
		&"speed_2":
			var n := "Speed_%s" % str(2.0).replace(".", "_")
			return transport.find_child(n, true, false) as Control if transport else null
		&"row_layer_iii":
			var fp := hud.find_child("ForgePanel", true, false)
			return fp.find_child("Row_" + String(OriginChamberScript.layer_entity(2)), true, false) as Control if fp else null
		&"row_seed_aurel":
			var up := hud.find_child("UniversePanel", true, false)
			return up.find_child("Row_seed_aurel", true, false) as Control if up else null
		&"focus":
			var ins := hud.find_child("Inspector", true, false)
			return ins.find_child("Focus", true, false) as Control if ins else null
	return null


## Viewport point to press for a target: the control's centre; the timeline's playhead.
func target_point(id: StringName) -> Vector2:
	var c := target_control(id)
	if c == null:
		push_warning("review: target %s not found" % id)
		return _view_size() * 0.5
	if c is TimelineBar:
		var tl := c as TimelineBar
		return _to_viewport(tl, Vector2(tl.x_at(Simulation.time), tl.size.y * 0.5))
	return _to_viewport(c, c.size * 0.5)


func _transport() -> Control:
	for n in get_tree().get_nodes_in_group(Transport.GROUP):
		if main and main.is_ancestor_of(n):
			return n as Control
	return null


func _step_point(s: Dictionary) -> Vector2:
	if s.has("target"):
		return target_point(s["target"])
	var at: Vector2 = s["at"]
	return at * _view_size()


static func _to_viewport(c: Control, local: Vector2) -> Vector2:
	return c.get_global_transform_with_canvas() * local


func _view_size() -> Vector2:
	return get_viewport().get_visible_rect().size


# --- Input (real pipeline: Input.parse_input_event) -------------------------------------------

func _key_event(code: Key, pressed: bool) -> InputEventKey:
	var k := InputEventKey.new()
	k.keycode = code
	k.physical_keycode = code
	k.key_label = code
	k.pressed = pressed
	return k


func _send_key(code: Key, pressed: bool) -> void:
	Input.parse_input_event(_key_event(code, pressed))


func _later(after: float, ev: InputEvent) -> void:
	_pending.append({"t": time + after, "event": ev})


func _flush_pending() -> void:
	var keep: Array[Dictionary] = []
	for p in _pending:
		if time >= float(p["t"]):
			var ev := p["event"] as InputEvent
			if ev is InputEventMouseButton:
				_pointer_touch()
			Input.parse_input_event(ev)
		else:
			keep.append(p)
	_pending = keep


func _window_pos(p: Vector2) -> Vector2:
	return get_viewport().get_final_transform() * p


func _move_pointer(to: Vector2, mask: int) -> void:
	var from := _pointer_or(to)
	var ev := InputEventMouseMotion.new()
	var w := _window_pos(to)
	ev.position = w
	ev.global_position = w
	ev.relative = w - _window_pos(from)
	ev.screen_relative = ev.relative
	ev.button_mask = mask
	Input.parse_input_event(ev)
	_pointer = to
	_pointer_seen = true
	_pointer_touch()


func _button_event(at: Vector2, pressed: bool) -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	var w := _window_pos(at)
	ev.position = w
	ev.global_position = w
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = pressed
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	return ev


func _send_button(at: Vector2, pressed: bool) -> void:
	Input.parse_input_event(_button_event(at, pressed))
	_pointer_touch()
	if pressed:
		_pulses.append(Vector3(at.x, at.y, time))


func _click(at: Vector2) -> void:
	_gesture = {}
	if not _pointer_seen or _pointer.distance_to(at) > 0.5:
		_move_pointer(at, 0)
	_send_button(at, true)
	_later(CLICK_HOLD, _button_event(at, false))


func _update_gesture() -> void:
	if _gesture.is_empty():
		return
	var dur := maxf(float(_gesture["dur"]), 0.001)
	var u := clampf((time - float(_gesture["t0"])) / dur, 0.0, 1.0)
	var to: Vector2 = _gesture["to"]
	if _gesture["kind"] == &"move" and StringName(_gesture["target"]) != &"":
		to = target_point(_gesture["target"])  # follows layout changes (e.g. Start/Pause slot)
	var from: Vector2 = _gesture["from"]
	var p := from.lerp(to, ease_in_out(u))
	var dragging: bool = _gesture["kind"] == &"drag"
	if p.distance_to(_pointer) > 0.01:
		_move_pointer(p, MOUSE_BUTTON_MASK_LEFT if dragging else 0)
	if u >= 1.0:
		if dragging:
			_send_button(p, false)
		_gesture = {}


static func ease_in_out(u: float) -> float:
	return 0.5 - 0.5 * cos(PI * clampf(u, 0.0, 1.0))


func _pointer_or(fallback: Vector2) -> Vector2:
	return _pointer if _pointer_seen else fallback


func _pointer_touch() -> void:
	_pointer_last = time


# --- Overlay -----------------------------------------------------------------------------------

func _scale() -> float:
	return maxf(_view_size().y / REF_HEIGHT, 0.4)


func _px(v: float) -> int:
	return maxi(int(round(v * _scale())), 1)


func _label(text: String, font: Font, size: float, color: Color, align := HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.horizontal_alignment = align
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", _px(size))
	l.add_theme_color_override("font_color", color)
	return l


func _build_overlay() -> void:
	_layer = CanvasLayer.new()
	_layer.name = "ReviewOverlay"
	_layer.layer = OVERLAY_LAYER
	add_child(_layer)
	_overlay = Control.new()
	_overlay.name = "Root"
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.theme = UiTheme.get_theme()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_layer.add_child(_overlay)

	_caption = PanelContainer.new()
	_caption.name = "Caption"
	_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_caption.add_theme_stylebox_override("panel", UiTheme.box(Palette.PANEL, Palette.PANEL_LINE, Vector4i.ONE,
		_px(22), _px(12)))
	_caption.modulate.a = 0.0
	_caption.visible = false
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", _px(5))
	_caption.add_child(v)
	_cap_label = _label("", UiTheme.font_mono(), 12, Palette.TEXT_DIM)
	v.add_child(_cap_label)
	_cap_text = _label("", UiTheme.font_sans(420), 21, Palette.BONE)
	_cap_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_cap_text)
	_overlay.add_child(_caption)

	_pointer_canvas = Control.new()
	_pointer_canvas.name = "Pointer"
	_pointer_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pointer_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pointer_canvas.draw.connect(_draw_pointer)
	_overlay.add_child(_pointer_canvas)

	_cards[&"title"] = _build_title_card()
	_cards[&"verdict"] = _build_verdict_card()
	for c: Control in _cards.values():
		c.visible = false
		c.modulate.a = 0.0
		_overlay.add_child(c)


func _card_base(card_name: String, backdrop: Color) -> Array:
	var card := Control.new()
	card.name = card_name
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.name = "Backdrop"
	bg.color = backdrop
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	card.add_child(bg)
	var center := CenterContainer.new()
	center.name = "Center"
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	card.add_child(center)
	return [card, center]


func _build_title_card() -> Control:
	var base := _card_base("TitleCard", Palette.VOID)
	var v := VBoxContainer.new()
	v.name = "Content"
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", _px(14))
	(base[1] as Control).add_child(v)
	v.add_child(_label(TITLE, UiTheme.font_sans(300, _px(10)), 60, Palette.BONE))
	v.add_child(_label(SUBTITLE, UiTheme.font_sans(420), 22, Palette.BONE))
	var rule := ColorRect.new()
	rule.color = Palette.LINE_STRONG
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rule.custom_minimum_size = Vector2(_px(120), 1)
	rule.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(rule)
	v.add_child(_label(TITLE_META, UiTheme.font_mono(), 14, Palette.TEXT_DIM))
	return base[0]


func _build_verdict_card() -> Control:
	var base := _card_base("VerdictCard", Color(Palette.VOID, 0.9))
	var panel := PanelContainer.new()
	panel.name = "Content"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", UiTheme.box(Palette.PANEL, Palette.PANEL_LINE, Vector4i.ONE,
		_px(40), _px(32)))
	(base[1] as Control).add_child(panel)
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", _px(22))
	panel.add_child(v)
	v.add_child(_label("%s · %s" % [TITLE, SUBTITLE], UiTheme.font_mono(), 13, Palette.TEXT_DIM, HORIZONTAL_ALIGNMENT_LEFT))
	var cols := HBoxContainer.new()
	cols.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cols.add_theme_constant_override("separation", _px(56))
	v.add_child(cols)
	cols.add_child(_verdict_column("PRÓS", PROS))
	cols.add_child(_verdict_column("CONTRAS", CONS))
	var rule := ColorRect.new()
	rule.color = Palette.PANEL_LINE
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rule.custom_minimum_size = Vector2(0, 1)
	v.add_child(rule)
	v.add_child(_label(VERDICT, UiTheme.font_sans(500), 27, Palette.BONE, HORIZONTAL_ALIGNMENT_LEFT))
	return base[0]


func _verdict_column(header: String, items: Array[String]) -> Control:
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", _px(9))
	col.add_child(_label(header, UiTheme.font_mono(true), 13, Palette.TEXT_DIM, HORIZONTAL_ALIGNMENT_LEFT))
	for it in items:
		col.add_child(_label("·  " + it, UiTheme.font_sans(420), 19, Palette.BONE, HORIZONTAL_ALIGNMENT_LEFT))
	return col


func _set_caption(label: String, text: String) -> void:
	if text == "":
		_cap_want = false
		_cap_next = []
		return
	_cap_want = true
	if _caption.visible and _cap_alpha > 0.0 and _cap_text.text != text:
		_cap_next = [label, text]
	else:
		_cap_next = []
		_apply_caption_text(label, text)


func _apply_caption_text(label: String, text: String) -> void:
	_cap_label.text = label
	_cap_label.visible = label != ""
	_cap_text.text = text


func _update_caption(delta: float) -> void:
	if not _cap_next.is_empty():
		_cap_alpha = maxf(_cap_alpha - delta / CAPTION_OUT, 0.0)
		if _cap_alpha <= 0.0:
			_apply_caption_text(String(_cap_next[0]), String(_cap_next[1]))
			_cap_next = []
	elif _cap_want:
		_cap_alpha = minf(_cap_alpha + delta / CAPTION_IN, 1.0)
	else:
		_cap_alpha = maxf(_cap_alpha - delta / CAPTION_OUT, 0.0)
	_caption.visible = _cap_alpha > 0.0 or (_cap_want and _cap_next.is_empty())
	_caption.modulate.a = _cap_alpha
	if _caption.visible:
		_layout_caption()


## Places the caption above the transport, centred on the screen when it fits; otherwise inside
## the free lane left by the HUD blocks that reach its band (OBSERVATORY sheet, feed, inspector).
func _layout_caption() -> void:
	var view := _view_size()
	var edge := float(Palette.UI_EDGE)
	var gap := float(Palette.UI_GAP) * 2.0
	var bottom := view.y - edge - _px(20)
	var transport := _transport()
	var chrome_on := hud.chrome.visible and hud.chrome.modulate.a > 0.05
	if chrome_on and transport and transport.is_visible_in_tree():
		bottom = _to_viewport(transport, Vector2.ZERO).y - gap
	var left := edge
	var right := view.x - edge
	var band_top := bottom - _px(120)
	if chrome_on:
		for c: Control in [hud.observatory_panel, hud.feed, hud.inspector]:
			if not c.is_visible_in_tree() or c.modulate.a < 0.05:
				continue
			var r := Rect2(_to_viewport(c, Vector2.ZERO), c.size)
			if r.end.y < band_top or r.position.y > bottom:
				continue
			if r.get_center().x < view.x * 0.5:
				left = maxf(left, r.end.x + gap)
			else:
				right = minf(right, r.position.x - gap)
	var lane := maxf(right - left, float(_px(240)))
	var pad := float(_px(22)) * 2.0 + 2.0
	var font := _cap_text.get_theme_font("font")
	var fs := _cap_text.get_theme_font_size("font_size")
	var text_w := font.get_string_size(_cap_text.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 2.0
	# Width available while staying centred on the screen; the whole lane only when that is narrow.
	var centred := 2.0 * minf(view.x * 0.5 - left, right - view.x * 0.5)
	var room := centred if centred >= minf(text_w + pad, CAPTION_MAX_W * _scale()) else lane
	var inner := minf(text_w, minf(room, CAPTION_MAX_W * _scale()) - pad)
	if not is_equal_approx(_cap_text.custom_minimum_size.x, inner):
		_cap_text.custom_minimum_size.x = inner
	_caption.reset_size()
	var box := _caption.size
	var x := clampf(view.x * 0.5 - box.x * 0.5, left, maxf(left, right - box.x))
	_caption.position = Vector2(roundf(x), roundf(bottom - box.y))


func _update_cards() -> void:
	for id: StringName in _cards:
		var card: Control = _cards[id]
		var a := 0.0
		if _card_state.has(id):
			var st: Dictionary = _card_state[id]
			var shown := float(st["shown"])
			var hidden := float(st["hidden"])
			if id == &"title":
				# The VOID backdrop is there from the first frame; the words fade in over it.
				a = 1.0
				var words := clampf((time - shown - 0.3) / CARD_IN, 0.0, 1.0)
				(card.get_node(^"Center/Content") as Control).modulate.a = words
			else:
				a = clampf((time - shown) / CARD_IN, 0.0, 1.0)
			if hidden >= 0.0:
				a *= 1.0 - clampf((time - hidden) / CARD_OUT, 0.0, 1.0)
		card.modulate.a = a
		card.visible = a > 0.0


func _cards_covering() -> bool:
	for c: Control in _cards.values():
		if c.visible and c.modulate.a > 0.5:
			return true
	return false


func _update_pointer() -> void:
	var idle := time - _pointer_last - RING_LINGER
	var want := 1.0 - clampf(idle / RING_FADE, 0.0, 1.0) if _pointer_seen else 0.0
	if _cards_covering():
		want = 0.0
	var alive: Array[Vector3] = []
	for p in _pulses:
		if time - p.z < PULSE_TIME:
			alive.append(p)
	_pulses = alive
	if want != _pointer_alpha or not _pulses.is_empty() or want > 0.0:
		_pointer_alpha = want
		_pointer_canvas.queue_redraw()


func _draw_pointer() -> void:
	var s := _scale()
	var w := maxf(1.5 * s, 1.0)
	if _pointer_alpha > 0.0:
		_pointer_canvas.draw_arc(_pointer, 11.0 * s, 0.0, TAU, 48, Color(Palette.BONE, 0.85 * _pointer_alpha), w, true)
		_pointer_canvas.draw_circle(_pointer, 2.0 * s, Color(Palette.BONE, 0.9 * _pointer_alpha), true, -1.0, true)
	for p in _pulses:
		var u := clampf((time - p.z) / PULSE_TIME, 0.0, 1.0)
		var r := (11.0 + 18.0 * u) * s
		_pointer_canvas.draw_arc(Vector2(p.x, p.y), r, 0.0, TAU, 48, Color(Palette.BONE, 0.7 * (1.0 - u)), w, true)


static func _parse_args(raw: PackedStringArray) -> Dictionary:
	var out := {}
	for a in raw:
		if not a.begins_with("--"):
			continue
		var kv := a.substr(2).split("=", true, 1)
		out[kv[0]] = kv[1] if kv.size() > 1 else true
	return out
