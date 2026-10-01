// KORIUM UNIVERSE — a planet (sub-agent) being formed. Owner: art-director.
// Four uniforms, 0..1, tell the whole genesis:
//   formation  — accretion: matter gathers in patches that grow until the sphere is whole; the
//                growing edge is lit gold (never a flash).
//   heat       — incandescent magma: dark cooled melt crossed by bright flowing gold rivers.
//   crust      — dark stone plates (Voronoi cells) settle one by one over the melt; the cracks
//                between plates keep the magma glow, fading with `heat`.
//   atmosphere — the formed world: basins fill into deep ICE-blue seas with a soft glint, the land
//                turns rose, thin PEARL clouds drift over it, a lit ICE limb scatters on the day
//                side, a DUSK_ROSE band follows the terminator (custom light()) and a soft haze
//                covers the disc. The formed world is the most beautiful body in frame even under
//                a faint key: its seas, land and clouds are light albedos, the terminator and limb
//                are coloured light (specular channel, independent of the albedo).
// The engine multiplies DIFFUSE_LIGHT by ALBEDO after light(): light() never multiplies by ALBEDO
// itself (that squared the dark crust into black).
// `world_style` (x = ICE latitude bands, y = rose dust) turns a formed world into a distinct
// family (the distant worlds); (0, 0) = the forming planet's own look.
// Every grazing term is anti-aliased (fwidth of the fresnel): no stair-stepped outline.
// Patterns use the object-space direction (sphere of any radius, no UVs needed). `motion_time`
// (MotionClock) drives the magma flow — never TIME. Opaque; accretion uses discard.
// Cost: one 3x3x3 Voronoi + a few fbm (`detail` octaves for the magma; LOW uses 3).
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

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
// Formed land (continents) and the colours of the distant-world families.
uniform vec3 land_color : source_color;
uniform vec3 band_color : source_color;
uniform vec3 dust_color : source_color;
// Formed world: seas (basins) and clouds.
uniform vec3 ocean_color : source_color;
uniform vec3 cloud_color : source_color;

uniform float magma_intensity = 1.6;
uniform float crack_glow = 1.6;
uniform float atmo_intensity = 1.0;
// Lit-limb scattering and the terminator band (shares of the light that reaches them).
uniform float scatter_amount = 0.55;
uniform float terminator_amount = 1.1;
// Light wrap of the formed world (soft day/night line) and the sea glint.
uniform float wrap_amount : hint_range(0.0, 1.0) = 0.18;
uniform float glint_amount = 0.5;
// Cloud cover of the formed world (0 = none) and its drift speed.
uniform float cloud_amount : hint_range(0.0, 1.0) = 0.45;
uniform float cloud_speed = 0.004;
// x = ICE latitude bands, y = rose dust (0..1 each); see header.
uniform vec2 world_style = vec2(0.0);
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
// Written in fragment(), read in light(): silhouette damping and the sea share (glint).
varying float v_edge;
varying float v_sea;

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
	// Continents: broad land masses (lighter, warm) against dark basins; plate tones on top.
	float land = smoothstep(0.42, 0.58, k_fbm(d * 1.4 + 31.0, 4));
	vec3 basin_albedo = mix(crust_color, crust_light_color, clamp(crust_tex * 0.5 + (v.z - 0.5) * 0.25, 0.0, 1.0));
	vec3 land_albedo = mix(crust_light_color, land_color, clamp(0.35 + crust_tex * 0.5 + (v.z - 0.5) * 0.3, 0.0, 1.0));
	vec3 crust_albedo = mix(basin_albedo, land_albedo, land);
	// Distant-world families: ICE latitude bands / rose dust replace the plates (no cracks).
	float style_b = clamp(world_style.x, 0.0, 1.0);
	float style_d = clamp(world_style.y, 0.0, 1.0);
	float lat = v_dir.y * 5.5 + (k_fbm(d * 2.2 + 7.0, 3) - 0.5) * 1.6;
	float bands = 0.5 + 0.5 * sin(lat * 3.14159 + sin(lat * 1.7) * 0.8);
	vec3 banded = mix(crust_color, band_color, smoothstep(0.2, 0.9, bands) * 0.85 + crust_tex * 0.15);
	vec3 dusty = mix(crust_light_color, dust_color, smoothstep(0.3, 0.75, k_fbm(d * 3.0 + 17.0, 3)) * 0.8 + 0.1);
	// The formed world (atmosphere, own look only): basins become seas, the land warms, clouds drift.
	float own = 1.0 - max(style_b, style_d);
	float formed = clamp(atmosphere, 0.0, 1.0) * own;
	float sea = (1.0 - land) * formed;
	vec3 sea_albedo = mix(ocean_color * 0.55, ocean_color, clamp(crust_tex * 0.8 + 0.1, 0.0, 1.0));
	vec3 shore = mix(land_albedo, mix(land_color, cloud_color, 0.25), 0.5);
	crust_albedo = mix(crust_albedo, mix(sea_albedo, shore, land), formed * 0.85);
	crust_albedo = mix(crust_albedo, banded, style_b);
	crust_albedo = mix(crust_albedo, dusty, style_d);
	crack *= 1.0 - max(style_b, style_d);
	// A formed world shows land and sea, not a cracked marble: the sealed seams vanish under the air.
	crack *= 1.0 - formed * 0.85;
	covered = settled * (1.0 - crack);
	float cl_t = motion_time * cloud_speed;
	vec3 cq = d * 3.2 + vec3(cl_t, 0.0, -cl_t * 0.7) + (w - 0.5) * 0.6;
	float cloud = smoothstep(0.52, 0.74, k_fbm(cq + 51.0, 3)) * cloud_amount * formed * covered;
	v_sea = sea * covered * (1.0 - cloud);

	float nv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float f = 1.0 - nv;
	float f_aa = 1.0 - smoothstep(0.1, 0.4, fwidth(f));
	v_edge = f_aa;

	ALBEDO = mix(magma_deep_color * 0.2, crust_albedo, covered);
	ALBEDO = mix(ALBEDO, cloud_color, cloud);
	ROUGHNESS = mix(mix(0.6, 0.85, covered), 0.45, v_sea);
	SPECULAR = 0.3;
	METALLIC = 0.0;

	// Under a settled crust the open floor cools with the heat (a formed world is not a cracked marble).
	vec3 e = magma * magma_lum * magma_intensity * heat * (1.0 - covered) * mix(1.0, clamp(heat * 1.5, 0.0, 1.0), crust);
	// Cracks between settled plates: the melt shows through, cooling (and closing) with the heat.
	float crack_heat = 0.006 + 0.994 * heat * heat * heat;
	e += mix(magma_mid_color, magma_hot_color, heat) * crack * settled * crack_glow * crack_heat;

	// Atmosphere: a soft haze over the disc toward the limb (the lit limb is scattered in light()).
	float haze = smoothstep(0.35, 1.0, f);
	ALBEDO = mix(ALBEDO, atmo_inner_color * 0.35, atmosphere * haze * haze * haze * 0.4);
	vec3 atmo = mix(atmo_outer_color, atmo_inner_color, smoothstep(0.55, 0.95, f));
	e += atmo * haze * haze * haze * f_aa * 0.22 * atmosphere * atmo_intensity;

	e += accretion_color * lip * 2.0;
	e += atmo_inner_color * pow(max(f, 0.0), 3.0) * f_aa * select * 0.6;
	EMISSION = e;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float direct = clamp(ndl, 0.0, 1.0);
	float air = clamp(atmosphere, 0.0, 1.0);
	float wr = clamp(wrap_amount, 0.0, 1.0) * air;
	float wrapped = clamp((ndl + wr) / max(1.0 + wr, 1.0), 0.0, 1.0);
	vec3 lit = LIGHT_COLOR * ATTENUATION / 3.14159265;
	// The engine multiplies DIFFUSE_LIGHT by ALBEDO afterwards (never multiply it here).
	DIFFUSE_LIGHT += lit * wrapped;
	// Terminator: a DUSK_ROSE band along the day/night line, mostly on the night side (light
	// through the air) — coloured light, in the specular channel so the albedo never darkens it.
	float band = 1.0 - smoothstep(0.0, 0.32, abs(ndl + 0.08));
	SPECULAR_LIGHT += lit * atmo_outer_color * band * terminator_amount * 0.3 * air * v_edge;
	// Scattering: the limb glows ICE on the day side, fading round into the night.
	float f = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float limb = smoothstep(0.55, 1.0, f);
	float day = smoothstep(-0.35, 0.6, ndl);
	SPECULAR_LIGHT += lit * mix(atmo_outer_color, atmo_inner_color, day) * limb * limb * day
			* v_edge * scatter_amount * air;
	// A faint broad sheen on the land, a soft ICE glint on the seas (no mirror highlights).
	vec3 hv = k_safe_normalize(LIGHT + VIEW, NORMAL);
	float ndh = clamp(dot(NORMAL, hv), 0.0, 1.0);
	SPECULAR_LIGHT += lit * pow(max(ndh, 0.0), 24.0) * 0.12 * direct * v_edge;
	SPECULAR_LIGHT += lit * mix(atmo_inner_color, vec3(1.0), 0.4) * pow(max(ndh, 0.0), 70.0)
			* glint_amount * v_sea * direct * v_edge;
}
