// KORIUM UNIVERSE — angelic hand (living prototype, Loop 5). Owner: art-director.
// One family for every hand MIKU commands (1, 2, 4, 6...): the function of a hand comes from its
// animation, never from its look. Luminous pearl / ivory porcelain, translucent: a wide soft
// specular, light passing through thin parts (BACKLIGHT, BLUSH), a soft cool rim that draws the form
// against the night, and an inner light seen a little *inside* the porcelain (parallax along the
// view ray). `drive` 0..1 = how hard MIKU is pulling this hand right now (the tension of its thread):
// at rest the inner light is a faint cool pearl; under tension it gathers into soft filaments of
// warm pale gold that flow along `flow_axis` (energy arriving through the thread) and the rim
// tightens; released, it cools back to pearl. Nothing blinks: the animator eases `drive`.
// `presence` 0..1 summons / dismisses the hand: it condenses radially from `presence_origin`
// (object space, e.g. the palm) in fine grains with a warm lip — never a pop. The optional wrist
// dissolve is the same contract as hand_stone (MaterialLibrary.set_hand_wrist).
// Scales follow `hand_size` (object units from wrist to fingertip), so any HandRig scale works.
// Skinned meshes: patterns live in (skinned) object space and are kept low-frequency and soft so
// that fingers moving through them read as light inside, not as a sliding texture.
// Vertex colour red = baked AO (white when the mesh has none). No UVs needed. No TIME.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://src/style/shaders/genesis/noise.gdshaderinc"

uniform vec3 pearl_color : source_color;
uniform vec3 ivory_color : source_color;
// Light through the porcelain (translucency) and the cool rim of the silhouette.
uniform vec3 scatter_color : source_color;
uniform vec3 rim_color : source_color;
// Inner light at rest (cool pearl) and under tension (warm pale gold).
uniform vec3 glow_color : source_color;
uniform vec3 drive_color : source_color;

// 0..1: tension of the hand (its thread pulling). 0 = at rest, cool; 1 = lit, warm, taut.
uniform float drive : hint_range(0.0, 1.0) = 0.0;
// 0..1: summoned (1) / gone (0); condenses from presence_origin.
uniform float presence : hint_range(0.0, 1.0) = 1.0;
uniform float select : hint_range(0.0, 1.0) = 0.0;
uniform float motion_time = 0.0;
// Object units from wrist to fingertip (every pattern scale follows it).
uniform float hand_size = 1.0;
uniform float albedo_level : hint_range(0.0, 1.0) = 0.8;
uniform float roughness_amount : hint_range(0.0, 1.0) = 0.46;
uniform float backlight_amount : hint_range(0.0, 1.0) = 0.5;
uniform float rim_intensity = 0.32;
// Inner light: at rest (always faintly there) and the extra under full tension.
uniform float glow_rest = 0.05;
uniform float glow_drive = 2.4;
// Filaments of the inner light: scale (per hand_size) and the depth of the inner layer.
uniform float filament_scale = 3.2;
uniform float depth_offset = 0.18;
// Direction the inner light flows under tension (object space; wrist -> fingers).
uniform vec3 flow_axis = vec3(0.0, 1.0, 0.0);
uniform float ao_strength : hint_range(0.0, 1.0) = 1.0;

group_uniforms presence_dissolve;
uniform vec3 presence_origin = vec3(0.0);
// Radius (object units) the hand condenses over; 0 = 0.85 * hand_size.
uniform float presence_reach = 0.0;
uniform float grain_scale = 22.0;

group_uniforms wrist;
uniform vec3 wrist_point = vec3(0.0);
uniform vec3 forearm_end = vec3(0.0);
uniform vec2 wrist_fade = vec2(0.05, 0.85);
uniform float wrist_grain = 15.0;

varying vec3 v_obj;
varying vec3 v_eye;

void vertex() {
	v_obj = VERTEX;
	vec3 cam_obj = (inverse(MODEL_MATRIX) * vec4(CAMERA_POSITION_WORLD, 1.0)).xyz;
	v_eye = VERTEX - cam_obj;
}

void fragment() {
	float size = max(hand_size, 1e-3);
	vec3 p = v_obj / size;
	float dr = clamp(drive, 0.0, 1.0);

	// --- Presence: the hand condenses out of grains from its palm outward (and back). ---
	float lip = 0.0;
	float pr = clamp(presence, 0.0, 1.0);
	if (pr < 0.999) {
		float reach = (presence_reach > 1e-3) ? presence_reach : 0.85 * size;
		float r = length(v_obj - presence_origin) / max(reach, 1e-3);
		float n = k_vnoise(p * grain_scale) * 0.55 + k_fbm(p * 3.0 + 7.0, 2) * 0.45;
		float front = pr * 1.3 - 0.15;
		float dp = front - r - (n - 0.5) * 0.35;
		if (dp < 0.0) {
			discard;
		}
		lip = 1.0 - smoothstep(0.0, 0.07, dp);
	}

	// --- Wrist: the arm ends in grains of light, never a cylinder cut (as hand_stone). ---
	vec3 arm = forearm_end - wrist_point;
	float arm_len = length(arm);
	float wlip = 0.0;
	if (arm_len > 1e-3) {
		float s = dot(v_obj - wrist_point, arm) / max(arm_len * arm_len, 1e-6);
		float dh = clamp((s - wrist_fade.x) / max(wrist_fade.y - wrist_fade.x, 1e-3), 0.0, 1.0);
		if (dh > 0.0) {
			float n = k_fbm(p * 2.0, 3) * mix(0.75, 0.3, dh) + k_vnoise(p * wrist_grain) * mix(0.25, 0.7, dh);
			float thr = dh * 1.08 - 0.04;
			if (n < thr) {
				discard;
			}
			wlip = (1.0 - smoothstep(0.0, 0.04, n - thr)) * smoothstep(0.0, 0.15, dh);
		}
	}

	float ao = mix(1.0, COLOR.r, ao_strength);
	float nv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float f = 1.0 - nv;
	float f_aa = 1.0 - smoothstep(0.1, 0.4, fwidth(f));

	// --- Porcelain: ivory in the hollows, pearl on the forms; wide soft specular. ---
	float tone = k_fbm(p * 2.4 + 4.0, 2);
	vec3 base = mix(ivory_color, pearl_color, clamp(0.3 + 0.4 * tone + 0.3 * nv, 0.0, 1.0));
	// Lit from inside, the porcelain lets less of the outer light bounce (it reads translucent).
	ALBEDO = base * albedo_level * mix(0.78, 1.0, ao) * mix(1.0, 0.72, dr);
	ROUGHNESS = roughness_amount - dr * 0.08;
	SPECULAR = 0.38;
	BACKLIGHT = scatter_color * backlight_amount;
	AO = ao;
	AO_LIGHT_AFFECT = 0.3;

	// --- Inner light, seen a little inside the porcelain (parallax). ---
	vec3 ray = k_safe_normalize(v_eye, vec3(0.0, 0.0, -1.0));
	vec3 inner = p + ray * depth_offset;
	vec3 axis = k_safe_normalize(flow_axis, vec3(0.0, 1.0, 0.0));
	// Under tension the light flows along the axis (energy arriving through the thread).
	vec3 fq = inner * filament_scale - axis * motion_time * 0.35 * dr;
	float filament = pow(max(k_ridge(fq + vec3(2.3, 5.1, 0.7)), 0.0), 4.0);
	float cloud = k_fbm(inner * 1.6 + 9.0, 3);
	// Where the camera looks through more matter (the core of a finger, the palm) the light is seen.
	float thick = nv * nv;
	float tension_light = dr * dr * (3.0 - 2.0 * dr);
	vec3 inner_col = mix(glow_color, drive_color, tension_light);
	float lum = glow_rest * (0.6 + cloud) + tension_light * glow_drive * (0.18 + 0.3 * cloud + 0.8 * filament) * mix(0.35, 1.0, thick);
	vec3 e = inner_col * lum * mix(0.55, 1.0, ao);

	// Soft cool rim (anti-aliased); it tightens and brightens a little under tension.
	float rim = smoothstep(mix(0.45, 0.6, dr), 1.0, f);
	e += rim_color * rim * rim * f_aa * rim_intensity * (1.0 + 0.5 * dr) * mix(0.5, 1.0, ao);
	e += scatter_color * pow(max(f, 0.0), 3.0) * select * 0.6;
	// Condensing / dissolving edges: warm motes of light.
	e += drive_color * (lip * 1.6 + wlip * 0.5);
	EMISSION = e;
}
