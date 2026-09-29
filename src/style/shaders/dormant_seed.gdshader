// KORIUM UNIVERSE — dormant seeds in the UNIVERSE (future constructs). Owner: art-director.
// Cold and quiet: near-black body with an ASH fresnel. `energy` (0..1) warms the rim to EMBER
// only when a seed is actually powered — at 0 there is no accent at all.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec3 body_color : source_color;
uniform vec3 cold_color : source_color;
uniform vec3 ember_color : source_color;
uniform float energy : hint_range(0.0, 1.0) = 0.0;
uniform float cold_energy = 0.55;
uniform float ember_energy = 1.6;

void fragment() {
	float nv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float fres = pow(1.0 - nv, 2.0);
	float e = clamp(energy, 0.0, 1.0);
	ALBEDO = body_color;
	METALLIC = 0.5;
	ROUGHNESS = 0.5;
	vec3 cold = cold_color * (0.06 + fres * cold_energy);
	vec3 warm = ember_color * (0.08 + fres) * ember_energy;
	EMISSION = mix(cold, warm, e);
}
