// KORIUM UNIVERSE — intent thread (living prototype, Loop 5). Owner: art-director.
// Intention and control, never decoration: MIKU decides -> gesture -> the thread appears -> it
// tenses -> the hand answers -> the task -> it slackens -> it is gone.
//   tension  0..1  relaxed: a wider, faint, translucent fibre (its slack curve comes from the
//                  geometry: the animator's spring curve sags when tension is low); taut: thin,
//                  bright, with glints running from MIKU to the hand and a slight hum (standing
//                  wave fixed at both ends).
//   presence 0..1  the thread is spun out from the origin (MIKU) toward the hand, its front a
//                  bright grain; reversed, it is drawn back into the origin.
//   release  0..1  letting go: the fibre dissolves into grains starting at the origin (the will
//                  lets go first, the hand is the last to know). Reset to 0 for the next use.
//   anger    0..1  MIKU losing her composure: colder, whiter, harder (thin core, little glow), a
//                  faster, higher tremor.
// Width is constant in pixels at any distance: the vertex stage expands a centre-line strip into
// a camera-facing ribbon of `ribbon_px` half-width and the fragment cuts the core and glow from it.
// Mesh contract (built by the thread owner, ArrayMesh or ImmediateMesh, PRIMITIVE_TRIANGLE_STRIP or
// triangles): for every sample i of the curve (>= 2, origin first) TWO vertices at the SAME point
// P_i (the curve itself, no width), UV = (u_i, 0) and (u_i, 1) with u_i 0 (origin) -> 1 (hand), and
// NORMAL = the curve tangent at P_i (any length; it is only a direction). Set a custom_aabb grown by
// a few centimetres (the ribbon is widened on screen). Colours: the fibre leaves MIKU with the tip
// colour of her hair's link strands (MaterialLibrary.hair_link_tip()) and turns into the thread's
// own pearl. Additive, unshaded, no depth write, no TIME (`motion_time` is set by the owner of each
// duplicate).
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

#include "res://src/style/shaders/genesis/noise.gdshaderinc"

uniform vec3 origin_color : source_color;
uniform vec3 calm_color : source_color;
uniform vec3 taut_color : source_color;
uniform vec3 anger_color : source_color;

uniform float tension : hint_range(0.0, 1.0) = 0.0;
uniform float presence : hint_range(0.0, 1.0) = 1.0;
uniform float release : hint_range(0.0, 1.0) = 0.0;
uniform float anger : hint_range(0.0, 1.0) = 0.0;
uniform float motion_time = 0.0;
// Different threads of the same hand set: phase of the hum and of the grains.
uniform float seed = 0.0;
uniform float intensity = 0.85;
// Core width in pixels: relaxed (x) and taut (y); the soft glow around it (px) and its weight.
uniform vec2 width_px = vec2(2.4, 1.1);
uniform float glow_px = 5.0;
uniform float glow = 0.22;
// Peak lateral hum of a taut thread (px, at mid-span).
uniform float vibration_px = 1.4;
// Half-width (px) of the expanded strip: must hold core + glow + hum.
uniform float ribbon_px = 12.0;
// Shares of the thread over which it thins at the origin (x) and at the hand (y).
uniform vec2 end_fade = vec2(0.03, 0.06);

// -1..1 across the strip.
varying float v_across;

void vertex() {
	float side_sign = UV.y * 2.0 - 1.0;
	vec4 c0 = PROJECTION_MATRIX * (MODELVIEW_MATRIX * vec4(VERTEX, 1.0));
	vec4 c1 = PROJECTION_MATRIX * (MODELVIEW_MATRIX * vec4(VERTEX + NORMAL * 0.01, 1.0));
	vec2 vp = max(VIEWPORT_SIZE, vec2(1.0));
	vec2 s0 = c0.xy / max(c0.w, 1e-4) * vp;
	vec2 s1 = c1.xy / max(c1.w, 1e-4) * vp;
	vec2 d = s1 - s0;
	float dl = max(length(d), 1e-5);
	vec2 dir = d / dl;
	vec2 side = vec2(-dir.y, dir.x);

	float u = UV.x;
	float t = clamp(tension, 0.0, 1.0);
	float a = clamp(anger, 0.0, 1.0);
	// Hum: standing waves fixed at both ends; anger adds a faster, higher mode (a tremor).
	float env = sin(3.14159 * u);
	float w = sin(u * 3.14159 * 3.0) * sin(motion_time * (13.0 + 9.0 * a) + seed * 7.0) * 0.65
			+ sin(u * 3.14159 * 7.0 + 1.3) * sin(motion_time * (29.0 + 41.0 * a) + seed * 3.1) * (0.15 + 0.35 * a);
	float vib = vibration_px * t * t * (1.0 + 0.25 * a) * env * w;
	float off_px = side_sign * ribbon_px + vib;
	c0.xy += side * off_px * 2.0 / vp * c0.w;
	POSITION = c0;
	v_across = side_sign;
}

void fragment() {
	float u = UV.x;
	float t = clamp(tension, 0.0, 1.0);
	float a = clamp(anger, 0.0, 1.0);
	float ts = t * t * (3.0 - 2.0 * t);
	float d_px = abs(v_across) * ribbon_px;

	// Core: wide and soft when slack, thin and crisp when taut, thinner still in anger.
	float core_half = max(mix(width_px.x, width_px.y, ts) * 0.5 * mix(1.0, 0.8, a), 0.35);
	float core = 1.0 - smoothstep(core_half - 0.5, core_half + mix(0.9, 0.5, ts), d_px);
	float g_w = max(glow_px * mix(1.2, 0.8, ts) * mix(1.0, 0.4, a), 0.5);
	float gd = d_px / g_w;
	float halo = exp(-gd * gd) * glow * mix(1.0, 0.45, a);
	float ends = smoothstep(0.0, max(end_fade.x, 1e-3), u) * (1.0 - smoothstep(1.0 - max(end_fade.y, 1e-3), 1.0, u));

	// Brightness: a slack thread is faint and uneven (translucent), a taut one bright; glints run
	// from MIKU to the hand while it pulls.
	float slack = 1.0 - (1.0 - ts) * 0.45 * k_vnoise(vec3(u * 14.0 + seed * 13.0, motion_time * 0.25, seed));
	float lum = mix(0.24, 1.0, ts) * mix(1.0, 1.3, a) * slack;
	float glint_d = fract(u * 3.0 - motion_time * mix(0.7, 1.6, a) + seed) - 0.5;
	float glint = exp(-glint_d * glint_d * 160.0) * ts * 0.6;

	// Colour: the hair's tip at the origin -> the thread's pearl; anger chills both.
	vec3 body = mix(calm_color, taut_color, ts);
	body = mix(body, anger_color, a);
	vec3 from = mix(origin_color, anger_color, a * 0.7);
	vec3 col = mix(from, body, smoothstep(0.0, 0.22, u));

	// Presence: spun out from the origin; the front is a bright grain.
	float pr = clamp(presence, 0.0, 1.0);
	float front = pr * 1.1;
	float jag = (k_vnoise(vec3(u * 60.0, seed * 17.0, 0.5)) - 0.5) * 0.03;
	float spun = (1.0 - smoothstep(front - 0.04, front, u + jag)) * smoothstep(0.0, 0.05, pr);
	float fd = (u - front) / 0.025;
	float lip = (pr > 0.001 && pr < 0.999) ? exp(-fd * fd) * 1.4 : 0.0;

	// Release: dissolves into grains from the origin toward the hand.
	float rl = clamp(release, 0.0, 1.0);
	float rfront = rl * 1.15 - 0.1;
	float grains = k_vnoise(vec3(u * 90.0 + seed * 5.0, seed, 1.0));
	float kept = smoothstep(rfront - 0.06, rfront + 0.02, u + (grains - 0.5) * 0.1);
	kept *= 1.0 - smoothstep(0.95, 1.0, rl);
	float rd = (u - rfront) / 0.04;
	float rlip = (rl > 0.001 && rl < 0.95) ? exp(-rd * rd) * grains * 0.8 : 0.0;

	float profile = (core + halo) * ends;
	vec3 e = col * intensity * (lum + glint) * profile;
	e += mix(taut_color, anger_color, a) * (lip + rlip) * core * ends;
	ALBEDO = e * spun * kept;
	ALPHA = 1.0;
}
