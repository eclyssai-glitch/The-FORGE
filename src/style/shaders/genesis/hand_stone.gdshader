// KORIUM UNIVERSE — the auxiliary hands: night stone with kintsugi. Owner: art-director.
// Polished deep-blue basalt (clearcoat) carved out of the night sky: pin-point stars inside the
// stone (object space, so they stay put when the hand moves) and gold kintsugi veins from ridged
// Voronoi borders (only a few of them). The gold is always there as a dull metal inlay; `veins` 0..1 spreads the lit part of
// the network and makes it glow (the hands light up while they work). Vertex colour red = baked AO
// (white when the mesh has none). No UVs needed. `motion_time` (MotionClock) lets light flow
// along lit veins — never TIME.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://src/style/shaders/genesis/noise.gdshaderinc"

uniform vec3 stone_color : source_color;
uniform vec3 stone_light_color : source_color;
uniform vec3 star_color : source_color;
uniform vec3 gold_color : source_color;
uniform vec3 gold_deep_color : source_color;

// 0..1: kintsugi lit (spread + glow).
uniform float veins : hint_range(0.0, 1.0) = 0.0;
// Vein network scale (cells per object unit; hands are ~7 u) and width (ridge units).
uniform float vein_scale = 1.0;
uniform float vein_width : hint_range(0.0, 0.3) = 0.022;
uniform float vein_glow = 1.1;
// Share of single cell borders that are mended branches (the rest of the network is absent), and
// the scale (per object unit) of the long fracture paths the main cracks follow.
uniform float vein_share : hint_range(0.0, 1.0) = 0.16;
uniform float vein_path_scale = 0.26;
// Stars in the stone.
uniform float star_scale = 9.0;
uniform float star_density : hint_range(0.0, 1.0) = 0.18;
uniform float star_intensity = 1.6;
uniform float roughness_amount : hint_range(0.0, 1.0) = 0.3;
uniform float clearcoat_amount : hint_range(0.0, 1.0) = 0.6;
uniform float ao_strength : hint_range(0.0, 1.0) = 1.0;
uniform float motion_time = 0.0;
uniform float select : hint_range(0.0, 1.0) = 0.0;

varying vec3 v_obj;

void vertex() {
	v_obj = VERTEX;
}

void fragment() {
	float ao = mix(1.0, COLOR.r, ao_strength);
	float nv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);

	// Stone body: deep blue with slow, low-contrast strata.
	float strata = k_fbm(v_obj * vec3(0.35, 0.9, 0.35), 3);
	vec3 stone = mix(stone_color, stone_light_color, smoothstep(0.35, 0.8, strata) * 0.55);

	// Kintsugi: borders of warped Voronoi cells (a mended ceramic crack pattern). Only a few
	// borders are mended cracks: those along a couple of long fracture paths (a low-frequency
	// ridge through the whole hand) plus a small share of single borders chosen by their own
	// hash (short branches). The rest of the network does not exist: plain stone, no grid.
	vec3 q = v_obj * vein_scale;
	q += (vec3(k_vnoise(q * 1.3), k_vnoise(q * 1.3 + 11.3), k_vnoise(q * 1.3 + 23.9)) - 0.5) * 0.7;
	vec4 vo = k_voronoi2(q, 0.9);
	float edge = vo.y - vo.x;
	float aa = max(fwidth(edge), 1e-4);
	// Width varies along the crack (hand-applied lacquer).
	float wv = vein_width * (0.55 + 0.9 * k_vnoise(q * 3.0 + 5.0));
	float crack = 1.0 - smoothstep(wv - aa, wv + aa, edge);
	float path = k_ridge(v_obj * vein_path_scale + vec3(3.1, 7.7, 1.9));
	float on_path = smoothstep(0.74, 0.86, path);
	float branch = step(k_edge_hash(vo.z, vo.w), vein_share);
	float gate = max(on_path, branch);
	float gold_mask = crack * gate;

	// Which part of the network is lit: grows from low-frequency islands as `veins` rises.
	float spread = k_vnoise(v_obj * 0.18 + 7.7);
	float lit = smoothstep(spread - 0.08, spread + 0.08, veins * 1.15 - 0.05) * veins;
	float flow = 0.75 + 0.25 * sin(motion_time * 0.9 + (v_obj.x + v_obj.y * 0.6) * 1.3);

	ALBEDO = mix(stone, gold_deep_color, gold_mask * 0.85) * mix(0.55, 1.0, ao);
	METALLIC = gold_mask * 0.9;
	ROUGHNESS = mix(roughness_amount + (strata - 0.5) * 0.12, 0.28, gold_mask);
	SPECULAR = 0.55;
	CLEARCOAT = clearcoat_amount * (1.0 - gold_mask);
	CLEARCOAT_ROUGHNESS = 0.12;
	AO = ao;
	AO_LIGHT_AFFECT = 0.4;

	float px = length(fwidth(v_obj)) * star_scale;
	float stars = k_stars(v_obj * star_scale, star_density, 0.09, px)
			+ k_stars(v_obj * star_scale * 2.7 + 3.1, star_density * 0.6, 0.07, px * 2.7) * 0.5;
	vec3 e = star_color * stars * star_intensity * (1.0 - gold_mask) * mix(0.4, 1.0, ao);
	// Lit gold stays saturated: the glow ramps deep gold -> gold instead of pushing to white.
	e += mix(gold_deep_color, gold_color, lit * 0.8) * gold_mask * (0.04 + lit * vein_glow * flow);
	e += stone_light_color * pow(1.0 - nv, 3.0) * select * 0.8;
	EMISSION = e;
}
