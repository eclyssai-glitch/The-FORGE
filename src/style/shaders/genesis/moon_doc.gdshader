// KORIUM UNIVERSE — a documentation moon: knowledge ice. Owner: art-director.
// Frosted pale-ice body with faint strata (stacked pages of ice, latitude bands in object space),
// a cool translucent backlight and a thin ice rim. `formation` 0..1 accretes the moon like the
// planet (growing patches, luminous edge); `glow` 0..1 is its quiet inner light once formed.
// Object-space direction (sphere of any radius, no UVs). No TIME.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://src/style/shaders/genesis/noise.gdshaderinc"

uniform vec3 ice_color : source_color;
uniform vec3 deep_color : source_color;
uniform vec3 light_color : source_color;
uniform vec3 accretion_color : source_color;
uniform float formation : hint_range(0.0, 1.0) = 1.0;
uniform float glow : hint_range(0.0, 1.0) = 0.5;
// Strata (pages) across the moon, and their visibility.
uniform float strata = 22.0;
uniform float strata_strength : hint_range(0.0, 1.0) = 0.8;
uniform float rim_intensity = 0.6;
uniform float seed = 0.0;
uniform float select : hint_range(0.0, 1.0) = 0.0;

varying vec3 v_dir;

void vertex() {
	v_dir = normalize(VERTEX);
}

void fragment() {
	vec3 d = v_dir + vec3(seed * 7.3, seed * 3.1, seed * 5.9);
	float acc = k_fbm(d * 3.2 + 20.0, 3);
	float thr = formation * 1.3 - 0.15;
	if (acc > thr) {
		discard;
	}
	float lip = (formation < 0.999) ? 1.0 - smoothstep(0.0, 0.05, thr - acc) : 0.0;

	float frost = k_fbm(d * 6.0, 3);
	// Strata: slightly warped latitude bands (pages of ice), anti-aliased.
	float y = v_dir.y * strata + (k_vnoise(d * 2.0) - 0.5) * 1.2;
	float dist = abs(fract(y + 0.5) - 0.5);
	float line = 1.0 - smoothstep(0.0, fwidth(y) * 1.2 + 0.03, dist);

	float nv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float f = 1.0 - nv;

	ALBEDO = mix(deep_color, ice_color, 0.55 + 0.35 * frost) * (1.0 - line * strata_strength * 0.35);
	ROUGHNESS = mix(0.45, 0.8, frost);
	SPECULAR = 0.4;
	METALLIC = 0.0;
	BACKLIGHT = ice_color * 0.35;

	vec3 e = light_color * glow * (0.05 + line * strata_strength * 0.18) * mix(0.5, 1.0, nv);
	e += ice_color * pow(f, 4.0) * rim_intensity;
	e += accretion_color * lip * 2.0;
	e += light_color * pow(f, 3.0) * select * 0.6;
	EMISSION = e;
}
