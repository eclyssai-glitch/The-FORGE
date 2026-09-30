class_name UiQuietSettings
extends VBoxContainer
## GENESIS settings: a small astrolabe sign at the top right that opens a quiet card — graphics
## quality (AUTO / LOW / MEDIUM / HIGH / ULTRA words -> Quality.set_auto / set_level), cinematic
## camera (Session.set_cinematic), three volumes (Master / Ambience / SFX through the static
## AudioDirector.set_bus_volume_db / get_bus_volume_db) and the few keys. Follows
## Quality.profile_changed and Session.cinematic_changed. Opening/closing is a sine fade.

const QUALITY_CHOICES: Array[String] = ["AUTO", "LOW", "MEDIUM", "HIGH", "ULTRA"]
## [bus, word] of each volume slider.
const VOLUMES: Array = [[AudioDirector.BUS_MASTER, "master"], [AudioDirector.BUS_AMBIENCE, "ambience"], [AudioDirector.BUS_SFX, "effects"]]
## Silence floor (dB) of a volume slider at 0.
const SILENT_DB := -80.0
const KEYS := "space  play · pause      h  hide\n1 2 3  modes      v  camera      esc  release"

var toggle_button: UiGlyphButton
var card: PanelContainer
var quality_buttons: Array[Button] = []
var cinematic_button: Button
## Slider per bus name.
var sliders: Dictionary = {}

var _quality_group := ButtonGroup.new()


func _init() -> void:
	name = "GenesisSettings"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 6)
	toggle_button = UiGlyphButton.new(&"settings", "SettingsToggle", 7.0)
	toggle_button.toggle_mode = true
	toggle_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	toggle_button.toggled.connect(set_open)
	add_child(toggle_button)

	card = UiKit.panel(&"Card")
	card.name = "SettingsCard"
	card.custom_minimum_size = Vector2(300, 0)
	card.size_flags_horizontal = Control.SIZE_SHRINK_END
	card.visible = false
	add_child(card)
	var v := UiKit.vbox(10)
	card.add_child(v)

	v.add_child(UiKit.label("quality", &"NoteFaint"))
	var qrow := UiKit.hbox(0)
	qrow.name = "Quality"
	v.add_child(qrow)
	for i in QUALITY_CHOICES.size():
		var b := UiKit.button(QUALITY_CHOICES[i], &"WordButton", true)
		b.name = QUALITY_CHOICES[i].capitalize()
		b.button_group = _quality_group
		b.pressed.connect(_on_quality.bind(i))
		qrow.add_child(b)
		quality_buttons.append(b)

	var crow := UiKit.hbox(8)
	v.add_child(crow)
	var cl := UiKit.label("cinematic camera", &"NoteFaint")
	cl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	crow.add_child(cl)
	cinematic_button = UiKit.button("ON", &"WordButton", true)
	cinematic_button.name = "Cinematic"
	cinematic_button.toggled.connect(_on_cinematic)
	crow.add_child(cinematic_button)

	var grid := GridContainer.new()
	grid.name = "Volumes"
	grid.columns = 2
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 4)
	v.add_child(grid)
	for vol: Array in VOLUMES:
		var l := UiKit.label(String(vol[1]), &"NoteFaint")
		l.custom_minimum_size = Vector2(84, 0)
		grid.add_child(l)
		var s := UiHairlineSlider.new()
		s.name = "Volume_%s" % vol[0]
		s.value = volume_to_slider(AudioDirector.get_bus_volume_db(vol[0]))
		s.value_changed.connect(_on_volume.bind(vol[0]))
		grid.add_child(s)
		sliders[vol[0]] = s

	var keys := UiKit.label(KEYS, &"NoteFaint")
	keys.name = "Keys"
	v.add_child(keys)


func _ready() -> void:
	Quality.profile_changed.connect(func(_p: Dictionary) -> void: refresh())
	Session.cinematic_changed.connect(func(_on: bool) -> void: refresh())
	refresh()


## Slider position (0..1, linear amplitude) of a bus volume in dB.
static func volume_to_slider(db: float) -> float:
	return clampf(db_to_linear(db), 0.0, 1.0) if db > SILENT_DB + 0.5 else 0.0


## Bus volume (dB) of a slider position (0 = silence floor).
static func slider_to_volume(v: float) -> float:
	return maxf(linear_to_db(v), SILENT_DB) if v > 0.0001 else SILENT_DB


func set_open(on: bool) -> void:
	toggle_button.set_pressed_no_signal(on)
	toggle_button.queue_redraw()
	if on:
		for bus: StringName in sliders:
			(sliders[bus] as Range).set_value_no_signal(volume_to_slider(AudioDirector.get_bus_volume_db(bus)))
			(sliders[bus] as Control).queue_redraw()
	UiKit.fade_sine(card, on, Palette.T_BASE if on else Palette.T_FAST)


func is_open() -> bool:
	return card.visible


static func current_choice() -> int:
	return 0 if Quality.auto else int(Quality.level) + 1


func refresh() -> void:
	var c := current_choice()
	for i in quality_buttons.size():
		quality_buttons[i].set_pressed_no_signal(i == c)
	cinematic_button.set_pressed_no_signal(Session.cinematic)
	cinematic_button.text = "ON" if Session.cinematic else "OFF"


func _on_quality(i: int) -> void:
	UiKit.ui_sound(self, &"ui_tick")
	SettingsMenu.choose_quality(i)


func _on_cinematic(on: bool) -> void:
	UiKit.ui_sound(self, &"ui_tick")
	Session.set_cinematic(on)


func _on_volume(v: float, bus: StringName) -> void:
	AudioDirector.set_bus_volume_db(bus, slider_to_volume(v))
