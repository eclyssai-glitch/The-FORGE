// KORIUM UNIVERSE — work world (living prototype, Loop 5): a world MIKU builds with her hands, in
// stages, that can fail and be mended. Owner: art-director. Same language as planet_forming (Voronoi
// plates, gold growing edge, night stone, ICE rim) but *built*, not accreted:
//   formation   0..1  the shell is laid course by course along `build_axis` (bottom -> top); in
//                     each course the tiles spread from their centres, their growing edges lit gold;
//                     where the shell is still open the inside shows a dim warm core (a hollow
//                     work in progress, never a hole into space).
//   compression 0..1  matter squeezed by the hands: the shell flattens a little along `press_dir`
//                     (both poles: two hands pressing), seams close, the stone darkens and densifies
//                     and warm rings of pressure run toward the pressed poles.
//   stress      0..1  the structure fails: a share of the tile borders opens into glowing fissures
//                     (white-hot core, copper edge, an unstable shimmer), fine fractures branch from
//                     them and the loosest plates lift off the surface.
//   heal        0..1  mending: the open fissures close and settle into gold kintsugi seams (keep
//                     `stress` at its peak while healing; both back to 0 = a clean world).
// Patterns use the object-space direction (any sphere, no UVs). `detail` = octaves (Quality).
// `motion_time` drives the shimmer and the pressure rings — never TIME. Opaque, double-sided.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

#include "res://src/style/shaders/genesis/noise.gdshaderinc"

uniform float formation : hint_range(0.0, 1.0) = 1.0;
uniform float stress : hint_range(0.0, 1.0) = 0.0;
uniform float compression : hint_range(0.0, 1.0) = 0.0;
uniform float heal : hint_range(0.0, 1.0) = 0.0;

uniform vec3 stone_color : source_color;
uniform vec3 stone_light_color : source_color;
uniform vec3 seam_color : source_color;
uniform vec3 build_color : source_color;
uniform vec3 fissure_hot_color : source_color;
uniform vec3 fissure_edge_color : source_color;
uniform vec3 mend_color : source_color;
uniform vec3 mend_deep_color : source_color;
uniform vec3 core_color : source_color;
uniform vec3 press_color : source_color;
uniform vec3 rim_color : source_color;

// Courses are laid from -build_axis to +build_axis; the hands press along press_dir (object space).
uniform vec3 build_axis = vec3(0.0, 1.0, 0.0);
uniform vec3 press_dir = vec3(1.0, 0.0, 0.0);
uniform float courses = 7.0;
uniform float tile_scale = 3.4;
uniform float seed = 0.0;
uniform int detail : hint_range(1, 5) = 4;
uniform float motion_time = 0.0;
uniform float select : hint_range(0.0, 1.0) = 0.0;
uniform float fissure_glow = 2.2;
// Share of the tile borders that can open under full stress.
uniform float fissure_share : hint_range(0.0, 1.0) = 0.42;
// Largest lift of a loose plate (share of the radius) and the flattening at full compression.
uniform float lift_amount = 0.05;
uniform float squeeze_amount = 0.14;
uniform float rim_intensity = 0.4;

varying vec3 v_dir;

vec3 tile_space(vec3 d) {
	vec3 s = d + vec3(seed * 13.7, seed * 5.3, seed * 9.1);
	return s * tile_scale + (vec3(k_vnoise(s * 2.0 + 5.0), k_vnoise(s * 2.0 + 15.0), k_vnoise(s * 2.0 + 25.0)) - 0.5) * 0.6;
}

void vertex() {
	vec3 d = k_safe_normalize(VERTEX, vec3(0.0, 1.0, 0.0));
	v_dir = d;
	float radius = length(VERTEX);
	// Failing: loose plates lift off along the normal (the most loose first).
	float st = clamp(stress, 0.0, 1.0) * (1.0 - clamp(heal, 0.0, 1.0));
	vec4 vo = k_voronoi2(tile_space(d), 0.85);
	float loose = smoothstep(vo.z * 0.9 + 0.1, vo.z * 0.9 + 0.25, st);
	VERTEX += d * radius * lift_amount * loose * st * fract(vo.z * 7.3);
	// Compression: flattened along the pressing axis, a little smaller overall.
	vec3 pd = k_safe_normalize(press_dir, vec3(1.0, 0.0, 0.0));
	float c = clamp(compression, 0.0, 1.0);
	VERTEX -= pd * dot(VERTEX, pd) * squeeze_amount * c;
	VERTEX *= 1.0 - 0.04 * c;
}

void fragment() {
	vec3 d = v_dir;
	vec3 axis = k_safe_normalize(build_axis, vec3(0.0, 1.0, 0.0));
	vec3 pd = k_safe_normalize(press_dir, vec3(1.0, 0.0, 0.0));
	float c = clamp(compression, 0.0, 1.0);
	float st = clamp(stress, 0.0, 1.0);
	float hl = clamp(heal, 0.0, 1.0);

	// --- Formation: courses along the axis, tiles spreading from their centres. ---
	vec3 tq = tile_space(d);
	vec4 vo = k_voronoi2(tq, 0.85);
	float h = dot(d, axis) * 0.5 + 0.5;
	float n_courses = max(courses, 1.0);
	float course = floor(clamp(h, 0.0, 0.9999) * n_courses);
	float progress = formation * (n_courses + 0.6) - course;
	float grow = clamp((progress - vo.z * 0.7) * 2.5, 0.0, 1.0);
	float build_lip = 0.0;
	if (formation < 0.999) {
		float reach = grow * 1.25;
		if (vo.x > reach) {
			discard;
		}
		build_lip = (1.0 - smoothstep(0.0, 0.06, reach - vo.x)) * step(grow, 0.999);
	}
	// Course joints: a fine line where one course meets the next (masonry, not a planet).
	float hc = fract(clamp(h, 0.0, 0.9999) * n_courses);
	float joint_aa = max(fwidth(hc), 1e-4);
	float joint = (1.0 - smoothstep(joint_aa, joint_aa * 2.5, min(hc, 1.0 - hc))) * (1.0 - c * 0.8);

	// --- Tiles: night stone with per-tile tone and tilt, seams between them. ---
	float edge = vo.y - vo.x;
	float aa = max(fwidth(edge), 1e-4);
	float seam_w = 0.035 * (1.0 - c * 0.45);
	float seam = 1.0 - smoothstep(seam_w - aa, seam_w + aa, edge);
	float tex = k_fbm(tq * 2.7 + 3.0, detail);
	vec3 stone = mix(stone_color, stone_light_color, clamp(0.25 + tex * 0.5 + (vo.z - 0.5) * 0.35, 0.0, 1.0));
	stone *= mix(1.0, 0.6, c);
	vec3 tilt = (k_hash33(vec3(vo.z * 91.0, 3.0, 7.0)) - 0.5) * 0.35 * (1.0 - c * 0.5);
	vec3 tilt_view = (VIEW_MATRIX * MODEL_MATRIX * vec4(tilt, 0.0)).xyz;
	NORMAL = k_safe_normalize(NORMAL + tilt_view, NORMAL);

	// --- Stress: some borders open into fissures; fine fractures branch from them. ---
	float can_open = step(k_edge_hash(vo.z, vo.w), fissure_share);
	float order = k_edge_hash(vo.w + 0.37, vo.z + 0.11);
	float opened = smoothstep(order * 0.8, order * 0.8 + 0.2, st) * can_open;
	float fw = 0.02 + 0.05 * opened;
	float crack = (1.0 - smoothstep(fw - aa, fw + aa, edge)) * opened;
	float fine = k_line(k_ridge(d * 13.0 + vec3(seed)), 0.035) * smoothstep(0.35, 0.9, st)
			* smoothstep(0.55, 0.75, k_vnoise(d * 4.0 + 8.0));
	float fissure = max(crack, fine * 0.7);
	float open_now = fissure * (1.0 - hl);
	float mended = fissure * hl;
	float core_t = 1.0 - smoothstep(0.0, fw * 0.6, edge);
	float shimmer = 0.8 + 0.2 * sin(motion_time * 6.0 + vo.z * 40.0) * sin(motion_time * 2.3 + vo.w * 17.0);

	// --- Compression: pressure rings run toward the pressed poles. ---
	float pole = abs(dot(d, pd));
	float ring_p = pole * 18.0 + motion_time * 2.5;
	float ring = smoothstep(0.9, 1.0, sin(ring_p)) * smoothstep(0.45, 0.95, pole);
	float cap = smoothstep(0.8, 1.0, pole);

	vec3 albedo = mix(stone, seam_color, seam * 0.7);
	albedo = mix(albedo, mend_deep_color, mended * 0.85);
	albedo = mix(albedo, stone_color * 0.4, open_now);
	ALBEDO = albedo;
	ROUGHNESS = mix(0.62 - c * 0.12, 0.35, mended);
	METALLIC = mended * 0.6;
	SPECULAR = 0.35;

	float nv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float f = 1.0 - nv;
	float f_aa = 1.0 - smoothstep(0.1, 0.4, fwidth(f));
	vec3 e = vec3(0.0);
	if (FRONT_FACING) {
		e += rim_color * smoothstep(0.45, 1.0, f) * smoothstep(0.45, 1.0, f) * f_aa * rim_intensity;
		e += seam_color * joint * 0.25;
		e += build_color * build_lip * 1.6;
		vec3 fiss = mix(fissure_edge_color, fissure_hot_color, core_t);
		e += fiss * open_now * fissure_glow * shimmer;
		e += mix(mend_deep_color, mend_color, 0.4) * mended * (0.25 + 0.5 * hl * (1.0 - hl) * 4.0);
		e += press_color * c * (ring * 0.4 + cap * cap * 0.9);
		e += rim_color * pow(max(f, 0.0), 3.0) * select * 0.6;
	} else {
		// The inside of an open shell: a dim warm core, hotter when compressed.
		ALBEDO = stone_color * 0.3;
		e += core_color * (0.12 + 0.55 * c + 0.4 * st * (1.0 - hl)) * (0.6 + 0.4 * k_fbm(d * 3.0 + motion_time * 0.05, 2));
	}
	EMISSION = e;
}
