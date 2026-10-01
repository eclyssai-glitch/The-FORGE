// KORIUM UNIVERSE — memory belt rocks (asteroids). Owner: art-director.
// Rough night stone (same family as the hands, without polish), a dusk-rose/lilac rim from the
// nebula backlight, and — for a few rocks chosen by instance id — a quiet gold glint: a kept
// memory. `memory` 0..1 raises those glints (belt.formed). Normals are bent toward the rock's
// sphere (`smooth_shape`) so low-poly facets read as worn, rounded stone, and a broad anti-aliased
// rim (nebula backlight) draws every rock against the night. Works on single meshes and MultiMesh
// (INSTANCE_ID; custom data not required). Object-space pattern, no UVs, no TIME.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://src/style/shaders/genesis/noise.gdshaderinc"

uniform vec3 rock_color : source_color;
uniform vec3 rock_light_color : source_color;
uniform vec3 rim_color : source_color;
uniform vec3 glint_color : source_color;
uniform float memory : hint_range(0.0, 1.0) = 1.0;
// Share of rocks that hold a lit memory.
uniform float glint_share : hint_range(0.0, 1.0) = 0.05;
uniform float glint_intensity = 1.2;
uniform float rim_intensity = 0.8;
uniform float smooth_shape : hint_range(0.0, 1.0) = 0.5;
uniform float ao_strength : hint_range(0.0, 1.0) = 1.0;

varying vec3 v_obj;
varying flat float v_seed;
varying vec3 v_round;

void vertex() {
	v_obj = VERTEX;
	v_round = (MODELVIEW_MATRIX * vec4(VERTEX, 0.0)).xyz;
	v_seed = k_hash13(vec3(float(INSTANCE_ID), 3.7, 1.3));
}

void fragment() {
	vec3 round_n = k_safe_normalize(v_round, NORMAL);
	NORMAL = k_safe_normalize(mix(NORMAL, round_n, smooth_shape), NORMAL);
	float ao = mix(1.0, COLOR.r, ao_strength);
	float n = k_fbm(v_obj * 3.0 + v_seed * 17.0, 3);
	ALBEDO = mix(rock_color, rock_light_color, n * 0.6) * mix(0.5, 1.0, ao);
	ROUGHNESS = 0.85;
	SPECULAR = 0.3;
	METALLIC = 0.0;
	AO = ao;

	float f = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	// Small rocks (a few pixels) keep half their rim: never a black hole in the nebula.
	float f_aa = 1.0 - 0.5 * smoothstep(0.15, 0.5, fwidth(f));
	float rim = smoothstep(0.3, 1.0, f);
	vec3 e = rim_color * (rim * rim * f_aa * rim_intensity + 0.04);
	float holds = step(1.0 - glint_share, v_seed);
	float spot = smoothstep(0.55, 0.8, k_vnoise(v_obj * 5.0 + v_seed * 31.0));
	e += glint_color * holds * memory * glint_intensity * (0.08 + spot);
	EMISSION = e;
}
