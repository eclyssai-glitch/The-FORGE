// KORIUM UNIVERSE — configuration artifact (living prototype, Loop 5). Owner: art-director.
// A floating sheet of light holding MIKU's configuration: three sections (identity, appearance,
// behaviour), each a header line and a few `key · value` lines written in a faint asemic script
// (arcs and stems of light, never letters, never an app icon). It is held by one hand while another
// edits it.
//   presence  0..1  the sheet unrolls from its top edge (bright lip), then its lines are written
//                   in; reversed, it rolls back up and is gone.
//   edit      0..1  progress of the edit on line `edit_row`: a caret of light crosses the line;
//                   behind it the glyphs are the new value, ahead of it the old one, and around it
//                   they rearrange (cross-fading shapes, never blinking). The line lifts and the
//                   rest of the sheet steps back while editing.
//   validated 0..1  ease it 0 -> 1 over Palette.T_CONFIRM: a short band of light sweeps the sheet
//                   (the pulse lives inside the ramp) and the edited line is sealed with a small
//                   pale-gold ring (a change was made). At 1 the sheet is calm.
// Mesh: QuadMesh / PlaneMesh, UV (0, 0) top-left; `aspect` = width / height of the quad so glyphs
// stay round. Additive, unshaded, double-sided, no depth write, no TIME.
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

#include "res://src/style/shaders/genesis/noise.gdshaderinc"

uniform vec3 sheet_color : source_color;
uniform vec3 ink_color : source_color;
uniform vec3 edit_color : source_color;
uniform vec3 pulse_color : source_color;
uniform vec3 seal_color : source_color;

uniform float presence : hint_range(0.0, 1.0) = 1.0;
uniform float edit : hint_range(0.0, 1.0) = 0.0;
uniform float validated : hint_range(0.0, 1.0) = 0.0;
// Index of the line being edited (0 = first line; headers are lines 0, 4 and 8).
uniform float edit_row = 5.0;
uniform float motion_time = 0.0;
uniform float seed = 0.0;
uniform float intensity = 0.7;
// Width / height of the quad.
uniform float aspect = 0.72;
uniform float rows = 11.0;
// Sheet fill (share of intensity), edge line width (px), glyph stroke width (px).
uniform float fill = 0.04;
uniform float edge_px = 0.9;
// Feathered border of the sheet (share of the height).
uniform float feather = 0.05;
uniform float stroke_px = 1.0;
uniform float ink = 0.42;

// Asemic glyph in a cell (local coords -0.5..0.5): an arc of light, sometimes a stem or a dot.
// `h` (0..1) picks the shape; `px` is one pixel in cell units. Returns coverage 0..1.
float glyph(vec2 c, float h, float px, float w_px) {
	vec2 q = c * vec2(1.0, 0.85);
	float r = 0.17 + 0.06 * fract(h * 7.3);
	float a0 = fract(h * 3.7);
	float span = 0.35 + 0.45 * fract(h * 11.1);
	float ang = fract(k_angle01(q) - a0);
	float on_arc = 1.0 - smoothstep(span, span + 0.04, ang);
	float half_w = max(w_px * 0.5, 0.4) * px;
	float d_arc = abs(length(q) - r);
	float g = (1.0 - smoothstep(half_w, half_w + px, d_arc)) * on_arc;
	// Stem: a vertical stroke on one side of the arc (about half of the glyphs).
	float stem_x = (fract(h * 5.9) - 0.5) * 0.36;
	float has_stem = step(0.5, fract(h * 13.7));
	float d_stem = abs(c.x - stem_x);
	float stem = (1.0 - smoothstep(half_w, half_w + px, d_stem)) * (1.0 - smoothstep(0.22, 0.27, abs(c.y + 0.04)));
	g = max(g, stem * has_stem);
	// Dot: a few glyphs end in a point.
	float has_dot = step(0.78, fract(h * 17.3));
	float d_dot = length(c - vec2(-stem_x, 0.24));
	g = max(g, (1.0 - smoothstep(half_w * 1.6, half_w * 1.6 + px, d_dot)) * has_dot);
	return g;
}

void fragment() {
	vec2 uv = UV;
	float asp = max(aspect, 0.05);
	vec2 q = (uv - 0.5) * vec2(asp, 1.0);
	vec2 px2 = max(fwidth(q), vec2(1e-5));
	float px = max(px2.x, px2.y);

	// --- Presence: the sheet unrolls downward, then its lines are written in. ---
	float pr = clamp(presence, 0.0, 1.0);
	float roll = pr * 1.25 - 0.1;
	float edge_n = (k_vnoise(vec3(uv.x * 9.0, seed, 3.0)) - 0.5) * 0.04;
	float shown = 1.0 - smoothstep(roll - 0.03, roll, uv.y + edge_n);
	float rd = (uv.y + edge_n - roll) / 0.012;
	float roll_lip = (pr > 0.001 && pr < 0.999) ? exp(-rd * rd) : 0.0;
	float written = clamp(pr * 1.6 - 0.6, 0.0, 1.0);

	// --- Sheet: a leaf of light with feathered edges (no frame, no device corners), brighter
	// toward the top, a faint margin rule left of the text and a hairline along the top edge. ---
	vec2 half_size = vec2(asp * 0.5, 0.5) - 0.02;
	float radius = 0.02;
	vec2 bq = abs(q) - half_size + radius;
	float sdf = length(max(bq, vec2(0.0))) + min(max(bq.x, bq.y), 0.0) - radius;
	float inside = 1.0 - smoothstep(-feather, px, sdf);
	float top_d = abs(q.y + half_size.y - 0.01);
	float top_line = (1.0 - smoothstep(edge_px * 0.5 * px, (edge_px * 0.5 + 1.0) * px, top_d))
			* (1.0 - smoothstep(half_size.x * 0.55, half_size.x * 0.95, abs(q.x)));
	float edge = top_line;
	float rule_x = -asp * 0.5 + 0.045;
	float rule = (1.0 - smoothstep(edge_px * 0.5 * px, (edge_px * 0.5 + 1.0) * px, abs(q.x - rule_x)))
			* (1.0 - smoothstep(0.3, 0.42, abs(q.y + 0.01)));
	float sheet = inside * fill * (0.75 + 0.5 * (1.0 - uv.y)) + top_line * 0.3 + rule * 0.12;

	// --- Lines of asemic script. ---
	float top = 0.12;
	float bottom = 0.9;
	float rn = max(rows, 1.0);
	float row_h = (bottom - top) / rn;
	float ry = (uv.y - top) / max(row_h, 1e-4);
	float row = floor(ry);
	float in_rows = step(0.0, ry) * step(ry, rn);
	vec2 cell_size = vec2(row_h * 0.62, row_h);
	float x0 = -asp * 0.5 + 0.07;
	float is_header = step(abs(mod(row, 4.0)), 0.5);
	float indent = (1.0 - is_header) * 1.0;
	float gx = (q.x - x0) / max(cell_size.x, 1e-4) - indent;
	float col = floor(gx);
	vec2 cc = vec2(fract(gx) - 0.5, fract(ry) - 0.5);
	float cpx = px / max(row_h, 1e-4);

	// Layout of a line: header = short bracketed word; entry = key (3..6), a separator dot, value.
	float hr = k_hash12(vec2(row, seed * 31.0 + 1.0));
	float key_len = is_header > 0.5 ? 4.0 + floor(hr * 3.0) : 2.0 + floor(hr * 4.0);
	float old_len = 2.0 + floor(k_hash12(vec2(row, seed * 31.0 + 7.0)) * 5.0);
	float new_len = 2.0 + floor(k_hash12(vec2(row, seed * 31.0 + 13.0)) * 5.0);
	float is_edit_row = 1.0 - step(0.5, abs(row - edit_row));
	float e_amt = clamp(edit, 0.0, 1.0);
	float editing = smoothstep(0.0, 0.04, e_amt) * (1.0 - smoothstep(0.0, 0.35, clamp(validated, 0.0, 1.0)));
	// The value's length grows / shrinks as the caret passes.
	float val_len = mix(old_len, new_len, is_edit_row * e_amt);
	float line_len = (is_header > 0.5) ? key_len : key_len + 1.0 + val_len;
	float in_line = step(0.0, gx) * step(gx, line_len) * in_rows;

	// Glyph hash: old / new value on the edited line; around the caret the shapes rearrange.
	float caret_col = (key_len + 1.0) + e_amt * max(new_len, old_len);
	float h_old = k_hash12(vec2(col * 1.37 + row * 17.0, seed * 7.0 + 3.0));
	float h_new = k_hash12(vec2(col * 1.37 + row * 17.0, seed * 7.0 + 41.0));
	float behind_caret = 1.0 - smoothstep(caret_col - 0.6, caret_col + 0.2, col + 0.5);
	float in_value = step(key_len + 0.5, col);
	float use_new = is_edit_row * in_value * mix(0.0, behind_caret, step(0.001, e_amt));
	float near_caret = is_edit_row * in_value * editing * (1.0 - smoothstep(0.0, 1.8, abs(col + 0.5 - caret_col)));
	float churn_t = motion_time * 2.2 + col * 0.37;
	float churn_k = floor(churn_t);
	float churn_f = smoothstep(0.25, 0.75, fract(churn_t));
	float h_c0 = k_hash12(vec2(col + churn_k * 3.1, row + seed));
	float h_c1 = k_hash12(vec2(col + (churn_k + 1.0) * 3.1, row + seed));

	float g_old = glyph(cc, h_old, cpx, stroke_px);
	float g_new = glyph(cc, h_new, cpx, stroke_px);
	float g_settled = mix(g_old, g_new, use_new);
	float g_churn = mix(glyph(cc, h_c0, cpx, stroke_px), glyph(cc, h_c1, cpx, stroke_px), churn_f);
	float g = mix(g_settled, g_churn, near_caret * 0.85);
	// Separator dot between key and value.
	float sep = (1.0 - is_header) * (1.0 - step(0.5, abs(col - key_len))) *
			(1.0 - smoothstep(0.05, 0.05 + cpx, length(cc - vec2(0.0, 0.08))));
	// Header: short brackets of light on both sides of its word.
	float bracket_l = is_header * (1.0 - step(0.5, abs(col + 1.0))) * (1.0 - smoothstep(cpx * 0.6, cpx * 1.6, abs(cc.x - 0.3)))
			* (1.0 - smoothstep(0.32, 0.38, abs(cc.y)));
	float glyphs = max(max(g * in_line, sep * in_rows), bracket_l * in_rows);
	// A few glyphs are fainter (ink pressure), headers are brighter.
	float pressure = 0.6 + 0.4 * k_hash12(vec2(col, row * 3.0 + 5.0));
	float row_ink = ink * pressure * mix(1.0, 1.35, is_header);
	// Lines are written in one after the other as the sheet appears.
	float row_written = smoothstep(row / rn - 0.05, row / rn + 0.05, written * 1.1 - 0.05);
	// While editing the edited line lifts and the rest steps back.
	float focus = mix(1.0, mix(0.4, 2.0, is_edit_row), editing);
	float settled_focus = mix(1.0, 1.3, is_edit_row * step(0.001, e_amt) * (1.0 - editing));
	vec3 glyph_col = mix(ink_color, edit_color, is_edit_row * clamp(editing + near_caret, 0.0, 1.0));
	vec3 e = sheet_color * sheet + glyph_col * glyphs * row_ink * row_written * focus * settled_focus;

	// Edited line: a faint band of light behind it and the caret.
	float band_d = (ry - (edit_row + 0.5)) / 0.7;
	float band = exp(-band_d * band_d) * in_rows * inside * 0.2 * editing;
	float caret_x = x0 + (caret_col + indent) * cell_size.x;
	float caret_d = abs(q.x - caret_x);
	float caret = is_edit_row * (1.0 - smoothstep(px * 0.7, px * 2.0, caret_d)) * (1.0 - smoothstep(0.36, 0.48, abs(cc.y))) * editing;
	e += edit_color * (band + caret * 1.6);

	// --- Validation: a short band sweeps the sheet, then the edited line is sealed. ---
	float v = clamp(validated, 0.0, 1.0);
	float sweep_t = clamp(v / 0.7, 0.0, 1.0);
	float sweep_y = mix(-0.1, 1.1, sweep_t);
	float sd = (uv.y - sweep_y) / 0.05;
	float sweep_env = sin(3.14159 * sweep_t);
	e += pulse_color * exp(-sd * sd) * sweep_env * inside * 0.55;
	e += pulse_color * edge * sweep_env * 0.6;
	float seal_on = smoothstep(0.45, 1.0, v);
	float seal_x = x0 + (key_len + 1.0 + new_len + 1.6 + indent) * cell_size.x;
	vec2 seal_c = vec2(seal_x, top + (edit_row + 0.5) * row_h - 0.5);
	float seal_r = row_h * 0.28;
	float seal_d = abs(length(q - seal_c) - seal_r);
	float seal = (1.0 - smoothstep(px * 0.6, px * 1.8, seal_d)) + (1.0 - smoothstep(px * 0.8, px * 2.0, length(q - seal_c)));
	e += seal_color * seal * seal_on * 0.9;

	e *= intensity * shown;
	e += sheet_color * roll_lip * inside * 0.45 * intensity;
	ALBEDO = e;
	ALPHA = 1.0;
}
