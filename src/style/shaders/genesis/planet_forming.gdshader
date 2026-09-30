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
// Share of plate borders that stay open (glowing cracks); the others are sealed, dim seams.
uniform float open_share : hint_range(0.0, 1.0) = 0.45;
// Different planets: offsets the whole pattern.
uniform float seed = 0.0;
// Noise octaves of the magma (LOW 3, HIGH 4).
uniform int detail : hint_range(1, 5) = 4;
uniform float select : hint_range(0.0, 1.0) = 0.0;

varying vec3 v_dir;

void vertex() {
	v_dir = k_safe_normalize(VERTEX, vec3(0.0, 1.0, 0.0));
}

void fragment() {
	vec3 d = v_dir + vec3(seed * 13.7, seed * 5.3, seed * 9.1);

	// Accretion: many small grains of matter gather and merge until the shell is whole (never one
	// lonely blob); a gold lip lights every growing edge. The threshold follows the fbm's real range.
	float acc = k_fbm(d * 5.5 + 40.0, 3);
	float thr = mix(0.22, 0.8, formation);
	if (formation < 0.999 && acc > thr) {
		discard;
	}
	float lip = (formation < 0.999) ? 1.0 - smoothstep(0.0, 0.045, thr - acc) : 0.0;

	// Magma: a lava lake, not a stain — a dark cooled skin broken by a network of thin incandescent
	// rivers at two scales that drift slowly, with a few hot upwellings. Mid-tones are rare.
	float t = motion_time * flow_speed;
	vec3 w = vec3(k_vnoise(d * 1.4 + t), k_vnoise(d * 1.4 + 9.2 - t), k_vnoise(d * 1.4 + 4.4 + t * 0.7));
	vec3 mq = d * magma_scale + (w - 0.5) * 1.8;
	float body = k_fbm(mq, detail);
	float rivers = pow(max(k_ridge(mq * 1.7 + 2.0), 0.0), 9.0);
	float veins_fine = pow(max(k_ridge(mq * 4.3 + 7.0), 0.0), 12.0) * smoothstep(0.35, 0.6, body);
	float upwell = smoothstep(0.66, 0.86, body);
	float hot = clamp(rivers + veins_fine * 0.7 + upwell * 0.45, 0.0, 1.0);
	vec3 magma = mix(magma_deep_color, magma_mid_color, smoothstep(0.0, 0.45, hot));
	magma = mix(magma, magma_hot_color, smoothstep(0.45, 1.0, hot));
	float magma_lum = mix(0.035, 1.0, hot * hot * (3.0 - 2.0 * hot));

	// Crust: Voronoi plates settle one by one (plate hash < crust); cracks = cell borders. To keep a
	// formed world from reading as a honeycomb: strong warp, only some borders stay open (the others
	// are sealed seams), plate tones vary per plate and per continent (low-frequency tint), and the
	// crack network fades out when its cells get small on screen (a distant world shows continents,
	// not a grid).
	vec3 pq = d * plate_scale + (w - 0.5) * 0.35 + (vec3(k_vnoise(d * 2.1 + 5.0), k_vnoise(d * 2.1 + 15.0), k_vnoise(d * 2.1 + 25.0)) - 0.5) * 1.1 + 70.0;
	vec4 v = k_voronoi2(pq, 1.0);
	float edge = v.y - v.x;
	float aa = max(fwidth(edge), 1e-4);
	float cw = crack_width * (0.5 + k_vnoise(d * 9.0 + 2.0));
	float crack = 1.0 - smoothstep(cw - aa, cw + aa, edge);
	float open = mix(0.18, 1.0, step(k_edge_hash(v.z, v.w), open_share));
	// Fine secondary fractures inside the plates.
	float fine = k_line(k_ridge(d * 14.0 + (w - 0.5) * 2.0), 0.03) * smoothstep(0.5, 0.7, k_vnoise(d * 5.0 + 8.0));
	float cells_px = length(fwidth(pq));
	float near = 1.0 - smoothstep(0.08, 0.3, cells_px);
	crack = max(crack * open, fine * 0.6) * near;
	float settled = smoothstep(v.z - 0.04, v.z + 0.04, crust * 1.08 - 0.04);
	float covered = settled * (1.0 - crack);
	float crust_tex = k_fbm(d * 11.0 + 3.0, 2);
	float continent = smoothstep(0.35, 0.65, k_fbm(d * 1.6 + 31.0, 3));
	vec3 crust_albedo = mix(crust_color, crust_light_color,
			clamp(crust_tex * 0.45 + (v.z - 0.5) * 0.35 + continent * 0.55, 0.0, 1.0));

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
	ALBEDO = mix(ALBEDO, atmo_inner_color * 0.3, atmosphere * pow(max(f, 0.0), 2.2) * 0.7);
	e += atmo * (pow(max(f, 0.0), 3.5) * 0.7 + pow(max(f, 0.0), 9.0) * 1.3) * atmosphere * atmo_intensity;

	e += accretion_color * lip * 2.0;
	e += atmo_inner_color * pow(max(f, 0.0), 3.0) * select * 0.6;
	EMISSION = e;
}
