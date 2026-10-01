// KORIUM UNIVERSE — MIKU's body: matte luminous porcelain. Owner: art-director.
// Votive statuary, not vinyl: a matte pearl dielectric (roughness ~0.5, low broad specular) with a
// very low-contrast marbling. Light wraps round the form and the band just past the terminator
// takes a warm BLUSH scatter (porcelain lets light through: its shadows are warm, never grey-lilac).
// A grazing sheen pearl -> rose -> pale gold lives only at grazing angles, and every view-dependent
// term is anti-aliased (fwidth of the fresnel and of the normal): no bright one-pixel "sticker"
// outline on the silhouette, no sparkle along sharp folds. A faint inner light (`awaken`, `breath`)
// makes the porcelain read as lit from within.
// Statuary, not carving: on the face the shading normal leans toward the head's ellipsoid
// (`face_soften`) and the baked AO is lighter (`face_ao`), so eyelids, brow and lips read as soft
// masses instead of incised lines; on the bodice the shading normal leans toward the torso's
// round form (`torso_soften`), which melts decimation facets while the broad pleats stay.
// Below `dissolve_top` (object Y) the skirt turns into light: noise eats it downward into grains
// with a luminous lip (never a hard hem); `dissolve_top` <= `dissolve_bottom` disables it.
// Awakening (`reveal` 0..1): the porcelain exists only within a radius that grows from the seed on
// her brow (`reveal_origin`, object space) out to `reveal_reach`; the front is broken by noise and
// carries a soft luminous edge (gold -> pearl). Opaque (discard), so nothing behind the surface —
// the inner wall of the skirt — ever shows; 1 = whole figure, no edge.
// The engine multiplies DIFFUSE_LIGHT by ALBEDO after light(): light() never multiplies by ALBEDO
// itself (that squared the albedo); coloured light that must not take the albedo (the BLUSH
// scatter) goes to SPECULAR_LIGHT.
// Vertex colour red = baked ambient occlusion (white when the mesh has none).
// Works without UVs (sculpted meshes): every pattern is in object space. No TIME.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

#include "res://src/style/shaders/genesis/noise.gdshaderinc"

uniform vec3 pearl_color : source_color;
uniform vec3 blush_color : source_color;
uniform vec3 rose_color : source_color;
uniform vec3 gold_color : source_color;
// Occluded porcelain: a warm dusk, never grey.
uniform vec3 shadow_color : source_color;

// Albedo of the lit porcelain (share of the pearl/blush marble).
uniform float albedo_level : hint_range(0.0, 1.0) = 0.56;
uniform float roughness_amount : hint_range(0.0, 1.0) = 0.52;
// Specular reflectance scale (0.5 = F0 0.04, a plain dielectric). Kept low: matte porcelain.
uniform float specular_amount : hint_range(0.0, 1.0) = 0.28;
// Light wrap past the terminator (0 = Lambert) and the warm scatter carried by that band.
uniform float wrap_amount : hint_range(0.0, 1.0) = 0.5;
uniform float scatter_amount : hint_range(0.0, 2.0) = 0.9;
// Directional shadows never go black on porcelain: a share of the light passes through, BLUSH-tinted
// (also softens the shadow-map staircase). Point/spot lights keep their own falloff.
uniform float shadow_lift : hint_range(0.0, 1.0) = 0.3;
// Grazing sheen (emission, fresnel-weighted, anti-aliased).
uniform float sheen = 0.55;
// Inner light of the porcelain (emission, strongest on the thin silhouette).
uniform float inner_glow = 0.05;
// Fake subsurface: warm light passing through the thin silhouette (view-dependent emission).
uniform float backlight_amount = 0.22;
// Soft fill of the porcelain's micro-hollows: a faint BLUSH light where the baked AO darkens
// (light scattered inside the porcelain reaches the folds), so grooves never read as cuts.
uniform float hollow_fill = 0.06;
// Baked AO from vertex colour red (0 = ignore).
uniform float ao_strength : hint_range(0.0, 1.0) = 1.0;
// Marbling scale in object units (MIKU is ~6 u tall).
uniform float marble_scale = 1.3;
// 0 = dormant porcelain (cold, no inner light) -> 1 awake.
uniform float awaken : hint_range(0.0, 1.0) = 1.0;
// Breathing 0..1 (animator: sine of Palette.T_BREATH over MotionClock).
uniform float breath : hint_range(0.0, 1.0) = 0.5;
// Hover / selection: pearl rim.
uniform float select : hint_range(0.0, 1.0) = 0.0;

group_uniforms statuary;
// Head ellipsoid (object space): centre and radii; the face's shading normal leans toward it.
uniform vec3 head_center = vec3(-0.04, 1.4, 0.13);
uniform vec3 head_radii = vec3(0.25, 0.38, 0.33);
// Share of the face's shading normal taken from the ellipsoid (0 = raw sculpt).
uniform float face_soften : hint_range(0.0, 1.0) = 0.5;
// Baked AO strength on the face (share of ao_strength): the eyes and lips are masses, not holes.
uniform float face_ao : hint_range(0.0, 1.0) = 0.35;
// Torso front (bodice): horizontal share of the shading normal taken from the round torso around
// the vertical axis through (torso_axis.x, torso_axis.y) (object x, z).
uniform float torso_soften : hint_range(0.0, 1.0) = 0.4;
uniform vec2 torso_axis = vec2(0.0, 0.0);

group_uniforms dissolve;
// Object-space heights: solid porcelain at/above dissolve_top, fully dissolved at dissolve_bottom.
uniform float dissolve_top = -1.7;
uniform float dissolve_bottom = -4.35;
// Noise scale of the dissolving front (object units) and of the grains it breaks into.
uniform float dissolve_scale = 1.6;
uniform float grain_scale = 30.0;
// Light of the dissolving lip and how luminous the porcelain grows as it turns into light.
uniform float lip_intensity = 0.7;
uniform float light_turn = 0.8;
uniform float motion_time = 0.0;
uniform float flow_speed = 0.03;

group_uniforms reveal;
// 0 = nothing, 1 = the whole figure (no front, no edge). Radial from reveal_origin.
uniform float reveal : hint_range(0.0, 1.0) = 1.0;
// Seed on the brow (object space; the sculpt's "forehead" anchor) and the distance covered at 1.
uniform vec3 reveal_origin = vec3(0.001, 1.5145, 0.4168);
uniform float reveal_reach = 6.4;
// Width of the luminous edge (object units), its brightness and the noise breaking the front.
uniform float reveal_edge = 0.32;
uniform float reveal_glow = 1.1;
uniform float reveal_noise = 1.3;
uniform vec3 reveal_color : source_color;

varying vec3 v_obj;
// Face weight (0..1) written in vertex(), read in fragment() (lighter AO on the face).
varying float v_face;
// 1 inside the surface, -> 0 on the silhouette ring and along sharp folds (fresnel/normal jump per
// pixel): damps the grazing light so outlines never stair-step. Written in fragment(), read in light().
varying float v_edge;

void vertex() {
	vec3 p = VERTEX;
	v_obj = p;
	vec3 n = NORMAL;
	// Face: inside the head ellipsoid, on its front, between chin and hairline (the sculpted hair
	// mass on the crown keeps its own grooves).
	vec3 hr = max(head_radii, vec3(0.05));
	vec3 e = (p - head_center) / hr;
	float d = length(e);
	float wf = (1.0 - smoothstep(0.85, 1.2, d)) * smoothstep(0.1, 0.24, p.z)
			* (1.0 - smoothstep(1.56, 1.68, p.y)) * smoothstep(1.06, 1.18, p.y);
	vec3 hr2 = max(hr * hr, vec3(1e-3));
	vec3 ne = k_safe_normalize((p - head_center) / hr2, n);
	n = k_safe_normalize(mix(n, ne, wf * face_soften), n);
	// Bodice front: keep the mesh's vertical tilt (the pleats), take part of the horizontal
	// direction from the round torso (melts decimation facets).
	float wt = smoothstep(-0.7, -0.35, p.y) * (1.0 - smoothstep(0.95, 1.12, p.y))
			* (1.0 - smoothstep(0.3, 0.5, abs(p.x))) * smoothstep(-0.05, 0.12, p.z);
	vec2 hz = vec2(p.x - torso_axis.x, p.z - torso_axis.y);
	vec2 hd = hz / max(length(hz), 1e-4);
	float ny = clamp(n.y, -1.0, 1.0);
	vec3 nt = vec3(hd.x, 0.0, hd.y) * sqrt(max(1.0 - ny * ny, 0.0)) + vec3(0.0, ny, 0.0);
	n = k_safe_normalize(mix(n, nt, wt * torso_soften), n);
	NORMAL = n;
	v_face = wf;
}

void fragment() {
	// --- Awakening: radial reveal from the seed, opaque (discard) with a luminous edge ---
	float reveal_e = 0.0;
	if (reveal < 0.999) {
		float rn = k_fbm(v_obj * reveal_noise + 11.0, 3) - 0.5;
		float edge_w = max(reveal_edge, 1e-3);
		float dist = length(v_obj - reveal_origin) + rn * edge_w * 1.6;
		float front = reveal * (reveal_reach + edge_w * 2.0);
		if (dist > front) {
			discard;
		}
		reveal_e = 1.0 - smoothstep(0.0, edge_w, front - dist);
	}

	// --- Dissolve (skirt -> light -> grains) ---
	float dh = clamp((dissolve_top - v_obj.y) / max(dissolve_top - dissolve_bottom, 1e-3), 0.0, 1.0);
	dh = (dissolve_top > dissolve_bottom) ? dh : 0.0;
	float lip = 0.0;
	if (dh > 0.0) {
		vec3 q = vec3(v_obj.x, v_obj.y + motion_time * flow_speed, v_obj.z);
		// Broad front (fbm) broken into grains (high-frequency value noise) as it sinks.
		float n = k_fbm(q * dissolve_scale, 3) * mix(0.8, 0.35, dh)
				+ k_vnoise(q * grain_scale) * mix(0.2, 0.65, dh);
		float thr = dh * 1.08 - 0.04;
		if (n < thr) {
			discard;
		}
		lip = 1.0 - smoothstep(0.0, 0.035, n - thr);
	}

	float raw_ao = COLOR.r;
	float ao = mix(1.0, raw_ao, ao_strength * mix(1.0, face_ao, clamp(v_face, 0.0, 1.0)));
	float nv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float f = 1.0 - nv;
	// Where the fresnel or the normal jumps by a large share per pixel (the silhouette ring, a sharp
	// fold, a decimation crease) the grazing terms fade out instead of drawing bright pixels.
	float jump = max(fwidth(f), length(fwidth(NORMAL)) * 0.6);
	float f_aa = 1.0 - smoothstep(0.06, 0.3, jump);
	v_edge = f_aa;

	float marble = k_vnoise(v_obj * marble_scale) * 0.65 + k_vnoise(v_obj * marble_scale * 3.1) * 0.35;
	vec3 base = mix(pearl_color, blush_color, 0.25 + smoothstep(0.35, 0.85, marble) * 0.35);
	base = mix(shadow_color, base * albedo_level, mix(0.45, 1.0, ao));

	ALBEDO = base;
	ROUGHNESS = clamp(roughness_amount + (marble - 0.5) * 0.06, 0.0, 1.0);
	SPECULAR = specular_amount;
	METALLIC = 0.0;
	AO = ao;
	AO_LIGHT_AFFECT = 0.25;

	// Grazing sheen: only past ~60 degrees, smooth ramp, anti-aliased.
	float graze = smoothstep(0.45, 0.95, f) * f_aa;
	vec3 irid = mix(pearl_color, rose_color, smoothstep(0.55, 0.8, f));
	irid = mix(irid, gold_color, smoothstep(0.8, 0.97, f) * 0.6);
	float wake = mix(0.25, 1.0, awaken);
	vec3 sheen_e = irid * graze * graze * sheen * wake * ao;
	vec3 inner_e = mix(pearl_color, blush_color, 0.4) * inner_glow * awaken
			* (0.8 + 0.4 * breath) * mix(0.3, 1.0, f * f_aa) * ao;
	vec3 trans_e = mix(blush_color, rose_color, 0.3) * smoothstep(0.4, 0.95, f) * f_aa
			* backlight_amount * wake * ao;
	// Hollows: the darker the baked AO, the more warm scattered light fills it (never a black cut).
	vec3 hollow_e = blush_color * (1.0 - raw_ao) * hollow_fill * wake;
	vec3 select_e = pearl_color * f * f * f_aa * select * 0.6;
	// The skirt turning into light: warmer and brighter toward the front, a luminous lip.
	vec3 light_e = mix(pearl_color, blush_color, 0.5) * light_turn * smoothstep(0.0, 0.8, dh) * wake
			+ mix(gold_color, pearl_color, 0.45) * lip * lip_intensity * wake;
	// Awakening edge: gold at the front, pearl just behind it.
	vec3 reveal_c = mix(pearl_color, reveal_color, reveal_e);
	EMISSION = sheen_e + inner_e + trans_e + hollow_e + select_e + light_e
			+ reveal_c * reveal_e * reveal_e * reveal_glow;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float w = clamp(wrap_amount, 0.0, 1.0);
	float direct = clamp(ndl, 0.0, 1.0);
	float wrapped = clamp((ndl + w) / max(1.0 + w, 1.0), 0.0, 1.0);
	// The band the wrap adds beyond the terminator: light scattered through the porcelain.
	float scatter = max(wrapped - direct, 0.0);
	float edge = mix(0.55, 1.0, v_edge);
	vec3 pass = vec3(ATTENUATION);
	if (LIGHT_IS_DIRECTIONAL) {
		pass = mix(blush_color * shadow_lift, vec3(1.0), ATTENUATION);
	}
	vec3 lit = LIGHT_COLOR * pass * edge / 3.14159265;
	// The engine multiplies DIFFUSE_LIGHT by ALBEDO afterwards (never multiply it here).
	DIFFUSE_LIGHT += lit * wrapped;
	// The warm scatter keeps its own colour (not the albedo's): specular channel.
	SPECULAR_LIGHT += lit * blush_color * scatter * scatter_amount * 0.32;
	// Broad, low specular (normalised Blinn-Phong; exponent from roughness): no latex highlights.
	vec3 hv = k_safe_normalize(LIGHT + VIEW, NORMAL);
	float ndh = clamp(dot(NORMAL, hv), 0.0, 1.0);
	float r = clamp(ROUGHNESS, 0.05, 1.0);
	float shin = max(2.0 / max(r * r * r * r, 1e-6) - 2.0, 1.0);
	float lh = clamp(dot(LIGHT, hv), 0.0, 1.0);
	float f0 = 0.08 * specular_amount;
	float fres = f0 + (1.0 - f0) * pow(max(1.0 - lh, 0.0), 5.0);
	float spec = pow(max(ndh, 0.0), max(shin, 1.0)) * (shin + 8.0) / 25.1327 * fres * direct;
	SPECULAR_LIGHT += LIGHT_COLOR * ATTENUATION * edge * spec / 3.14159265;
}
