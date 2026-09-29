// KORIUM UNIVERSE — dormant seeds in the UNIVERSE (future constructs). Owner: art-director.
// Cold and quiet: near-black body with an ASH fresnel. `energy` (0..1) warms the rim to EMBER
// only when a seed is actually powered — at 0 there is no accent at all.
// `select` (0..1) is the only uniform the world writes for hover/selection: a thin BONE rim
// (select_color * pow(1 - n.v, 3) * select * select_energy) on top of the resting emission, so
// the resting look (cold_color/cold_energy) never changes with selection.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec3 body_color : source_color;
uniform vec3 cold_color : source_color;
uniform vec3 ember_color : source_color;
uniform float energy : hint_range(0.0, 1.0) = 0.0;
uniform float cold_energy = 0.55;
uniform float ember_energy = 1.6;
uniform float select : hint_range(0.0, 1.0) = 0.0;
uniform vec3 select_color : source_color;
uniform float select_energy = 0.35;

void fragment() {
	float nv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float fres = pow(1.0 - nv, 2.0);
	float e = clamp(energy, 0.0, 1.0);
	ALBEDO = body_color;
	METALLIC = 0.5;
	ROUGHNESS = 0.5;
	vec3 cold = cold_color * (0.03 + fres * cold_energy);
	vec3 warm = ember_color * (0.08 + fres) * ember_energy;
	vec3 sel = select_color * pow(1.0 - nv, 3.0) * clamp(select, 0.0, 1.0) * select_energy;
	EMISSION = mix(cold, warm, e) + sel;
}
