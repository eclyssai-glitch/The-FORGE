// KORIUM UNIVERSE — MIKU's gown: a veil of light that dissolves downward into star dust.
// Owner: art-director. Works on any mesh (cone, lathe, sculpt) — no UVs needed: the fall-off runs
// along object-space Y from `fade_top` (solid veil) to `fade_bottom` (fully dissolved).
// Additive, unshaded, no depth write, front faces only (the inside of the shell never shows: no
// visible thickness). The veil is brighter at grazing angles (fresnel: light caught in folds,
// anti-aliased so the silhouette never stair-steps), noise eats it from below — a broad front
// that breaks into grains as it sinks, with a luminous lip, never a hard hem — and fine star
// grains remain where it has dissolved (they hand over to the Stardust river).
// Flow is driven by `motion_time` (MotionClock), never TIME.
shader_type spatial;
render_mode unshaded, blend_add, cull_back, depth_draw_never, shadows_disabled, fog_disabled;

#include "res://src/style/shaders/genesis/noise.gdshaderinc"

uniform vec3 top_color : source_color;
uniform vec3 bottom_color : source_color;
uniform vec3 dust_color : source_color;
uniform float intensity = 0.55;
// Object-space heights: fully present at/above fade_top, fully gone at fade_bottom.
uniform float fade_top = 0.0;
uniform float fade_bottom = -4.0;
// Noise scale (object units) and downward flow speed of the dissolve.
uniform float noise_scale = 1.4;
uniform float flow_speed = 0.05;
uniform float motion_time = 0.0;
// Minimum veil opacity when seen face-on (fresnel lifts the rest).
uniform float face_opacity : hint_range(0.0, 1.0) = 0.12;
// Star grains left in the dissolved part.
uniform float dust_amount : hint_range(0.0, 1.0) = 0.6;
uniform float dust_scale = 14.0;
// Grains of the dissolving front (object units).
uniform float grain_scale = 9.0;
// Global presence 0..1 (awakening).
uniform float presence : hint_range(0.0, 1.0) = 1.0;

varying vec3 v_obj;

void vertex() {
	v_obj = VERTEX;
}

void fragment() {
	float h = clamp((fade_top - v_obj.y) / max(fade_top - fade_bottom, 1e-3), 0.0, 1.0);
	// Clamped: |n.v| can exceed 1 by a rounding step, and pow() of a negative base is NaN.
	float nv = clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0);
	float f_aa = 1.0 - smoothstep(0.15, 0.5, fwidth(nv));
	float veil = mix(face_opacity, 1.0, pow(max(1.0 - nv, 0.0), 1.6) * f_aa);

	vec3 q = vec3(v_obj.x, v_obj.y + motion_time * flow_speed, v_obj.z) * noise_scale;
	// Broad front (fbm) broken into grains (high-frequency noise) as it sinks.
	float n = k_fbm(q, 3) * mix(0.85, 0.55, h) + k_vnoise(q * (grain_scale / max(noise_scale, 1e-3))) * mix(0.15, 0.45, h);
	// Dissolve: the threshold rises with depth; a soft band keeps the edge luminous, not cut.
	float thr = h * 1.05 - 0.05;
	float body = smoothstep(thr - 0.01, thr + 0.14, n);
	// Gaussian lip: d*d, never pow(d, 2.0) (d is signed; pow of a negative base is NaN).
	float lip_d = (n - thr) / 0.04;
	float lip = exp(-lip_d * lip_d) * smoothstep(0.05, 0.3, h) * 0.8;

	// Long vertical folds (light caught in the fabric of light).
	vec2 around_xz = v_obj.xz + vec2(1e-4);
	vec2 around = around_xz / max(length(around_xz), 1e-6);
	float folds = 0.7 + 0.3 * k_vnoise(vec3(around * 3.0, v_obj.y * 0.35 + 1.7));

	vec3 col = mix(top_color, bottom_color, smoothstep(0.0, 0.85, h));
	float grains = k_stars(v_obj * dust_scale + vec3(0.0, motion_time * flow_speed * dust_scale, 0.0),
			0.22, 0.18, fwidth(v_obj.y) * dust_scale) * dust_amount * smoothstep(0.25, 0.75, h)
			* (1.0 - smoothstep(0.85, 1.0, h));

	float a = (veil * folds * body + lip) * (1.0 - smoothstep(0.92, 1.0, h));
	vec3 e = col * a + dust_color * grains * 1.6;
	ALBEDO = e * intensity * presence;
	ALPHA = 1.0;
}
