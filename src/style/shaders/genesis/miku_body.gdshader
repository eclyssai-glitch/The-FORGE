// KORIUM UNIVERSE — MIKU's body: lunar porcelain. Owner: art-director.
// Pearl dielectric with a very low-contrast marbling, a fake subsurface (BACKLIGHT: the warm
// nebula behind her glows through the thin edges) and an iridescent grazing sheen that slides
// pearl -> rose -> pale gold. A faint inner light (`awaken`, `breath`) makes the porcelain read as
// lit from within. Vertex colour red = baked ambient occlusion (white when the mesh has none).
// Works without UVs (sculpted meshes): every pattern is in object space. No TIME.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://src/style/shaders/genesis/noise.gdshaderinc"

uniform vec3 pearl_color : source_color;
uniform vec3 blush_color : source_color;
uniform vec3 rose_color : source_color;
uniform vec3 gold_color : source_color;
// Occluded porcelain drifts toward the night (never grey).
uniform vec3 shadow_color : source_color;

uniform float roughness_amount : hint_range(0.0, 1.0) = 0.3;
uniform float specular_amount : hint_range(0.0, 1.0) = 0.5;
// Iridescent grazing sheen (emission, fresnel-weighted).
uniform float sheen = 1.5;
// Inner light of the porcelain (emission, strongest on the thin silhouette).
uniform float inner_glow = 0.05;
// Fake subsurface: warm light passing through the thin silhouette (view-dependent emission; the
// engine BACKLIGHT is kept tiny — with the warm rim light facing the camera it lit every front
// face evenly and flattened the porcelain).
uniform float backlight_amount = 0.5;
// Baked AO from vertex colour red (0 = ignore).
uniform float ao_strength : hint_range(0.0, 1.0) = 1.0;
// Marbling scale in object units (MIKU is ~6 u tall).
uniform float marble_scale = 1.3;
// 0 = dormant porcelain (cold, no inner light) -> 1 awake.
uniform float awaken : hint_range(0.0, 1.0) = 1.0;
// Breathing 0..1 (animator: sine of Palette.T_BREATH over MotionClock).
uniform float breath : hint_range(0.0, 1.0) = 0.5;
// Hover / selection: pearl rim.
uniform float select : hint_range(0.0, 1.0) = 0.0;

varying vec3 v_obj;

void vertex() {
	v_obj = VERTEX;
}

void fragment() {
	float ao = mix(1.0, COLOR.r, ao_strength);
	float nv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float f = 1.0 - nv;

	float marble = k_vnoise(v_obj * marble_scale) * 0.65 + k_vnoise(v_obj * marble_scale * 3.1) * 0.35;
	vec3 base = mix(pearl_color, blush_color, 0.3 + smoothstep(0.35, 0.85, marble) * 0.4);
	base = mix(shadow_color, base * 0.62, mix(0.35, 1.0, ao));

	ALBEDO = base;
	ROUGHNESS = roughness_amount + (marble - 0.5) * 0.08;
	SPECULAR = specular_amount;
	METALLIC = 0.0;
	AO = ao;
	AO_LIGHT_AFFECT = 0.35;
	BACKLIGHT = blush_color * 0.04;

	// Iridescent ramp over the grazing angle: pearl -> rose -> pale gold at the very rim.
	vec3 irid = mix(pearl_color, rose_color, smoothstep(0.2, 0.6, f));
	irid = mix(irid, gold_color, smoothstep(0.6, 0.95, f));
	float wake = mix(0.25, 1.0, awaken);
	vec3 sheen_e = irid * pow(f, 2.2) * sheen * wake;
	vec3 inner_e = mix(pearl_color, blush_color, 0.4) * inner_glow * awaken
			* (0.8 + 0.4 * breath) * mix(0.3, 1.0, pow(f, 1.5)) * ao;
	vec3 trans_e = mix(blush_color, rose_color, 0.35) * smoothstep(0.35, 0.95, f) * backlight_amount * wake * ao;
	vec3 select_e = pearl_color * pow(f, 3.0) * select * 0.6;
	EMISSION = sheen_e + inner_e + trans_e + select_e;
}
