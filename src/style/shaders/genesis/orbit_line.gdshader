// KORIUM UNIVERSE — an orbit: a thin line of light that fades along the arc. Owner: art-director.
// Mesh contract (OrbitLine.build_tube, circular orbit in the local XZ plane): UV.x along the orbit
// 0..1 (same direction as the body's motion, angle TAU * UV.x from +Z toward +X), UV.y around the
// tube section. Brightest just behind the body (`head`, 0..1 = the body's position on the orbit),
// fading over `trail` of the loop to a faint `base`. `formation` 0..1 draws the orbit in behind
// the body. Additive, unshaded, no depth write. No TIME.
// Never a "ruler": the tube is rebuilt in the vertex stage as a thin ribbon that always faces the
// camera (a core of ~`line_px` pixels is then cut from it in the fragment stage), centred on the tube axis (recovered from UV: angle TAU * UV.x on the
// circle, section angle TAU * UV.y; `tube_radius` only refines the centre of the two section
// vertices that lie in the orbit plane), so the width is constant on screen at any distance and the
// across coordinate interpolates exactly (no beading per segment). The line fades as the orbit
// plane turns edge-on to the camera (a flat ellipse collapsing into a bar across the frame), and it
// thins out and vanishes within `body_gap` (world units) of the body it carries.
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

#include "res://src/style/shaders/genesis/noise.gdshaderinc"

uniform vec3 color : source_color;
uniform float intensity = 0.45;
uniform float head : hint_range(0.0, 1.0) = 0.0;
// Share of the loop over which the trail fades.
uniform float trail : hint_range(0.01, 1.0) = 0.55;
// Brightness of the rest of the loop (0..1 of the peak).
uniform float base : hint_range(0.0, 1.0) = 0.08;
uniform float formation : hint_range(0.0, 1.0) = 1.0;
// Line width in pixels, and the edge-on fade: |cos| of the angle between the view ray and the
// orbit plane's normal where the line is gone (x) and fully present (y).
uniform float line_px = 1.4;
uniform vec2 edge_on_fade = vec2(0.04, 0.26);
// World distance around the body (at `head`) over which the line thins out and vanishes.
uniform float body_gap = 0.5;
// Section radius of the OrbitLine tube (world units of the mesh): refines the axis estimate.
uniform float tube_radius = 0.02;
// Half-width of the camera-facing ribbon as an angle (radians): must exceed ~line_px pixels.
uniform float ribbon_angle = 0.0028;

// Across coordinate (-1..1, 0 on the axis), view-space orbit-plane normal, orbit radius (world).
varying float v_across;
varying vec3 v_plane;
varying float v_radius;

void vertex() {
	float a = 6.2831853 * UV.x;
	float th = 6.2831853 * UV.y;
	vec3 o = vec3(sin(a), 0.0, cos(a));
	// Axis point of this section (the circle of radius R in the local XZ plane).
	float r_axis = max(dot(VERTEX.xz, o.xz) - tube_radius * cos(th), 1e-3);
	vec3 centre = o * r_axis;
	float scale = max(length(MODEL_MATRIX[0].xyz), 1e-4);
	v_radius = r_axis * scale;
	vec3 c_view = (MODELVIEW_MATRIX * vec4(centre, 1.0)).xyz;
	vec3 t_view = (MODELVIEW_MATRIX * vec4(cos(a), 0.0, -sin(a), 0.0)).xyz;
	vec3 o_view = k_safe_normalize((MODELVIEW_MATRIX * vec4(o, 0.0)).xyz, vec3(1.0, 0.0, 0.0));
	vec3 y_view = k_safe_normalize((MODELVIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz, vec3(0.0, 1.0, 0.0));
	vec3 n_view = k_safe_normalize((MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz, o_view);
	v_plane = y_view;
	// Screen "side" of the line at this point; every section vertex lands on it, spread -1..1.
	vec3 to_eye = k_safe_normalize(-c_view, vec3(0.0, 0.0, 1.0));
	vec3 side = k_safe_normalize(cross(k_safe_normalize(t_view, vec3(1.0, 0.0, 0.0)), to_eye), vec3(0.0, 1.0, 0.0));
	float span = max(max(abs(dot(o_view, side)), abs(dot(y_view, side))), 1e-3);
	float s = clamp(dot(n_view, side) / span, -1.0, 1.0);
	v_across = s;
	// Conservative width (angle): a few pixels at any resolution >= 720p; the fragment cuts the core.
	POSITION = PROJECTION_MATRIX * vec4(c_view + side * s * ribbon_angle * max(-c_view.z, 1e-3), 1.0);
}

void fragment() {
	float behind = fract(head - UV.x);
	float k = 1.0 - clamp(behind / max(trail, 1e-3), 0.0, 1.0);
	float lum = base + (1.0 - base) * k * k;
	// Draw-in: only the part of the loop behind the head that has been traced.
	float traced = 1.0 - smoothstep(formation - 0.02, formation, behind);
	if (formation >= 0.999) {
		traced = 1.0;
	}
	// Constant pixel core across the camera-facing ribbon (built twice over by the section: halved).
	float half_px = max(line_px, 0.5) * 0.5;
	float d_px = abs(v_across) / max(fwidth(v_across), 1e-5);
	float profile = (1.0 - smoothstep(half_px - 0.5, half_px + 0.6, d_px)) * 0.5;
	// Edge-on orbit plane: the ellipse collapses into a bar — let it go.
	float face = abs(dot(k_safe_normalize(v_plane, vec3(0.0, 1.0, 0.0)), VIEW));
	float plane_fade = smoothstep(edge_on_fade.x, max(edge_on_fade.y, edge_on_fade.x + 1e-3), face);
	// Thin out near the body: arc distance to the head in world units.
	float arc = min(behind, 1.0 - behind) * 6.2831853 * v_radius;
	float gap = smoothstep(body_gap * 0.45, max(body_gap, 1e-3), arc);
	ALBEDO = color * lum * intensity * profile * plane_fade * gap * traced;
	ALPHA = 1.0;
}
