extends GutTest
## Static NaN guard for every shader in src/style/shaders (Loop 4). A single NaN/Inf pixel is spread
## by glow into white blotches or black holes (seen on llvmpipe; D3D12/Vulkan drivers may do worse),
## so the usual sources are banned at the source level. Pragmatic, not a parser: comments and
## preprocessor lines are stripped, calls are matched with balanced parentheses, and every rule has
## an explicit, justified exception list.
##
## Rules:
##   pow(b, e)        b is `max(..)`, `clamp(..)`, `abs(..)` or a positive literal; e a positive literal
##                    or `max(x, c)` with a positive literal floor c.
##                    (Signed Gaussians are written `d * d`, never `pow(d, 2.0)`.)
##   sqrt/log/log2/inversesqrt(x)   x is `max(..)`, `clamp(..)` or `abs(..)`.
##   asin/acos(x)     x is `clamp(..)`.
##   normalize(v)     banned (use k_safe_normalize or `v / max(length(v), eps)`), except engine bases.
##   atan(y, x)       only inside k_angle01 (atan(0, 0) is undefined).
##   smoothstep(a, b, x)   literal edges must satisfy a < b; identical edge text is always an error.
##   a / d            d is a positive literal, a `max(..)`/`clamp(..)` call, or an identifier declared
##                    in the same file as `name = max(..)`.

const SHADER_ROOT := "res://src/style/shaders/"

const GUARDS: Array[String] = ["max(", "clamp(", "abs("]

## normalize() arguments that are known non-null: [file name, exact argument].
const NORMALIZE_EXCEPTIONS := [
	# Camera basis vectors (columns of the inverse view matrix): unit length by construction.
	["particle_mote.gdshader", "INV_VIEW_MATRIX[0]"],
	["particle_mote.gdshader", "INV_VIEW_MATRIX[1]"],
	["particle_mote.gdshader", "INV_VIEW_MATRIX[2]"],
]

## Two-argument atan(): [file name, first argument]. k_angle01 feeds it a vector that is never null.
const ATAN_EXCEPTIONS := [
	["noise.gdshaderinc", "q.y"],
]

## Division denominators guarded by other means: [file name, denominator].
const DIVISION_EXCEPTIONS := [
	# k_safe_normalize: `(l > 1e-6) ? v / l : fallback`.
	["noise.gdshaderinc", "l"],
]

var _num := RegEx.create_from_string("^(\\d+\\.?\\d*|\\.\\d+)([eE][-+]?\\d+)?$")
var _num_prefix := RegEx.create_from_string("^(\\d+\\.?\\d*|\\.\\d+)([eE][-+]?\\d+)?(?![\\w.])")


# --- source helpers -----------------------------------------------------------------------------

func _shader_files(dir: String = SHADER_ROOT) -> Array[String]:
	var out: Array[String] = []
	for f: String in DirAccess.get_files_at(dir):
		if f.ends_with(".gdshader") or f.ends_with(".gdshaderinc"):
			out.append(dir + f)
	for d: String in DirAccess.get_directories_at(dir):
		out.append_array(_shader_files(dir + d + "/"))
	return out


## Code without comments and preprocessor lines (the #include path contains slashes).
func _code(src: String) -> String:
	var s := RegEx.create_from_string("/\\*[\\s\\S]*?\\*/").sub(src, "", true)
	var lines := PackedStringArray()
	for line: String in s.split("\n"):
		var cut := line.find("//")
		if cut >= 0:
			line = line.substr(0, cut)
		if line.strip_edges().begins_with("#"):
			line = ""
		lines.append(line)
	return "\n".join(lines)


## Index just past the parenthesis that closes the one at `open_idx` (-1 if unbalanced).
func _close(src: String, open_idx: int) -> int:
	var depth := 0
	for i in range(open_idx, src.length()):
		var c := src[i]
		if c == "(" or c == "[":
			depth += 1
		elif c == ")" or c == "]":
			depth -= 1
			if depth == 0:
				return i + 1
	return -1


## Top-level comma-separated arguments of the call whose "(" is at `open_idx`.
func _args(src: String, open_idx: int) -> PackedStringArray:
	var out := PackedStringArray()
	var depth := 0
	var start := open_idx + 1
	for i in range(open_idx, src.length()):
		var c := src[i]
		if c == "(" or c == "[":
			depth += 1
		elif c == ")" or c == "]":
			depth -= 1
			if depth == 0:
				out.append(src.substr(start, i - start).strip_edges())
				return out
		elif c == "," and depth == 1:
			out.append(src.substr(start, i - start).strip_edges())
			start = i + 1
	return out


## Every call of `fn`: [{args, line}].
func _calls(src: String, fn: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var re := RegEx.create_from_string("\\b%s\\s*\\(" % fn)
	for m: RegExMatch in re.search_all(src):
		var open_idx := m.get_end() - 1
		out.append({"args": _args(src, open_idx), "line": src.count("\n", 0, open_idx) + 1})
	return out


func _is_positive_literal(s: String) -> bool:
	return _num.search(s.strip_edges()) != null and float(s) > 0.0


## True for `max(x, c)` with a positive literal floor `c` (a pow exponent that is never <= 0).
func _is_floored(s: String) -> bool:
	s = s.strip_edges()
	if not (s.begins_with("max(") and _close(s, 3) == s.length()):
		return false
	var inner := _args(s, 3)
	return inner.size() == 2 and _is_positive_literal(inner[1])


## True when the whole expression is a single max()/clamp()/abs() call.
func _is_guarded(s: String) -> bool:
	s = s.strip_edges()
	for g: String in GUARDS:
		if s.begins_with(g) and _close(s, g.length() - 1) == s.length():
			return true
	return false


# --- the checker --------------------------------------------------------------------------------

## Violations in one shader source (file name used for exceptions and messages).
func check_source(file: String, src: String) -> PackedStringArray:
	var bad := PackedStringArray()
	var code := _code(src)

	for c: Dictionary in _calls(code, "pow"):
		var a: PackedStringArray = c["args"]
		if a.size() != 2 or not (_is_guarded(a[0]) or _is_positive_literal(a[0])):
			bad.append("%s:%d pow base not clamped: pow(%s)" % [file, c["line"], ", ".join(a)])
		elif not (_is_positive_literal(a[1]) or _is_floored(a[1])):
			bad.append("%s:%d pow exponent not a positive literal: pow(%s)" % [file, c["line"], ", ".join(a)])

	for fn: String in ["sqrt", "log", "log2", "inversesqrt"]:
		for c: Dictionary in _calls(code, fn):
			var a: PackedStringArray = c["args"]
			if a.size() != 1 or not _is_guarded(a[0]):
				bad.append("%s:%d %s of an unclamped value: %s(%s)" % [file, c["line"], fn, fn, ", ".join(a)])

	for fn: String in ["asin", "acos"]:
		for c: Dictionary in _calls(code, fn):
			var a: PackedStringArray = c["args"]
			if a.size() != 1 or not a[0].begins_with("clamp("):
				bad.append("%s:%d %s outside [-1, 1]: %s(%s)" % [file, c["line"], fn, fn, ", ".join(a)])

	for c: Dictionary in _calls(code, "normalize"):
		var a: PackedStringArray = c["args"]
		if not NORMALIZE_EXCEPTIONS.has([file, a[0] if a.size() > 0 else ""]):
			bad.append("%s:%d normalize of a possibly null vector: normalize(%s) (use k_safe_normalize)"
					% [file, c["line"], ", ".join(a)])

	for c: Dictionary in _calls(code, "atan"):
		var a: PackedStringArray = c["args"]
		if a.size() == 2 and not ATAN_EXCEPTIONS.has([file, a[0]]):
			bad.append("%s:%d atan(y, x) may see (0, 0): use k_angle01" % [file, c["line"]])

	for c: Dictionary in _calls(code, "smoothstep"):
		var a: PackedStringArray = c["args"]
		if a.size() != 3:
			continue
		if a[0] == a[1]:
			bad.append("%s:%d smoothstep with identical edges: smoothstep(%s)" % [file, c["line"], ", ".join(a)])
		elif _num.search(a[0].trim_prefix("-")) and _num.search(a[1].trim_prefix("-")) \
				and float(a[0]) >= float(a[1]):
			bad.append("%s:%d smoothstep edges not increasing: smoothstep(%s)" % [file, c["line"], ", ".join(a)])

	bad.append_array(_check_divisions(file, code))
	return bad


func _check_divisions(file: String, code: String) -> PackedStringArray:
	var bad := PackedStringArray()
	var i := code.find("/")
	while i >= 0:
		var j := i + 1
		if j < code.length() and code[j] == "=":
			bad.append("%s:%d '/=' is not checked: write the guarded division out" % [file, code.count("\n", 0, i) + 1])
		while j < code.length() and (code[j] == " " or code[j] == "\t"):
			j += 1
		var rest := code.substr(j)
		var den := ""
		var ok := false
		if rest.begins_with("("):
			den = rest.substr(0, _close(rest, 0))
		else:
			var m := _num_prefix.search(rest)
			if m == null:
				m = RegEx.create_from_string("^[\\w.]+(\\s*\\()?").search(rest)
			den = m.get_string() if m else rest.substr(0, 12)
			if den.ends_with("("):
				var call := rest.substr(0, _close(rest, den.length() - 1))
				ok = _is_guarded(call)
				den = call
			elif _is_positive_literal(den):
				ok = true
			else:
				var root := den.get_slice(".", 0)
				var decl := RegEx.create_from_string("\\b%s\\s*=\\s*max\\(" % root)
				ok = decl.search(code) != null or DIVISION_EXCEPTIONS.has([file, den])
		if not ok:
			bad.append("%s:%d division by a possibly zero value: / %s" % [file, code.count("\n", 0, i) + 1, den])
		i = code.find("/", i + 1)
	return bad


# --- tests --------------------------------------------------------------------------------------

func test_all_shaders_are_nan_safe() -> void:
	var files := _shader_files()
	assert_gt(files.size(), 15, "shader files found")
	var bad := PackedStringArray()
	for path: String in files:
		bad.append_array(check_source(path.get_file(), FileAccess.get_file_as_string(path)))
	assert_eq(bad.size(), 0, "NaN hazards:\n" + "\n".join(bad))


func test_checker_flags_known_hazards() -> void:
	# The exact patterns found in Loop 4 (and friends) must be caught, or the guard above is blind.
	var hazards := {
		"gown lip": "float lip = exp(-pow((n - thr) / 0.05, 2.0));",
		"fresnel": "float v = pow(1.0 - nv, 1.6);",
		"ridge": "float r = pow(k_ridge(q), 7.0);",
		"exponent": "float r = pow(max(x, 0.0), k);",
		"exponent floored at zero": "float r = pow(max(x, 0.0), max(k, 0.0));",
		"sqrt": "float d = sqrt(f1);",
		"acos": "float a = acos(dot(a, b));",
		"normalize": "vec3 d = normalize(VERTEX);",
		"atan": "float a = atan(p.y, p.x);",
		"equal edges": "float s = smoothstep(w, w, x);",
		"reversed edges": "float s = smoothstep(0.5, 0.15, x);",
		"bare uniform divisor": "float k = behind / trail;",
		"expression divisor": "float e = a / (r * r);",
	}
	for name: String in hazards:
		var src: String = "void fragment() {\n\t%s\n}\n" % hazards[name]
		assert_gt(check_source("probe.gdshader", src).size(), 0, "not flagged: %s" % name)


func test_checker_accepts_guarded_forms() -> void:
	var safe := [
		"float lip_d = (n - thr) / 0.05;\n\tfloat lip = exp(-lip_d * lip_d);",
		"float v = pow(max(1.0 - nv, 0.0), 1.6);",
		"float v = pow(clamp(x, 0.0, 1.0), 3.0);",
		"float d = sqrt(max(f1, 0.0));",
		"float s = pow(max(ndh, 0.0), max(shin, 1.0));",
		"float a = acos(clamp(c, -1.0, 1.0));",
		"float s = 1.0 - smoothstep(0.15, 0.5, x);",
		"float k = behind / max(trail, 1e-3);",
		"vec2 px = max(fwidth(UV), vec2(1e-5));\n\tfloat f = 1.0 / px.x;",
		"// a comment with pow(x, 2.0) / y and normalize(v)\n\tfloat z = 1.0;",
	]
	for s: String in safe:
		var src: String = "void fragment() {\n\t%s\n}\n" % s
		var bad := check_source("probe.gdshader", src)
		assert_eq(bad.size(), 0, "false positive on %s: %s" % [s, "\n".join(bad)])
