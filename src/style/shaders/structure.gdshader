// KORIUM UNIVERSE — structure segments (FragmentStructure MultiMesh, use_custom_data = true).
// Owner: art-director. Colours are fed by MaterialLibrary from Palette; no colour literals here.
//
// Per instance (INSTANCE_CUSTOM, read in vertex, passed flat to fragment):
//   r = assembly 0..1   (0 loose raw fragment, 1 seated in its layer)
//   g = verify flash 0..1 (PALE)
//   b = selection / hover highlight 0..1 (BONE, never EMBER: selecting is not energy)
//   a = build energy 0..1 (EMBER on the edges while the fragment is being assembled)
// Material-wide: finish, scan_y, scan_strength, final_lock, energy (see uniforms).
//
// Edges come from the segment UVs (0..1 per face, guaranteed by MeshBuilder): distance to the
// nearest UV border is converted to screen pixels, giving hairlines of constant width and a
// narrow world-sized chamfer that catches the light. Cost: a handful of derivatives, no textures.
// Opaque on purpose (see docs/VISUAL_DIRECTION.md, "Materiais").
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

group_uniforms palette;
uniform vec3 raw_color : source_color;
uniform vec3 finished_color : source_color;
uniform vec3 edge_color : source_color;
uniform vec3 ember_color : source_color;
uniform vec3 pale_color : source_color;
uniform vec3 select_color : source_color;

group_uniforms state;
// 0 raw (light matte grey) -> 1 finished (dark metal, medium roughness, fine edges).
uniform float finish : hint_range(0.0, 1.0) = 0.0;
// World-space Y of the verification sweep, and its strength (PALE band).
uniform float scan_y = -100.0;
uniform float scan_strength : hint_range(0.0, 1.0) = 0.0;
// Final form: discreet EMBER hairlines along the arcs only (continuous rings, no outlines).
uniform float final_lock : hint_range(0.0, 1.0) = 0.0;
// Global power: scales every EMBER term (nothing glows warm without energy).
uniform float energy : hint_range(0.0, 1.0) = 1.0;

group_uniforms look;
uniform float edge_px : hint_range(0.5, 3.0) = 1.1;
uniform float chamfer_m : hint_range(0.0, 0.1) = 0.022;
uniform float scan_half_width : hint_range(0.02, 1.0) = 0.16;
uniform float ember_edge_energy = 3.2;
uniform float lock_edge_share : hint_range(0.0, 1.0) = 0.32;
uniform float pale_edge_energy = 2.4;

varying flat vec4 v_custom;
varying vec3 v_world;

void vertex() {
	v_custom = INSTANCE_CUSTOM;
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float assembly = clamp(v_custom.r, 0.0, 1.0);
	float flash = clamp(v_custom.g, 0.0, 1.0);
	float highlight = clamp(v_custom.b, 0.0, 1.0);
	float build = clamp(v_custom.a, 0.0, 1.0);

	// --- Edge distance in pixels (UV borders of the current face) ---
	vec2 uv_px = max(fwidth(UV), vec2(1e-5));
	vec2 to_border = min(UV, 1.0 - UV);
	vec2 d_px2 = to_border / uv_px;
	float d_px = min(d_px2.x, d_px2.y);
	// Fade lines out when the face is only a few pixels wide (no shimmering far away).
	float face_px = 1.0 / max(uv_px.x, uv_px.y);
	float far_fade = smoothstep(5.0, 14.0, face_px);
	float line = (1.0 - smoothstep(edge_px - 0.5, edge_px + 0.5, d_px)) * far_fade;
	// Arc lines only (v borders: top/bottom contour of walls, inner/outer rim of caps). They
	// join across segments into continuous circles — used by the final lock, never a full outline.
	float arc_line = (1.0 - smoothstep(edge_px - 0.5, edge_px + 0.5, d_px2.y)) * far_fade;
	// World-sized chamfer: metres -> pixels using the world footprint of one pixel.
	float m_per_px = max(0.5 * (length(dFdx(v_world)) + length(dFdy(v_world))), 1e-5);
	float chamfer_px = max(chamfer_m / m_per_px, edge_px + 0.5);
	float chamfer = 1.0 - smoothstep(0.0, chamfer_px, d_px);

	// --- Surface: raw matte grey -> dark metal. Loose fragments stay raw. ---
	float f = clamp(finish, 0.0, 1.0) * assembly;
	vec3 albedo = mix(raw_color, finished_color, f);
	// Raw: faint darker seams read the cut. Finished: light-catching lighter hairline.
	albedo *= 1.0 - 0.28 * line * (1.0 - f);
	albedo = mix(albedo, edge_color, (0.10 * chamfer + 0.30 * line) * f);
	ALBEDO = albedo;
	METALLIC = mix(0.0, 0.74, f);
	ROUGHNESS = mix(0.9, 0.44, f) - 0.18 * chamfer * f;
	SPECULAR = mix(0.35, 0.5, f);

	// --- Emission (every term has a narrative owner) ---
	float nv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float fres = pow(1.0 - nv, 3.0);
	vec3 emit = vec3(0.0);

	// EMBER: only where energy flows (assembly, final lock), scaled by global power.
	float power = clamp(energy, 0.0, 1.0);
	emit += ember_color * build * power * (line * ember_edge_energy + chamfer * 0.35 + 0.05);
	float lock = clamp(final_lock, 0.0, 1.0) * f * power;
	emit += ember_color * lock * arc_line * ember_edge_energy * lock_edge_share;

	// PALE: verification sweep band (world Y) and per-segment check flash.
	float dy = (v_world.y - scan_y) / scan_half_width;
	float band = exp(-dy * dy) * clamp(scan_strength, 0.0, 1.0);
	emit += pale_color * band * (line * pale_edge_energy + chamfer * 0.45 + 0.05);
	emit += pale_color * flash * (line * pale_edge_energy + 0.10);

	// BONE: selection / hover.
	emit += select_color * highlight * (line * 1.2 + fres * 0.18);

	EMISSION = emit;
}
