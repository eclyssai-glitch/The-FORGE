// KORIUM UNIVERSE — MIKU's body: matte luminous porcelain. Owner: art-director.
// Votive statuary, not vinyl: a matte pearl dielectric (roughness ~0.5, low broad specular) with a
// very low-contrast marbling. Light wraps round the form and the band just past the terminator
// takes a warm BLUSH scatter (porcelain lets light through: its shadows are warm, never grey-lilac).
// A grazing sheen pearl -> rose -> pale gold lives only at grazing angles, and every view-dependent
// term is anti-aliased (fwidth of the fresnel): no bright one-pixel "sticker" outline on the
// silhouette. A faint inner light (`awaken`, `breath`) makes the porcelain read as lit from within.
// Below `dissolve_top` (object Y) the skirt turns into light: noise eats it downward into grains
// with a luminous lip (never a hard hem); `dissolve_top` <= `dissolve_bottom` disables it.
// Vertex colour red = baked ambient occlusion (white when the mesh has none).
// Works without UVs (sculpted meshes): every pattern is in object space. No TIME.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

#include "res://src/style/shaders/genesis/noise.gdshaderinc"

uniform vec3 pearl_color : source_color;
uniform vec3 blush_color : source_color;
uniform vec3 rose_color : source_color;
uniform vec3 gold_color : source_color;
// Occluded porcelain: a warm dusk, never grey.
uniform vec3 shadow_color : source_color;

uniform float roughness_amount : hint_range(0.0, 1.0) = 0.52;
// Specular reflectance scale (0.5 = F0 0.04, a plain dielectric). Kept low: matte porcelain.
uniform float specular_amount : hint_range(0.0, 1.0) = 0.28;
// Light wrap past the terminator (0 = Lambert) and the warm scatter carried by that band.
uniform float wrap_amount : hint_range(0.0, 1.0) = 0.5;
uniform float scatter_amount : hint_range(0.0, 2.0) = 0.9;
// Directional shadows never go black on porcelain: a share of the light passes through, BLUSH-tinted
// (also softens the shadow-map staircase). Point/spot lights keep their own falloff.
uniform float shadow_lift : hint_range(0.0, 1.0) = 0.3;
// Grazing sheen (emission, fresnel-weighted, anti-aliased).
uniform float sheen = 0.55;
// Inner light of the porcelain (emission, strongest on the thin silhouette).
uniform float inner_glow = 0.05;
// Fake subsurface: warm light passing through the thin silhouette (view-dependent emission).
uniform float backlight_amount = 0.22;
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

group_uniforms dissolve;
// Object-space heights: solid porcelain at/above dissolve_top, fully dissolved at dissolve_bottom.
uniform float dissolve_top = -1.7;
uniform float dissolve_bottom = -4.35;
// Noise scale of the dissolving front (object units) and of the grains it breaks into.
uniform float dissolve_scale = 1.6;
uniform float grain_scale = 30.0;
// Light of the dissolving lip and how luminous the porcelain grows as it turns into light.
uniform float lip_intensity = 0.7;
uniform float light_turn = 0.8;
uniform float motion_time = 0.0;
uniform float flow_speed = 0.03;

varying vec3 v_obj;
// 1 inside the surface, -> 0 on the silhouette ring (fresnel jumps per pixel): damps the grazing
// light so the outline never stair-steps. Written in fragment(), read in light().
varying float v_edge;

void vertex() {
	v_obj = VERTEX;
}

void fragment() {
	// --- Dissolve (skirt -> light -> grains) ---
	float dh = clamp((dissolve_top - v_obj.y) / max(dissolve_top - dissolve_bottom, 1e-3), 0.0, 1.0);
	dh = (dissolve_top > dissolve_bottom) ? dh : 0.0;
	float lip = 0.0;
	if (dh > 0.0) {
		vec3 q = vec3(v_obj.x, v_obj.y + motion_time * flow_speed, v_obj.z);
		// Broad front (fbm) broken into grains (high-frequency value noise) as it sinks.
		float n = k_fbm(q * dissolve_scale, 3) * mix(0.8, 0.35, dh)
				+ k_vnoise(q * grain_scale) * mix(0.2, 0.65, dh);
		float thr = dh * 1.08 - 0.04;
		if (n < thr) {
			discard;
		}
		lip = 1.0 - smoothstep(0.0, 0.035, n - thr);
	}

	float ao = mix(1.0, COLOR.r, ao_strength);
	float nv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float f = 1.0 - nv;
	// Where the fresnel jumps by a large share per pixel (the silhouette ring), the grazing terms
	// fade out instead of drawing a staircase of bright pixels.
	float f_aa = 1.0 - smoothstep(0.1, 0.4, fwidth(f));
	v_edge = f_aa;

	float marble = k_vnoise(v_obj * marble_scale) * 0.65 + k_vnoise(v_obj * marble_scale * 3.1) * 0.35;
	vec3 base = mix(pearl_color, blush_color, 0.25 + smoothstep(0.35, 0.85, marble) * 0.35);
	base = mix(shadow_color, base * 0.66, mix(0.4, 1.0, ao));

	ALBEDO = base;
	ROUGHNESS = clamp(roughness_amount + (marble - 0.5) * 0.06, 0.0, 1.0);
	SPECULAR = specular_amount;
	METALLIC = 0.0;
	AO = ao;
	AO_LIGHT_AFFECT = 0.3;

	// Grazing sheen: only past ~60 degrees, smooth ramp, anti-aliased.
	float graze = smoothstep(0.45, 0.95, f) * f_aa;
	vec3 irid = mix(pearl_color, rose_color, smoothstep(0.55, 0.8, f));
	irid = mix(irid, gold_color, smoothstep(0.8, 0.97, f) * 0.6);
	float wake = mix(0.25, 1.0, awaken);
	vec3 sheen_e = irid * graze * graze * sheen * wake * ao;
	vec3 inner_e = mix(pearl_color, blush_color, 0.4) * inner_glow * awaken
			* (0.8 + 0.4 * breath) * mix(0.3, 1.0, f * f_aa) * ao;
	vec3 trans_e = mix(blush_color, rose_color, 0.3) * smoothstep(0.4, 0.95, f) * f_aa
			* backlight_amount * wake * ao;
	vec3 select_e = pearl_color * pow(max(f, 0.0), 2.0) * f_aa * select * 0.6;
	// The skirt turning into light: warmer and brighter toward the front, a luminous lip.
	vec3 light_e = mix(pearl_color, blush_color, 0.5) * light_turn * smoothstep(0.0, 0.8, dh) * wake
			+ mix(gold_color, pearl_color, 0.45) * lip * lip_intensity * wake;
	EMISSION = sheen_e + inner_e + trans_e + select_e + light_e;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float w = clamp(wrap_amount, 0.0, 1.0);
	float direct = clamp(ndl, 0.0, 1.0);
	float wrapped = clamp((ndl + w) / max(1.0 + w, 1.0), 0.0, 1.0);
	// The band the wrap adds beyond the terminator: light scattered through the porcelain.
	float scatter = max(wrapped - direct, 0.0);
	float edge = mix(0.55, 1.0, v_edge);
	vec3 pass = vec3(ATTENUATION);
	if (LIGHT_IS_DIRECTIONAL) {
		pass = mix(blush_color * shadow_lift, vec3(1.0), ATTENUATION);
	}
	vec3 lit = LIGHT_COLOR * pass * edge / 3.14159265;
	DIFFUSE_LIGHT += lit * (ALBEDO * wrapped + blush_color * scatter * scatter_amount * 0.5);
	// Broad, low specular (normalised Blinn-Phong; exponent from roughness): no latex highlights.
	vec3 hv = k_safe_normalize(LIGHT + VIEW, NORMAL);
	float ndh = clamp(dot(NORMAL, hv), 0.0, 1.0);
	float r = clamp(ROUGHNESS, 0.05, 1.0);
	float shin = max(2.0 / max(r * r * r * r, 1e-6) - 2.0, 1.0);
	float lh = clamp(dot(LIGHT, hv), 0.0, 1.0);
	float f0 = 0.08 * specular_amount;
	float fres = f0 + (1.0 - f0) * pow(max(1.0 - lh, 0.0), 5.0);
	float spec = pow(max(ndh, 0.0), max(shin, 1.0)) * (shin + 8.0) / 25.1327 * fres * direct;
	SPECULAR_LIGHT += LIGHT_COLOR * ATTENUATION * edge * spec / 3.14159265;
}
