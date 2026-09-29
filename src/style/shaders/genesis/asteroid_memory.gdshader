// KORIUM UNIVERSE — memory belt rocks (asteroids). Owner: art-director.
// Rough night stone (same family as the hands, without polish), a dusk-rose/lilac rim from the
// nebula backlight, and — for a few rocks chosen by instance id — a quiet gold glint: a kept
// memory. `memory` 0..1 raises those glints (belt.formed). Works on single meshes and MultiMesh
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
uniform float rim_intensity = 0.35;
uniform float ao_strength : hint_range(0.0, 1.0) = 1.0;

varying vec3 v_obj;
varying flat float v_seed;

void vertex() {
	v_obj = VERTEX;
	v_seed = k_hash13(vec3(float(INSTANCE_ID), 3.7, 1.3));
}

void fragment() {
	float ao = mix(1.0, COLOR.r, ao_strength);
	float n = k_fbm(v_obj * 3.0 + v_seed * 17.0, 3);
	ALBEDO = mix(rock_color, rock_light_color, n * 0.6) * mix(0.5, 1.0, ao);
	ROUGHNESS = 0.85;
	SPECULAR = 0.3;
	METALLIC = 0.0;
	AO = ao;

	float f = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	vec3 e = rim_color * pow(f, 3.0) * rim_intensity;
	float holds = step(1.0 - glint_share, v_seed);
	float spot = smoothstep(0.55, 0.8, k_vnoise(v_obj * 5.0 + v_seed * 31.0));
	e += glint_color * holds * memory * glint_intensity * (0.08 + spot);
	EMISSION = e;
}
