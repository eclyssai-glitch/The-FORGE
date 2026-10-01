// KORIUM UNIVERSE — the auxiliary hands: night stone with kintsugi. Owner: art-director.
// Legible night stone, not black latex: a STONE basalt body lifted by slow strata, with *depth* —
// a faint nebular cloud and a layer of stars seen a little inside the stone (parallax along the view
// ray, object space, so they stay put when the hand moves) — a thin anti-aliased ICE rim that
// draws the form against the night, and a light satin finish (low clearcoat, no mirror highlights).
// Gold kintsugi veins from ridged Voronoi borders (only a few of them) are always visible as a dim
// gold inlay; `veins` 0..1 spreads the lit part of the network and makes it glow (the hands light up
// while they work). The forearm dissolves into grains from the wrist (`wrist_point` ->
// `forearm_end`, object space, see MaterialLibrary.set_hand_wrist); equal points disable it.
// Vertex colour red = baked AO (white when the mesh has none). No UVs needed. `motion_time`
// (MotionClock) lets light flow along lit veins — never TIME.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://src/style/shaders/genesis/noise.gdshaderinc"

uniform vec3 stone_color : source_color;
uniform vec3 stone_light_color : source_color;
uniform vec3 star_color : source_color;
uniform vec3 gold_color : source_color;
uniform vec3 gold_deep_color : source_color;
// Cold rim that draws the silhouette, and the nebular depth inside the stone.
uniform vec3 rim_color : source_color;
uniform vec3 depth_color : source_color;

// 0..1: kintsugi lit (spread + glow).
uniform float veins : hint_range(0.0, 1.0) = 0.0;
// Vein network scale (cells per object unit; hands are ~7 u) and width (ridge units).
uniform float vein_scale = 1.0;
uniform float vein_width : hint_range(0.0, 0.3) = 0.024;
uniform float vein_glow = 1.1;
// Dim gold of the unlit inlay (emission share: always readable, never lit).
uniform float vein_rest = 0.16;
// Share of single cell borders that are mended branches (the rest of the network is absent), and
// the scale (per object unit) of the long fracture paths the main cracks follow.
uniform float vein_share : hint_range(0.0, 1.0) = 0.16;
uniform float vein_path_scale = 0.26;
// Stars in the stone.
uniform float star_scale = 9.0;
uniform float star_density : hint_range(0.0, 1.0) = 0.18;
uniform float star_intensity = 1.6;
// Depth of the inner layer (object units along the view ray) and its glow.
uniform float depth_offset = 0.45;
uniform float depth_glow = 0.09;
uniform float rim_intensity = 0.55;
// Fine relief of the stone (breaks smooth latex highlights), strength and scale (object units).
uniform float bump_strength = 0.35;
uniform float bump_scale = 5.0;
uniform float roughness_amount : hint_range(0.0, 1.0) = 0.56;
uniform float clearcoat_amount : hint_range(0.0, 1.0) = 0.14;
uniform float ao_strength : hint_range(0.0, 1.0) = 1.0;
uniform float motion_time = 0.0;
uniform float select : hint_range(0.0, 1.0) = 0.0;

group_uniforms wrist;
// Object-space wrist centre and forearm end (the stone dissolves along wrist -> forearm_end), and
// the share of that segment where the dissolve starts (x) and where nothing is left (y).
uniform vec3 wrist_point = vec3(0.0);
uniform vec3 forearm_end = vec3(0.0);
uniform vec2 wrist_fade = vec2(0.05, 0.85);
uniform float wrist_grain = 15.0;

varying vec3 v_obj;
// Object-space view ray (camera -> vertex), for the parallax of the inner layer.
varying vec3 v_eye;

void vertex() {
	v_obj = VERTEX;
	vec3 cam_obj = (inverse(MODEL_MATRIX) * vec4(CAMERA_POSITION_WORLD, 1.0)).xyz;
	v_eye = VERTEX - cam_obj;
}

void fragment() {
	// --- Wrist: the forearm dissolves into grains of stone (never a cylinder cut). ---
	vec3 arm = forearm_end - wrist_point;
	float arm_len = length(arm);
	float lip = 0.0;
	if (arm_len > 1e-3) {
		float s = dot(v_obj - wrist_point, arm) / max(arm_len * arm_len, 1e-6);
		float dh = clamp((s - wrist_fade.x) / max(wrist_fade.y - wrist_fade.x, 1e-3), 0.0, 1.0);
		if (dh > 0.0) {
			float n = k_fbm(v_obj * 0.8, 3) * mix(0.75, 0.3, dh) + k_vnoise(v_obj * wrist_grain) * mix(0.25, 0.7, dh);
			float thr = dh * 1.08 - 0.04;
			if (n < thr) {
				discard;
			}
			lip = (1.0 - smoothstep(0.0, 0.04, n - thr)) * smoothstep(0.0, 0.15, dh);
		}
	}

	float ao = mix(1.0, COLOR.r, ao_strength);
	// Stone relief: gradient of value noise (object space, finite differences) bends the normal.
	vec3 bq = v_obj * bump_scale;
	float b0 = k_vnoise(bq);
	vec3 bg = vec3(k_vnoise(bq + vec3(0.07, 0.0, 0.0)), k_vnoise(bq + vec3(0.0, 0.07, 0.0)),
			k_vnoise(bq + vec3(0.0, 0.0, 0.07))) - b0;
	vec3 bg_view = (VIEW_MATRIX * MODEL_MATRIX * vec4(bg / 0.07, 0.0)).xyz;
	NORMAL = k_safe_normalize(NORMAL - (bg_view - NORMAL * dot(bg_view, NORMAL)) * bump_strength * 0.1, NORMAL);
	float nv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float f = 1.0 - nv;
	float f_aa = 1.0 - smoothstep(0.1, 0.4, fwidth(f));

	// Stone body: deep blue with slow, low-contrast strata.
	float strata = k_fbm(v_obj * vec3(0.35, 0.9, 0.35), 3);
	vec3 stone = mix(stone_color, stone_light_color, 0.2 + smoothstep(0.3, 0.8, strata) * 0.6);

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

	ALBEDO = mix(stone, mix(gold_deep_color, gold_color, 0.3), gold_mask * 0.85) * mix(0.55, 1.0, ao);
	METALLIC = gold_mask * 0.6;
	ROUGHNESS = mix(roughness_amount + (strata - 0.5) * 0.12, 0.32, gold_mask);
	SPECULAR = 0.35;
	CLEARCOAT = clearcoat_amount * (1.0 - gold_mask);
	CLEARCOAT_ROUGHNESS = 0.3;
	AO = ao;
	AO_LIGHT_AFFECT = 0.4;

	// Depth: a nebular cloud and fainter stars a little inside the stone (parallax).
	vec3 ray = k_safe_normalize(v_eye, vec3(0.0, 0.0, -1.0));
	vec3 inner = v_obj + ray * depth_offset;
	float cloud = smoothstep(0.35, 0.8, k_fbm(inner * 0.7 + 13.0, 3));
	float px = length(fwidth(v_obj)) * star_scale;
	float stars = k_stars(v_obj * star_scale, star_density, 0.09, px)
			+ k_stars(inner * star_scale * 1.6 + 3.1, star_density * 0.7, 0.07, px * 1.6) * 0.45;
	float body = (1.0 - gold_mask) * mix(0.4, 1.0, ao);
	vec3 e = star_color * stars * star_intensity * body;
	e += depth_color * cloud * depth_glow * body * mix(1.0, 0.6, f);
	// Cold rim drawing the silhouette against the night (smooth, never a stair-stepped outline).
	e += rim_color * smoothstep(0.35, 1.0, f) * smoothstep(0.35, 1.0, f) * f_aa * rim_intensity * mix(0.5, 1.0, ao);
	// Gold: always a dim inlay; lit gold stays saturated (deep gold -> gold, never white).
	e += mix(gold_deep_color, gold_color, 0.25 + lit * 0.6) * gold_mask * (vein_rest + lit * vein_glow * flow);
	e += stone_light_color * pow(max(1.0 - nv, 0.0), 3.0) * select * 0.8;
	// Dissolving edge at the wrist: a faint cold glow (mist), not fire.
	e += rim_color * lip * 0.5;
	EMISSION = e;
}
