class_name SettingsMenu
extends VBoxContainer
## Top-right SETTINGS toggle and its panel: graphics quality (AUTO / LOW / MEDIUM / HIGH / ULTRA →
## Quality.set_auto / Quality.set_level), cinematic camera on/off (Session.set_cinematic) and the
## keyboard reference. Follows Quality.profile_changed and Session.cinematic_changed.

const QUALITY_CHOICES: Array[String] = ["AUTO", "LOW", "MEDIUM", "HIGH", "ULTRA"]
const KEYS: Array = [
	["SPACE", "START / PAUSE"], ["R", "RESET"], ["1 2 3", "MODES"], ["ESC", "DESELECT"],
	["H", "HIDE HUD"], ["V", "CINEMATIC"], ["C", "RESET VIEW"], ["F11", "FULLSCREEN"],
]

var toggle_button: Button
var panel: PanelContainer
var quality_label: Label
var quality_buttons: Array[Button] = []
var cinematic_button: Button

var _quality_group := ButtonGroup.new()


func _init() -> void:
	name = "Settings"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	alignment = BoxContainer.ALIGNMENT_BEGIN
	add_theme_constant_override("separation", 8)
	toggle_button = UiKit.button("SETTINGS", &"ModeTab", true)
	toggle_button.name = "SettingsToggle"
	toggle_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	toggle_button.toggled.connect(set_open)
	add_child(toggle_button)

	panel = UiKit.panel()
	panel.name = "SettingsPanel"
	panel.custom_minimum_size = Vector2(300, 0)
	panel.size_flags_horizontal = Control.SIZE_SHRINK_END
	panel.visible = false
	add_child(panel)
	var v := UiKit.vbox(8)
	panel.add_child(v)

	var qh := UiKit.header("QUALITY")
	v.add_child(qh[0])
	quality_label = qh[1]
	var qrow := UiKit.hbox(2)
	qrow.name = "Quality"
	v.add_child(qrow)
	for i in QUALITY_CHOICES.size():
		var b := UiKit.button(QUALITY_CHOICES[i], &"Chip", true)
		b.name = QUALITY_CHOICES[i].capitalize()
		b.button_group = _quality_group
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(choose_quality.bind(i))
		qrow.add_child(b)
		quality_buttons.append(b)
	v.add_child(UiKit.separator())

	var ch := UiKit.hbox()
	v.add_child(ch)
	ch.add_child(UiKit.label("CINEMATIC CAMERA", &"Caption"))
	ch.add_child(UiKit.spacer())
	cinematic_button = UiKit.button("ON", &"Chip", true)
	cinematic_button.name = "Cinematic"
	cinematic_button.custom_minimum_size = Vector2(48, 0)
	cinematic_button.toggled.connect(Session.set_cinematic)
	ch.add_child(cinematic_button)
	v.add_child(UiKit.separator())

	v.add_child(UiKit.label("KEYS", &"Caption"))
	var grid := GridContainer.new()
	grid.name = "Keys"
	grid.columns = 4
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for k: Array in KEYS:
		var key := UiKit.label(String(k[0]), &"Data")
		key.custom_minimum_size = Vector2(44, 0)
		grid.add_child(key)
		var what := UiKit.label(String(k[1]), &"DataDim")
		what.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(what)
	v.add_child(grid)


func _ready() -> void:
	Quality.profile_changed.connect(_on_profile_changed)
	Session.cinematic_changed.connect(_on_cinematic_changed)
	refresh()


func set_open(on: bool) -> void:
	toggle_button.set_pressed_no_signal(on)
	UiKit.fade(panel, on, Palette.T_FAST)


func is_open() -> bool:
	return panel.visible


## Index of QUALITY_CHOICES matching the current Quality state (0 = AUTO).
static func current_choice() -> int:
	return 0 if Quality.auto else int(Quality.level) + 1


## Applies choice `i` of QUALITY_CHOICES (0 = AUTO, else a QualityProfiles.Level + 1).
static func choose_quality(i: int) -> void:
	if i <= 0:
		Quality.set_auto(true)
	else:
		Quality.set_level((i - 1) as QualityProfiles.Level)


func refresh() -> void:
	var c := current_choice()
	for i in quality_buttons.size():
		quality_buttons[i].set_pressed_no_signal(i == c)
	quality_label.text = Quality.level_name()
	cinematic_button.set_pressed_no_signal(Session.cinematic)
	cinematic_button.text = "ON" if Session.cinematic else "OFF"


func _on_profile_changed(_p: Dictionary) -> void:
	refresh()


func _on_cinematic_changed(_on: bool) -> void:
	refresh()
