extends Node
## Autoload "Quality": owns the active graphics profile.
## Applies viewport-level settings itself and broadcasts `profile_changed` so the
## environment, lights and effects apply their own parts.
## AUTO mode picks a level from the GPU class and steps down if FPS stays low.

signal profile_changed(profile: Dictionary)

const SETTINGS_PATH := "user://settings.cfg"
const SAMPLE_WINDOW := 4.0
const MAX_AUTO_STEPS := 2

var auto: bool = true
var level: QualityProfiles.Level = QualityProfiles.Level.HIGH
var profile: Dictionary = {}

var _sample_time := 0.0
var _sample_frames := 0
var _auto_steps := 0
var _warmup := 3.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load()
	if auto:
		level = QualityProfiles.detect(RenderingServer.get_video_adapter_type())
	_apply()


func set_level(new_level: QualityProfiles.Level, keep_auto: bool = false) -> void:
	auto = keep_auto
	level = new_level
	_apply()
	_save()


## Forces a level for this run only (command line); nothing is persisted.
func override_for_session(new_level: QualityProfiles.Level) -> void:
	auto = false
	level = new_level
	_apply()


func set_auto(enabled: bool) -> void:
	auto = enabled
	_auto_steps = 0
	if auto:
		level = QualityProfiles.detect(RenderingServer.get_video_adapter_type())
	_apply()
	_save()


func level_name() -> String:
	return ("AUTO · " if auto else "") + QualityProfiles.LEVEL_NAMES[level]


func _process(delta: float) -> void:
	if not auto or _auto_steps >= MAX_AUTO_STEPS or level == QualityProfiles.Level.LOW:
		return
	if _warmup > 0.0:
		_warmup -= delta
		return
	_sample_time += delta
	_sample_frames += 1
	if _sample_time < SAMPLE_WINDOW:
		return
	var fps := _sample_frames / _sample_time
	_sample_time = 0.0
	_sample_frames = 0
	if fps < QualityProfiles.auto_min_fps(DisplayServer.screen_get_refresh_rate()):
		_auto_steps += 1
		level = QualityProfiles.step_down(level)
		print("[Quality] AUTO: %.1f fps, stepping down to %s" % [fps, QualityProfiles.LEVEL_NAMES[level]])
		_apply()
		_warmup = 2.0


func _apply() -> void:
	profile = QualityProfiles.get_profile(level)
	var vp := get_viewport()
	vp.scaling_3d_mode = profile["scaling_mode"]
	vp.scaling_3d_scale = profile["render_scale"]
	vp.msaa_3d = profile["msaa"]
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if profile["fxaa"] else Viewport.SCREEN_SPACE_AA_DISABLED
	vp.positional_shadow_atlas_size = profile["shadow_size"]
	RenderingServer.directional_shadow_atlas_set_size(profile["shadow_size"], true)
	RenderingServer.directional_soft_shadow_filter_set_quality(profile["shadow_filter"])
	RenderingServer.positional_soft_shadow_filter_set_quality(profile["shadow_filter"])
	profile_changed.emit(profile)


func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return
	auto = bool(cfg.get_value("graphics", "auto", true))
	level = clampi(int(cfg.get_value("graphics", "level", level)), 0, QualityProfiles.Level.ULTRA) as QualityProfiles.Level


func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("graphics", "auto", auto)
	cfg.set_value("graphics", "level", int(level))
	cfg.save(SETTINGS_PATH)
