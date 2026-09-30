class_name UiGlyphs
extends RefCounted
## Small line glyphs of the GENESIS UI, drawn with CanvasItem primitives (no icon font, no textures):
## the astronomy of the vault. Each body kind has a sign (planet = subagent, moon = documentation,
## ring = skills, belt = memory, thread = link, star = the central agent, cupped arc = a hand) and the
## transport/card actions have theirs (play, pause, reset, settings, focus, close). Thin (1 px),
## anti-aliased, one ink colour from Palette. `r` is the glyph radius in px (≈ 5 for the UI).

## Sign of each GenesisCatalog kind name (see kind_glyph()).
const KIND_GLYPHS := {
	"CENTRAL AGENT": &"agent",
	"AUXILIARY HAND": &"hand",
	"SUBAGENT": &"planet",
	"DOCUMENTATION": &"moon",
	"SKILLS": &"ring",
	"MEMORY": &"belt",
	"RELATIONS": &"thread",
}

## Every glyph draw() knows.
const ALL: Array[StringName] = [
	&"agent", &"hand", &"planet", &"moon", &"ring", &"belt", &"thread", &"seal",
	&"play", &"pause", &"reset", &"settings", &"focus", &"close",
]


## Glyph of a GenesisCatalog kind name (&"" when it has none).
static func kind_glyph(kind_name: String) -> StringName:
	return KIND_GLYPHS.get(kind_name, &"")


## Draws glyph `kind` centred at `c` with radius `r` on `ci`. Unknown kinds draw nothing.
static func draw(ci: CanvasItem, kind: StringName, c: Vector2, r: float, color: Color, width := 1.0) -> void:
	match kind:
		&"agent":
			# A four-point star: the central agent, the weaver.
			var pts := PackedVector2Array()
			for i in 8:
				var a := TAU * float(i) / 8.0 - PI * 0.5
				var rr := r if i % 2 == 0 else r * 0.3
				pts.append(c + Vector2(cos(a), sin(a)) * rr)
			ci.draw_colored_polygon(pts, color)
		&"hand":
			# A cupped arc with a small world above it.
			ci.draw_arc(c + Vector2(0, -r * 0.2), r, PI * 0.12, PI * 0.88, 16, color, width, true)
			ci.draw_circle(c + Vector2(0, -r * 0.35), r * 0.28, color, true, -1.0, true)
		&"planet":
			ci.draw_circle(c, r * 0.62, color, true, -1.0, true)
		&"moon":
			# A crescent (lit limb on the right).
			var pts := PackedVector2Array()
			var rr := r * 0.9
			for i in 13:
				var a := -PI * 0.5 + PI * float(i) / 12.0
				pts.append(c + Vector2(cos(a), sin(a)) * rr)
			for i in range(11, 0, -1):
				var a := -PI * 0.5 + PI * float(i) / 12.0
				pts.append(c + Vector2(cos(a) * rr * 0.2, sin(a) * rr))
			ci.draw_colored_polygon(pts, color)
		&"ring":
			ci.draw_circle(c, r * 0.3, color, true, -1.0, true)
			_ellipse(ci, c, Vector2(r, r * 0.42), -0.35, color, width)
		&"belt":
			for i in 5:
				var a := PI * (1.12 + 0.19 * float(i))
				ci.draw_circle(c + Vector2(cos(a), sin(a) * 0.55 + 0.4) * r, r * 0.13 + 0.35, color, true, -1.0, true)
		&"thread":
			var pts := PackedVector2Array()
			for i in 13:
				var u := float(i) / 12.0
				pts.append(c + Vector2((u - 0.5) * 2.0 * r, -sin(u * PI) * r * 0.55 + r * 0.25))
			ci.draw_polyline(pts, color, width, true)
			ci.draw_circle(pts[0], r * 0.18, color, true, -1.0, true)
			ci.draw_circle(pts[pts.size() - 1], r * 0.18, color, true, -1.0, true)
		&"seal":
			ci.draw_arc(c, r, 0.0, TAU, 24, color, width, true)
			ci.draw_circle(c, r * 0.3, color, true, -1.0, true)
		&"play":
			var p := PackedVector2Array([c + Vector2(-r * 0.55, -r * 0.8), c + Vector2(r * 0.8, 0.0),
				c + Vector2(-r * 0.55, r * 0.8), c + Vector2(-r * 0.55, -r * 0.8)])
			ci.draw_polyline(p, color, width, true)
		&"pause":
			ci.draw_line(c + Vector2(-r * 0.35, -r * 0.75), c + Vector2(-r * 0.35, r * 0.75), color, width, true)
			ci.draw_line(c + Vector2(r * 0.35, -r * 0.75), c + Vector2(r * 0.35, r * 0.75), color, width, true)
		&"reset":
			# An open orbit returning to its start, with a small head.
			ci.draw_arc(c, r * 0.8, -PI * 0.35, PI * 1.45, 24, color, width, true)
			var tip := c + Vector2(cos(-PI * 0.35), sin(-PI * 0.35)) * r * 0.8
			ci.draw_line(tip, tip + Vector2(-r * 0.5, -r * 0.08), color, width, true)
			ci.draw_line(tip, tip + Vector2(r * 0.05, r * 0.5), color, width, true)
		&"settings":
			# Three hairlines with a small ring each: tuning.
			var knobs := PackedFloat32Array([0.35, -0.4, 0.1])
			for i in 3:
				var y := c.y + (float(i) - 1.0) * r * 0.62
				var k := c.x + r * knobs[i]
				ci.draw_line(Vector2(c.x - r, y), Vector2(k - r * 0.2, y), color, width, true)
				ci.draw_line(Vector2(k + r * 0.2, y), Vector2(c.x + r, y), color, width, true)
				ci.draw_arc(Vector2(k, y), r * 0.2, 0.0, TAU, 10, color, width, true)
		&"focus":
			var k := r * 0.45
			for s: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
				var corner := c + s * r * 0.85
				ci.draw_line(corner, corner - Vector2(s.x * k, 0.0), color, width, true)
				ci.draw_line(corner, corner - Vector2(0.0, s.y * k), color, width, true)
		&"close":
			ci.draw_line(c + Vector2(-r, -r) * 0.6, c + Vector2(r, r) * 0.6, color, width, true)
			ci.draw_line(c + Vector2(r, -r) * 0.6, c + Vector2(-r, r) * 0.6, color, width, true)


static func _ellipse(ci: CanvasItem, c: Vector2, radii: Vector2, tilt: float, color: Color, width: float) -> void:
	var pts := PackedVector2Array()
	var rot := Transform2D(tilt, Vector2.ZERO)
	for i in 33:
		var a := TAU * float(i) / 32.0
		pts.append(c + rot * Vector2(cos(a) * radii.x, sin(a) * radii.y))
	ci.draw_polyline(pts, color, width, true)
