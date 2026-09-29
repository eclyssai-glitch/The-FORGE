class_name Transport
extends PanelContainer
## Demo transport (group "ui_transport"): Start / Pause / Reset buttons (node names are a contract
## with the smoke test), the draggable timeline with phase ticks, time `T+00.0 / 50.0`, current
## phase and playback speed (0.5× 1× 2× 4×). Start and Pause share one slot: only the useful one
## is shown. Text is refreshed by the HUD at Palette.T_UI_REFRESH (refresh()), never per frame.

const GROUP := &"ui_transport"
const SPEEDS: Array[float] = [0.5, 1.0, 2.0, 4.0]

var start_button: Button
var pause_button: Button
var reset_button: Button
var timeline: TimelineBar
var time_label: Label
var phase_label: Label
var speed_buttons: Array[Button] = []

var _speed_group := ButtonGroup.new()


func _init() -> void:
	name = "Transport"
	theme_type_variation = &"HudPanel"
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_to_group(GROUP)
	add_theme_stylebox_override("panel", UiTheme.box(Palette.PANEL, Palette.PANEL_LINE, Vector4i.ONE, 12, 8))
	var row := UiKit.hbox(10)
	add_child(row)

	start_button = UiKit.button("START", &"TransportButton")
	start_button.name = "Start"
	start_button.custom_minimum_size = Vector2(84, 0)
	start_button.pressed.connect(Simulation.start)
	row.add_child(start_button)
	pause_button = UiKit.button("PAUSE", &"TransportButton")
	pause_button.name = "Pause"
	pause_button.custom_minimum_size = Vector2(84, 0)
	pause_button.pressed.connect(Simulation.pause)
	row.add_child(pause_button)
	reset_button = UiKit.button("RESET", &"TransportButton")
	reset_button.name = "Reset"
	reset_button.pressed.connect(Simulation.reset)
	row.add_child(reset_button)

	time_label = UiKit.label("", &"Data")
	time_label.name = "Time"
	time_label.custom_minimum_size = Vector2(118, 0)
	time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(time_label)

	timeline = TimelineBar.new()
	row.add_child(timeline)

	phase_label = UiKit.label("", &"Title")
	phase_label.name = "Phase"
	phase_label.custom_minimum_size = Vector2(120, 0)
	phase_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(phase_label)

	var speeds := UiKit.hbox(2)
	speeds.name = "Speed"
	row.add_child(speeds)
	for s in SPEEDS:
		var b := UiKit.button(speed_text(s), &"Chip", true)
		b.name = "Speed_%s" % str(s).replace(".", "_")
		b.button_group = _speed_group
		b.pressed.connect(Simulation.set_speed.bind(s))
		speeds.add_child(b)
		speed_buttons.append(b)


func _ready() -> void:
	Simulation.playback_changed.connect(_on_playback_changed)
	Simulation.world_rebuilt.connect(refresh)
	refresh()


static func speed_text(s: float) -> String:
	return ("%.1f×" % s) if s < 1.0 else ("%d×" % int(s))


## "T+12.3 / 50.0"
static func time_text(t: float, duration: float) -> String:
	return "T+%04.1f / %04.1f" % [t, duration]


static func start_text(status: EventTimeline.Status) -> String:
	match status:
		EventTimeline.Status.PAUSED:
			return "RESUME"
		EventTimeline.Status.COMPLETE:
			return "REPLAY"
	return "START"


func refresh() -> void:
	var text := time_text(Simulation.time, Simulation.duration())
	if time_label.text != text:
		time_label.text = text
	var phase := Simulation.world.phase_name()
	if phase_label.text != phase:
		phase_label.text = phase
	var speed := Simulation.timeline.speed
	for i in SPEEDS.size():
		speed_buttons[i].set_pressed_no_signal(is_equal_approx(SPEEDS[i], speed))
	_on_playback_changed(Simulation.status)


func _on_playback_changed(status: EventTimeline.Status) -> void:
	var playing := status == EventTimeline.Status.PLAYING
	start_button.visible = not playing
	pause_button.visible = playing
	start_button.text = start_text(status)
