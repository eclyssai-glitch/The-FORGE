class_name QualityProfiles
extends RefCounted
## Graphics quality presets. Pure data; applied by the Quality autoload and by the
## world components that listen to Quality.profile_changed.
## "shadow_splits": cascades of the key DirectionalLight3D (1, 2 or 4), read by the LightRig and
## mapped to DirectionalLight3D.directional_shadow_mode.

enum Level { LOW, MEDIUM, HIGH, ULTRA }

const LEVEL_NAMES: Array[String] = ["LOW", "MEDIUM", "HIGH", "ULTRA"]

## Frames per second below which AUTO steps quality down.
const AUTO_MIN_FPS := 40.0


static func get_profile(level: Level) -> Dictionary:
	match level:
		Level.LOW:
			return {
				"level": level, "name": "LOW",
				"render_scale": 0.77, "scaling_mode": Viewport.SCALING_3D_MODE_FSR,
				"msaa": Viewport.MSAA_DISABLED, "fxaa": true,
				"ssao": false, "ssil": false, "glow": true, "volumetric_fog": false,
				"shadow_size": 2048, "shadows": true, "shadow_splits": 2, "particles": 0.35,
			}
		Level.MEDIUM:
			return {
				"level": level, "name": "MEDIUM",
				"render_scale": 1.0, "scaling_mode": Viewport.SCALING_3D_MODE_BILINEAR,
				"msaa": Viewport.MSAA_2X, "fxaa": false,
				"ssao": true, "ssil": false, "glow": true, "volumetric_fog": true,
				"shadow_size": 2048, "shadows": true, "shadow_splits": 4, "particles": 0.6,
			}
		Level.HIGH:
			return {
				"level": level, "name": "HIGH",
				"render_scale": 1.0, "scaling_mode": Viewport.SCALING_3D_MODE_BILINEAR,
				"msaa": Viewport.MSAA_4X, "fxaa": false,
				"ssao": true, "ssil": false, "glow": true, "volumetric_fog": true,
				"shadow_size": 4096, "shadows": true, "shadow_splits": 4, "particles": 1.0,
			}
		_:
			return {
				"level": Level.ULTRA, "name": "ULTRA",
				"render_scale": 1.0, "scaling_mode": Viewport.SCALING_3D_MODE_BILINEAR,
				"msaa": Viewport.MSAA_4X, "fxaa": false,
				"ssao": true, "ssil": true, "glow": true, "volumetric_fog": true,
				"shadow_size": 4096, "shadows": true, "shadow_splits": 4, "particles": 1.0,
			}


## Initial level from the GPU class reported by the rendering server.
static func detect(adapter_type: RenderingDevice.DeviceType) -> Level:
	match adapter_type:
		RenderingDevice.DEVICE_TYPE_DISCRETE_GPU:
			return Level.HIGH
		RenderingDevice.DEVICE_TYPE_INTEGRATED_GPU, RenderingDevice.DEVICE_TYPE_VIRTUAL_GPU:
			return Level.MEDIUM
		_:
			return Level.LOW


## FPS threshold for AUTO step-down; never above 75% of the display refresh rate,
## so a vsync-capped low-refresh display does not trigger a downgrade.
static func auto_min_fps(refresh_rate: float) -> float:
	if refresh_rate <= 0.0:
		return AUTO_MIN_FPS
	return minf(AUTO_MIN_FPS, refresh_rate * 0.75)


## One step down, never below LOW.
static func step_down(level: Level) -> Level:
	return maxi(int(level) - 1, int(Level.LOW)) as Level
