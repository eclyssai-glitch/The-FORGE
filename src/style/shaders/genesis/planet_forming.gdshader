// KORIUM UNIVERSE — a planet (sub-agent) being formed. Owner: art-director.
// Four uniforms, 0..1, tell the whole genesis:
//   formation  — accretion: matter gathers in patches that grow until the sphere is whole; the
//                growing edge is lit gold (never a flash).
//   heat       — incandescent magma: dark cooled melt crossed by bright flowing gold rivers.
//   crust      — dark stone plates (Voronoi cells) settle one by one over the melt; the cracks
//                between plates keep the magma glow, fading with `heat`.
//   atmosphere — haze on the limb + a thin ice -> dusk-rose fresnel rim.
// Patterns use the object-space direction (sphere of any radius, no UVs needed). `motion_time`
// (MotionClock) drives the magma flow — never TIME. Opaque; accretion uses discard.
// Cost: one 3x3x3 Voronoi + a few fbm (`detail` octaves for the magma; LOW uses 3).
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://src/style/shaders/genesis/noise.gdshaderinc"

uniform float formation : hint_range(0.0, 1.0) = 1.0;
uniform float heat : hint_range(0.0, 1.0) = 1.0;
uniform float crust : hint_range(0.0, 1.0) = 0.0;
uniform float atmosphere : hint_range(0.0, 1.0) = 0.0;

uniform vec3 magma_hot_color : source_color;
uniform vec3 magma_mid_color : source_color;
uniform vec3 magma_deep_color : source_color;
uniform vec3 crust_color : source_color;
uniform vec3 crust_light_color : source_color;
uniform vec3 atmo_inner_color : source_color;
uniform vec3 atmo_outer_color : source_color;
uniform vec3 accretion_color : source_color;

uniform float magma_intensity = 1.6;
uniform float crack_glow = 1.6;
uniform float atmo_intensity = 1.0;
uniform float flow_speed = 0.02;
uniform float motion_time = 0.0;
// Pattern scales (per unit direction).
uniform float magma_scale = 2.2;
uniform float plate_scale = 4.6;
// Crack half-width in Voronoi units.
uniform float crack_width = 0.028;
// Different planets: offsets the whole pattern.
uniform float seed = 0.0;
// Noise octaves of the magma (LOW 3, HIGH 4).
uniform int detail : hint_range(1, 5) = 4;
uniform float select : hint_range(0.0, 1.0) = 0.0;

varying vec3 v_dir;

void vertex() {
	v_dir = normalize(VERTEX);
}

void fragment() {
	vec3 d = v_dir + vec3(seed * 13.7, seed * 5.3, seed * 9.1);

	// Accretion: patches of matter appear and grow; a gold lip lights the growing edge.
	float acc = k_fbm(d * 3.0 + 40.0, 3);
	float thr = formation * 1.3 - 0.15;
	if (acc > thr) {
		discard;
	}
	float lip = (formation < 0.999) ? 1.0 - smoothstep(0.0, 0.06, thr - acc) : 0.0;

	// Magma: warped fbm body + ridged rivers of hot melt that drift slowly.
	float t = motion_time * flow_speed;
	vec3 w = vec3(k_vnoise(d * 1.4 + t), k_vnoise(d * 1.4 + 9.2 - t), k_vnoise(d * 1.4 + 4.4 + t * 0.7));
	vec3 mq = d * magma_scale + (w - 0.5) * 1.8;
	float body = k_fbm(mq, detail);
	float rivers = pow(k_ridge(mq * 1.7 + 2.0), 6.0);
	float hot = clamp(smoothstep(0.5, 0.85, body) * 0.5 + rivers * 0.9, 0.0, 1.0);
	vec3 magma = mix(magma_deep_color, magma_mid_color, smoothstep(0.0, 0.5, hot));
	magma = mix(magma, magma_hot_color, smoothstep(0.5, 1.0, hot));
	float magma_lum = mix(0.12, 1.0, hot);

	// Crust: Voronoi plates settle one by one (plate hash < crust); cracks = cell borders.
	vec3 v = k_voronoi(d * plate_scale + (w - 0.5) * 0.35 + 70.0, 0.9);
	float edge = v.y - v.x;
	float aa = max(fwidth(edge), 1e-4);
	float cw = crack_width * (0.5 + k_vnoise(d * 9.0 + 2.0));
	float crack = 1.0 - smoothstep(cw - aa, cw + aa, edge);
	// Fine secondary fractures inside the plates.
	float fine = k_line(k_ridge(d * 14.0 + (w - 0.5) * 2.0), 0.03) * smoothstep(0.5, 0.7, k_vnoise(d * 5.0 + 8.0));
	crack = max(crack, fine * 0.6);
	float settled = smoothstep(v.z - 0.04, v.z + 0.04, crust * 1.08 - 0.04);
	float covered = settled * (1.0 - crack);
	float crust_tex = k_fbm(d * 11.0 + 3.0, 2);
	vec3 crust_albedo = mix(crust_color, crust_light_color, crust_tex * 0.6 + (v.z - 0.5) * 0.2);

	float nv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float f = 1.0 - nv;

	ALBEDO = mix(magma_deep_color * 0.2, crust_albedo, covered);
	ROUGHNESS = mix(0.6, 0.85, covered);
	SPECULAR = 0.3;
	METALLIC = 0.0;

	vec3 e = magma * magma_lum * magma_intensity * heat * (1.0 - covered);
	// Cracks between settled plates: the melt shows through, dimming as the planet cools.
	float crack_heat = 0.05 + 0.95 * heat * heat;
	e += mix(magma_mid_color, magma_hot_color, heat) * crack * settled * crack_glow * crack_heat;

	// Atmosphere: haze over the limb + a bright thin rim (ice at the edge, rose deeper in).
	vec3 atmo = mix(atmo_outer_color, atmo_inner_color, smoothstep(0.55, 0.95, f));
	ALBEDO = mix(ALBEDO, atmo_inner_color * 0.3, atmosphere * pow(f, 2.2) * 0.7);
	e += atmo * (pow(f, 3.5) * 0.7 + pow(f, 9.0) * 1.3) * atmosphere * atmo_intensity;

	e += accretion_color * lip * 2.0;
	e += atmo_inner_color * pow(f, 3.0) * select * 0.6;
	EMISSION = e;
}
