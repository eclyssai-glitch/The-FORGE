// KORIUM UNIVERSE — faceted shell of the origin core. Owner: art-director.
// Dark faceted metal with a subtle BONE fresnel so the dormant core reads in near darkness.
// `energy` (0..1) lets the heart's EMBER bleed through the grazing facets — dormant = no EMBER.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec3 shell_color : source_color;
uniform vec3 rim_color : source_color;
uniform vec3 ember_color : source_color;
uniform float energy : hint_range(0.0, 1.0) = 0.0;
uniform float rim_energy = 0.16;
uniform float ember_rim_energy = 1.4;

void fragment() {
	float nv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float fres = 1.0 - nv;
	float e = clamp(energy, 0.0, 1.0);
	ALBEDO = shell_color;
	METALLIC = 0.7;
	ROUGHNESS = 0.36;
	float fres3 = pow(max(fres, 0.0), 3.0);
	EMISSION = rim_color * fres3 * rim_energy + ember_color * e * fres3 * ember_rim_energy;
}
