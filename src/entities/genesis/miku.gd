class_name Miku
extends Node3D
## MIKU, the celestial weaver (docs/VISUAL_DIRECTION.md §1). Owner: animator.
## The porcelain sculpture (assets/meshes/miku_body.obj, MaterialLibrary.miku_body()), a gown of
## light over the skirt that trails below the hem and dissolves into star dust
## (MaterialLibrary.miku_gown(); the dust river itself is the Stardust module; the porcelain skirt
## itself dissolves into grains, miku_body dissolve_top/bottom), hair as ONE nebula mass of light
## ribbons (HairRibbons.nebula + miku_hair()) leaving the sculpted knot back and up in an S, whose
## link strands become MIKU's relation threads, the gold seed on her brow, and the astrolabe halo
## (halo_arc()) turning behind her head.
##
## Narrative (GenesisChoreography, from Simulation.genesis + Simulation.time): in the dark only
## the seed glows; at miku.awaken it blooms and its light reveals her (miku_body `reveal`, radial
## from the brow), the hair is spun out (`reveal` front), the gown's veil comes once the reveal
## reaches the skirt, the halo swells in. The seed surges gently on each act of creation; at
## planet.stable she raises her head, the halo closes and the climax pulse leaves her hair along
## the link strands (`link_pulse`) before it runs along her threads.
## Ambient (MotionClock): breathing (Palette.T_BREATH) on the porcelain, halo and a slow float of
## the whole figure; the two hair layers sway with different periods (the link strands hold
## still: their threads continue them); the halo turns once per Palette.T_HALO_TURN.
## Anchors (hair root, brow, head, chest, hem) are read from assets/meshes/miku_body.json.
## Entity `miku`: the Figure node is the visual root (group entity_miku, focus bounds = mesh
## bounds), picked through a capsule StaticBody3D (layer 2); audio anchor = the heart.

const MESH_NAME := "miku_body"
const MESH_PATH := "res://assets/meshes/miku_body.obj"
const ENTITY := &"miku"

## Float of the whole figure (units, period s) and the breathing period.
const FLOAT_AMPLITUDE := 0.06
const FLOAT_PERIOD := Palette.T_BREATH_SLOW
const BREATH_PERIOD := Palette.T_BREATH

## Hair: ONE nebula mass (HairRibbons.nebula) born at the single root on the sculpted knot
## (anchor hair_root): tufts of 5–10 strands rising back and up in an S, varied lengths, tips
## opening into filaments. Layers: [name, tufts, seed, length, width, intensity share, sway (rad),
## sway period (s), nebula options]. Additive ribbons all start at one point, so the intensity is
## low: the root concentrates the light of every strand.
const HAIR_LAYERS: Array = [
	["HairMass", 10, 7101, 12.0, 0.11, 0.22, 0.014, 10.0,
		{"spread": 0.55, "lift": 0.5, "s_amount": 0.55, "tip_open": 0.18, "root_radius": 0.1}],
	["HairVeil", 8, 7202, 15.0, 0.06, 0.22, 0.024, 13.5,
		{"spread": 0.75, "lift": 0.6, "s_amount": 0.6, "strands_min": 4, "strands_max": 7, "tip_open": 0.26,
		"wave": 0.07, "root_radius": 0.12}],
]
## Direction the hair leaves the knot (object space; blended with the sculpt's hair_root_tangent,
## HAIR_TANGENT_SHARE of it): back more than up — the S lifts it as it goes (nebula `lift`) —
## drifting a little to her right (screen left), away from the right hand.
const HAIR_DIRECTION := Vector3(-0.72, 0.05, -0.7)
const HAIR_TANGENT_SHARE := 0.25
## Link strands: one strand of the mass per relation thread of MIKU, ending exactly where its
## thread starts: the hair visibly becomes the graph. Each source (hair_sources) lies ON a strand of
## the mass — the longest strand of the tuft that leans most towards the thread's body, at
## HAIR_LINK_SHARES of its length — so the link strand follows the tuft's own S (HairRibbons.nebula
## link_ends: no hook) and the thread leaves along it. Static (no sway, so the junction holds), a
## little wider and brighter than the mass; brighter still once their thread is spun.
const HAIR_LINK_TUFTS := 10
const HAIR_ROOT_FALLBACK := Vector3(-0.08, 1.73, -0.11)
## Share of the chosen strand where each MIKU thread leaves the hair (RelationThreads.MIKU_LINKS order).
const HAIR_LINK_SHARES: Array[float] = [0.6, 0.72, 0.66, 0.78]
## The hair is spun out from the knot at the awakening: the shader's growth front (`reveal`, a
## bright front running root -> tip) while the plume also swells from HAIR_GROW_SCALE of its size.
const HAIR_GROW_SCALE := 0.7
const HAIR_LINK_WIDTH := 0.09
const HAIR_LINK_INTENSITY := Vector2(0.24, 0.42)
## Gown shell: the skirt of the sculpture below GOWN_TOP (object Y), pushed out along its normals,
## stretched below GOWN_STRETCH_FROM by GOWN_STRETCH and flared by GOWN_FLARE, so the veil trails
## past the porcelain and dissolves downward into star dust (miku_gown fade_top -> fade_bottom:
## a broad noise front breaking into grains with a luminous lip, never a hard hem). The porcelain
## skirt itself turns into light and grains below BODY_DISSOLVE.x (miku_body dissolve_top/bottom):
## the veil carries on past it and the Stardust river takes the grains down to the world.
const GOWN_VEIL := true
const GOWN_TOP := -0.2
const GOWN_OFFSET := 0.012
## Skirt envelope of the sculpture (object units): radius at the hips, flare below.
const SKIRT_RADIUS := 0.56
const SKIRT_FLARE := 0.45
const SKIRT_FLARE_FROM := -1.6
## The veil is a subtle light over the porcelain skirt (share of the material's presence): the
## porcelain already glows; the sum must stay below the glow threshold except at the grazing edges.
const GOWN_LEVEL := 0.4
const GOWN_STRETCH_FROM := -2.4
const GOWN_STRETCH := 0.75
const GOWN_FLARE := 0.3
const GOWN_FADE := Vector2(-0.35, -5.4)
## Porcelain dissolve (miku_body dissolve_top, dissolve_bottom; object Y): solid above x, gone at y.
const BODY_DISSOLVE := Vector2(-1.7, -4.35)
## Halo: quad edge (units), distance behind the head centre, tilt.
const HALO_SIZE := 2.3
const HALO_BACK := 0.42
const HALO_TILT := Vector3(-0.12, 0.0, 0.18)
## Seed on the brow: mote sizes (core, glow), light reach and energy at full seed.
const SEED_CORE_SIZE := 0.05
const SEED_GLOW_SIZE := 0.17
const SEED_CORE_HDR := 1.5
const SEED_LIGHT_RANGE := 0.9
const SEED_LIGHT_ENERGY := 0.04
## The light that reveals her: at the awakening the seed's light blooms this far (units) and this
## bright (GenesisChoreography.seed_bloom), then settles back to the small brow light.
const SEED_BLOOM_RANGE := 3.4
const SEED_BLOOM_ENERGY := 0.45
## Asleep, the ember on her brow breathes (share of its brightness, period in seconds).
const EMBER_BREATH := 0.22
const EMBER_PERIOD := Palette.T_BREATH
## At planet.stable she raises her head: the figure tilts back around the waist (rad) and rises a
## little (units).
const HEAD_LIFT_ANGLE := 0.075
const HEAD_LIFT_RISE := 0.12
## The halo's arcs close at planet.stable (arc spans of halo_arc: from the material's own to these).
const HALO_CLOSED_SPAN := 1.0
const HALO_CLOSED_INNER := 0.8
## Inner light of the porcelain at rest (miku_body inner_glow) and added while the seed reveals her
## (GenesisChoreography.reveal_glow). While she is revealed the porcelain's `awaken` follows her
## presence (the revealed porcelain is already the lit, awake one — never a dark figure).
const INNER_GLOW := 0.05
const REVEAL_INNER := 0.5
const REVEAL_WAKE := 4.0
## Selection smoothing (1/s) and levels.
const SELECT_RATE := 6.0

static var _gown_mesh_cache: ArrayMesh
static var _link_curves: Array[PackedVector3Array] = []
static var _sources: Dictionary = {}

var figure: Node3D
var body: MeshInstance3D
var gown: MeshInstance3D
var hair_pivot: Node3D
var hair_layers: Array[MeshInstance3D] = []
var hair_links: MeshInstance3D
var halo_pivot: Node3D
var halo: MeshInstance3D
var seed_motes: MoteCloud
var seed_light: OmniLight3D
var heart: Node3D
var pick_body: StaticBody3D

var _body_mat: ShaderMaterial
## miku_body has the radial awakening `reveal` (art-director r1b).
var _body_reveal := false
var _gown_mat: ShaderMaterial
var _halo_mat: ShaderMaterial
var _hair_mats: Array[ShaderMaterial] = []
var _link_mat: ShaderMaterial
var _select := 0.0
var _figure_base := Transform3D.IDENTITY
## Last narrative values written (awaken, hair reveal, hair intensity, gown, halo, seed, presence,
## seed bloom, head lift, halo close, link strands, reveal glow, hair pulse).
var _written := PackedFloat32Array([-1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -2])
## Seed brightness (narrative) and whether she is still asleep (the ember breathes, ambient).
var _seed := 0.0
var _bloom := 0.0
var _asleep := 1.0
var _lift := 0.0
## Halo arc spans of the material (restored as the open state).
var _halo_span := Vector2(0.68, 0.4)


func _ready() -> void:
	figure = Node3D.new()
	figure.name = "Figure"
	_figure_base = GenesisLayout.miku_transform()
	figure.transform = _figure_base
	figure.add_to_group(SessionState.entity_group(ENTITY))
	var bounds := GenesisLayout.bounds(MESH_NAME, AABB(Vector3(-1.4, -4.3, -1.6), Vector3(2.8, 6.1, 2.8)))
	figure.set_meta(CameraDirector.FOCUS_BOUNDS_META, bounds)
	figure.set_meta(&"label_anchor", _anchor("head_top", Vector3(0, 1.77, 0.28)) + Vector3(0.0, 0.2, 0.0))
	figure.set_meta(&"label_radius", 0.9)
	add_child(figure)

	body = MeshInstance3D.new()
	body.name = "Body"
	body.mesh = load(MESH_PATH) as Mesh
	_body_mat = MaterialLibrary.miku_body().duplicate() as ShaderMaterial
	_body_mat.set_shader_parameter("dissolve_top", BODY_DISSOLVE.x)
	_body_mat.set_shader_parameter("dissolve_bottom", BODY_DISSOLVE.y)
	_body_reveal = _declares(_body_mat, &"reveal")
	if _body_reveal:
		_body_mat.set_shader_parameter("reveal_origin", _anchor("forehead", Vector3(0.0, 1.52, 0.42)))
	body.material_override = _body_mat
	# No self-shadow: the key's shadow map stair-stepped across the torso and gown (critic r1).
	# Her baked AO + SSAO shape the porcelain; the key still lights her.
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	figure.add_child(body)

	gown = MeshInstance3D.new()
	gown.name = "Gown"
	gown.mesh = gown_mesh(body.mesh)
	_gown_mat = MaterialLibrary.miku_gown().duplicate() as ShaderMaterial
	_gown_mat.set_shader_parameter("fade_top", GOWN_FADE.x)
	_gown_mat.set_shader_parameter("fade_bottom", GOWN_FADE.y)
	gown.material_override = _gown_mat
	gown.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gown.visible = GOWN_VEIL
	figure.add_child(gown)

	_build_hair()
	_build_halo()
	_build_seed()
	for k in 2:
		var v: Variant = _halo_mat.get_shader_parameter(["arc_span", "inner_span"][k])
		if v is float:
			_halo_span[k] = v

	heart = Node3D.new()
	heart.name = "Heart"
	heart.position = _anchor("chest", Vector3(0, 0.6, 0.2))
	heart.set_meta(&"audio_anchor", &"miku")
	figure.add_child(heart)

	pick_body = _pick_body(bounds)
	figure.add_child(pick_body)

	Simulation.world_rebuilt.connect(_update_narrative)
	_update_narrative()
	_update_ambient(0.0)


func _process(delta: float) -> void:
	_update_narrative()
	_update_ambient(delta)


## Object-space anchor of the sculpture (JSON), `fallback` when absent.
func _anchor(key: String, fallback: Vector3) -> Vector3:
	return GenesisLayout.anchor(MESH_NAME, key, fallback)


func _update_narrative() -> void:
	var g := Simulation.genesis
	var t := Simulation.time
	var a := GenesisChoreography.awaken(g, t)
	var reveal := GenesisChoreography.hair_reveal(g, t)
	var hi := GenesisChoreography.hair_intensity(g, t)
	var gp := GenesisChoreography.gown_presence(g, t)
	var ha := GenesisChoreography.halo(g, t)
	var sd := GenesisChoreography.seed_light(g, t)
	var pr := GenesisChoreography.body_presence(g, t)
	var bloom := GenesisChoreography.seed_bloom(g, t)
	_lift = GenesisChoreography.head_lift(g, t)
	var hc := GenesisChoreography.halo_close(g, t)
	_asleep = 1.0 - GenesisChoreography.awaken(g, t)
	if not is_equal_approx(pr, _written[6]):
		_written[6] = pr
		# Out of the dark: hidden before the awakening (only the seed glows), then revealed by the
		# seed's light — miku_body's radial `reveal` from the brow (opaque, a soft gold front; the
		# global transparency showed the skirt's inner wall). Fallback when the material has no
		# `reveal`: a whole-body fade (transparency only while fading).
		body.visible = pr > 0.001
		if _body_reveal:
			_body_mat.set_shader_parameter("reveal", pr)
			body.transparency = 0.0
		else:
			body.transparency = 1.0 - pr if pr < 0.999 else 0.0
	if not is_equal_approx(hc, _written[9]):
		_written[9] = hc
		_halo_mat.set_shader_parameter("arc_span", lerpf(_halo_span.x, HALO_CLOSED_SPAN, hc))
		_halo_mat.set_shader_parameter("inner_span", lerpf(_halo_span.y, HALO_CLOSED_INNER, hc))
	var rg := GenesisChoreography.reveal_glow(g, t)
	if not is_equal_approx(a, _written[0]) or not is_equal_approx(rg, _written[11]):
		_written[0] = a
		_written[11] = rg
		_body_mat.set_shader_parameter("awaken", maxf(a, minf(GenesisChoreography.body_presence(g, t) * REVEAL_WAKE, 1.0)))
		# With the radial reveal the shader's own luminous front carries the light; the inner-glow
		# boost only serves the whole-body fade fallback.
		_body_mat.set_shader_parameter("inner_glow", INNER_GLOW + (0.0 if _body_reveal else REVEAL_INNER * rg))
	if not is_equal_approx(reveal, _written[1]) or not is_equal_approx(hi, _written[2]):
		_written[1] = reveal
		_written[2] = hi
		# The hair is spun out from the knot: the growth front runs root -> tip while the plume swells.
		hair_pivot.scale = Vector3.ONE * lerpf(HAIR_GROW_SCALE, 1.0, reveal)
		hair_pivot.visible = hi > 0.002
		for i in _hair_mats.size():
			_hair_mats[i].set_shader_parameter("reveal", reveal)
			_hair_mats[i].set_shader_parameter("intensity", hi * float(HAIR_LAYERS[i][5]))
		_link_mat.set_shader_parameter("reveal", reveal)
	# The climax pulse leaves her hair first (link strands), then runs along her threads.
	var hw := GenesisChoreography.hair_wave(g, t)
	if not is_equal_approx(hw, _written[12]):
		_written[12] = hw
		_link_mat.set_shader_parameter("link_pulse", hw)
	var lk := GenesisChoreography.link(g, t, 0)
	var li := hi * lerpf(HAIR_LINK_INTENSITY.x, HAIR_LINK_INTENSITY.y, lk)
	if not is_equal_approx(li, _written[10]):
		_written[10] = li
		_link_mat.set_shader_parameter("intensity", li)
	if not is_equal_approx(gp, _written[3]):
		_written[3] = gp
		_gown_mat.set_shader_parameter("presence", gp * GOWN_LEVEL)
	if not is_equal_approx(ha, _written[4]):
		_written[4] = ha
		_halo_mat.set_shader_parameter("strength", ha)
		halo.visible = ha > 0.002
	_seed = sd
	_bloom = bloom
	if not is_equal_approx(bloom, _written[7]):
		_written[7] = bloom
		_write_seed_light()


func _update_ambient(delta: float) -> void:
	var m := MotionClock.now()
	var breath := 0.5 + 0.5 * sin(TAU * m / BREATH_PERIOD)
	_body_mat.set_shader_parameter("breath", breath)
	_halo_mat.set_shader_parameter("breath", breath)
	for mat in _hair_mats:
		mat.set_shader_parameter("motion_time", m)
	_link_mat.set_shader_parameter("motion_time", m)
	_gown_mat.set_shader_parameter("motion_time", m)
	_body_mat.set_shader_parameter("motion_time", m)
	# The seed: asleep, the ember breathes (ambient); awake it holds its narrative brightness.
	var s := _seed * (1.0 + EMBER_BREATH * _asleep * sin(TAU * m / EMBER_PERIOD))
	if not is_equal_approx(s, _written[5]):
		_written[5] = s
		_write_seed(s)
	# Suspended: the whole figure floats on a slow breath; at planet.stable she raises her head
	# (the figure tilts back around the waist and rises a little).
	figure.transform = figure_pose(m, _lift)
	# Hair: each layer sways around the crown with its own period (nebula filaments in a slow wind).
	for i in hair_layers.size():
		var sway := float(HAIR_LAYERS[i][6])
		var period := float(HAIR_LAYERS[i][7])
		var ph := TAU * m / period + float(i) * 1.9
		hair_layers[i].rotation = Vector3(sway * sin(ph), sway * 0.6 * sin(ph * 0.73 + 1.1), sway * 0.8 * cos(ph * 0.91))
	# Halo: one turn per T_HALO_TURN.
	halo.rotation.z = -TAU * fposmod(m / Palette.T_HALO_TURN, 1.0)
	# Selection / hover highlight (real-time smoothing).
	var want := 1.0 if Session.selected == ENTITY else (0.5 if Session.hovered == ENTITY else 0.0)
	if not is_equal_approx(_select, want):
		_select = move_toward(_select, want, SELECT_RATE * delta) if delta > 0.0 else want
		_body_mat.set_shader_parameter("select", _select)


## True when the shader of `mat` declares `uniform_name` (material hooks that arrive with the
## art-director's passes).
static func _declares(mat: ShaderMaterial, uniform_name: StringName) -> bool:
	if mat == null or mat.shader == null:
		return false
	for u: Dictionary in mat.shader.get_shader_uniform_list():
		if StringName(u.get("name", "")) == uniform_name:
			return true
	return false


## Transform of the figure at ambient time `m` with the climax head lift `head_lift` 0..1: the slow
## float, and at planet.stable the tilt back around the waist with a small rise. Pure (the relation
## threads follow her hair with it).
static func figure_pose(m: float, head_lift: float) -> Transform3D:
	var base := GenesisLayout.miku_transform()
	var rise := FLOAT_AMPLITUDE * sin(TAU * m / FLOAT_PERIOD + 0.7) + HEAD_LIFT_RISE * head_lift
	var basis := base.basis * Basis(Vector3.RIGHT, -HEAD_LIFT_ANGLE * head_lift) if head_lift > 0.0 else base.basis
	return Transform3D(basis, base.origin + Vector3(0.0, rise, 0.0))


# ------------------------------------------------------------------------------ build


func _build_hair() -> void:
	hair_pivot = Node3D.new()
	hair_pivot.name = "Hair"
	hair_pivot.position = _anchor("hair_root", HAIR_ROOT_FALLBACK)
	figure.add_child(hair_pivot)
	var dir := hair_heading()
	for li in HAIR_LAYERS.size():
		var L: Array = HAIR_LAYERS[li]
		var neb := HairRibbons.nebula(Vector3.ZERO, dir, int(L[1]), int(L[0]) if false else int(L[1]), float(L[3]))
		_add_hair_mesh(String(L[0]), neb["curves"], float(L[4]), float(li) * 1.37 + 0.2, PackedInt32Array(), neb["groups"], true)
	# The link strands: the mass's own seed and tufts, so each leaves the root inside a real tuft.
	var links := hair_link_curves()
	hair_links = _add_hair_mesh("HairLinks", links, HAIR_LINK_WIDTH, 3.1, PackedInt32Array(range(links.size())),
		PackedInt32Array(), false)
	_link_mat = hair_links.material_override as ShaderMaterial


func _add_hair_mesh(n: String, curves: Array[PackedVector3Array], width: float, seed: float,
		links: PackedInt32Array, groups: PackedInt32Array, sways: bool) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = n
	mi.mesh = HairRibbons.build(curves, width, 0.2, 56, Vector3.BACK, true, links, groups)
	var mat := MaterialLibrary.miku_hair().duplicate() as ShaderMaterial
	mat.set_shader_parameter("seed", seed)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 2.0
	hair_pivot.add_child(mi)
	if sways:
		hair_layers.append(mi)
		_hair_mats.append(mat)
	return mi


## Heading of the hair at the knot (object space of the sculpture).
static func hair_heading() -> Vector3:
	var tangent := GenesisLayout.anchor(MESH_NAME, "hair_root_tangent", Vector3(-0.07, 0.8, -0.6)).normalized()
	return (tangent * HAIR_TANGENT_SHARE + HAIR_DIRECTION.normalized()).normalized()


## Where each MIKU thread leaves the hair: {link index: point relative to the hair root, object
## space of the sculpture}. For each link (RelationThreads.MIKU_LINKS order) the tuft of the mass
## (layer 0) that leans most towards the thread's body (its rest position) and is not taken yet;
## the point at HAIR_LINK_SHARES of that tuft's longest strand. Pure and cached.
static func hair_sources() -> Dictionary:
	if not _sources.is_empty():
		return _sources
	var L: Array = HAIR_LAYERS[0]
	var neb := HairRibbons.nebula(Vector3.ZERO, hair_heading(), int(L[2]), HAIR_LINK_TUFTS, float(L[3]), PackedVector3Array(), L[8])
	var curves: Array = neb["curves"]
	var groups: PackedInt32Array = neb["groups"]
	# The longest strand of each tuft.
	var longest := {}
	var lengths := {}
	for c in curves.size():
		var pts: PackedVector3Array = curves[c]
		var len_c := 0.0
		for j in range(1, pts.size()):
			len_c += pts[j].distance_to(pts[j - 1])
		var tuft := groups[c]
		if not lengths.has(tuft) or len_c > float(lengths[tuft]):
			lengths[tuft] = len_c
			longest[tuft] = c
	var root := GenesisLayout.anchor(MESH_NAME, "hair_root", HAIR_ROOT_FALLBACK)
	var inv := GenesisLayout.miku_transform().affine_inverse()
	var taken := {}
	for k in RelationThreads.MIKU_LINKS.size():
		var i: int = RelationThreads.MIKU_LINKS[k]
		var share := HAIR_LINK_SHARES[k % HAIR_LINK_SHARES.size()]
		var target: StringName = GenesisScript.LINKS[i][1]
		var to_body := (inv * RelationThreads.body_point(i, target, 0.0) - root).normalized()
		var best := -1
		var best_dot := -2.0
		for tuft: int in longest:
			if taken.has(tuft):
				continue
			var p := HairRibbons.curve_point(curves[int(longest[tuft])], share)
			var d := p.normalized().dot(to_body)
			if d > best_dot:
				best_dot = d
				best = tuft
		taken[best] = true
		_sources[i] = HairRibbons.curve_point(curves[int(longest[best])], share)
	return _sources


## The link strands of the hair (relative to the hair root, object space of the sculpture), in the
## order of RelationThreads.MIKU_LINKS: long strands of the mass (layer 0's seed and tufts) ending
## exactly at RelationThreads.HAIR_SOURCES. Pure and cached (RelationThreads follows them).
static func hair_link_curves() -> Array[PackedVector3Array]:
	if not _link_curves.is_empty():
		return _link_curves
	var ends := PackedVector3Array()
	var src := hair_sources()
	for i: int in RelationThreads.MIKU_LINKS:
		ends.append(src[i])
	var L: Array = HAIR_LAYERS[0]
	var neb := HairRibbons.nebula(Vector3.ZERO, hair_heading(), int(L[2]), HAIR_LINK_TUFTS, float(L[3]), ends, L[8])
	var curves: Array = neb["curves"]
	for idx: int in neb["links"]:
		_link_curves.append(curves[idx])
	return _link_curves


func _build_halo() -> void:
	halo_pivot = Node3D.new()
	halo_pivot.name = "HaloPivot"
	var brow := _anchor("forehead", Vector3(0.0, 1.52, 0.42))
	var crown := _anchor("hair_root", Vector3(-0.08, 1.73, -0.11))
	var centre := (brow + crown) * 0.5 + Vector3(0.0, 0.02, -HALO_BACK)
	halo_pivot.position = centre
	halo_pivot.rotation = HALO_TILT
	figure.add_child(halo_pivot)
	halo = MeshInstance3D.new()
	halo.name = "Halo"
	var quad := QuadMesh.new()
	quad.size = Vector2(HALO_SIZE, HALO_SIZE)
	halo.mesh = quad
	_halo_mat = MaterialLibrary.halo_arc().duplicate() as ShaderMaterial
	halo.material_override = _halo_mat
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	halo_pivot.add_child(halo)


func _build_seed() -> void:
	var brow := _anchor("forehead", Vector3(0.0, 1.52, 0.42))
	seed_motes = MoteCloud.new()
	seed_motes.name = "Seed"
	seed_motes.setup(2, Palette.GOLD, 1.0, Vector2(0.3, 0.8), false, AABB(Vector3(-1, -1, -1), Vector3(2, 2, 2)))
	seed_motes.position = brow + Vector3(0.0, 0.0, 0.02)
	figure.add_child(seed_motes)
	seed_light = OmniLight3D.new()
	seed_light.name = "SeedLight"
	seed_light.position = brow + Vector3(0.0, 0.0, 0.12)
	seed_light.light_color = Palette.GOLD
	seed_light.omni_range = SEED_LIGHT_RANGE
	seed_light.omni_attenuation = 2.0
	seed_light.light_energy = 0.0
	seed_light.light_specular = 0.2
	seed_light.shadow_enabled = false
	seed_light.light_volumetric_fog_energy = 0.0
	figure.add_child(seed_light)


func _write_seed(s: float) -> void:
	# Core: a small HDR point that blooms softly; glow: a wide faint disc around it.
	var k := SEED_CORE_HDR * minf(s, 1.6)
	seed_motes.set_mote(0, Vector3.ZERO, SEED_CORE_SIZE, Color(k, k, k, clampf(s, 0.0, 1.0)))
	seed_motes.set_mote(1, Vector3.ZERO, SEED_GLOW_SIZE * (0.8 + 0.2 * minf(s, 1.5)), Color(1, 1, 1, 0.18 * clampf(s, 0.0, 1.5)))
	seed_motes.commit()
	seed_motes.visible = s > 0.002
	_write_seed_light()


## The brow light: small with the seed, wide and bright while it blooms (the light that reveals her).
func _write_seed_light() -> void:
	seed_light.light_energy = SEED_LIGHT_ENERGY * maxf(_written[5], 0.0) + SEED_BLOOM_ENERGY * _bloom
	seed_light.omni_range = SEED_LIGHT_RANGE + SEED_BLOOM_RANGE * _bloom
	seed_light.visible = seed_light.light_energy > 0.002


func _pick_body(bounds: AABB) -> StaticBody3D:
	var sb := StaticBody3D.new()
	sb.name = "PickBody"
	sb.collision_layer = 2
	sb.collision_mask = 0
	sb.set_meta(&"entity_id", ENTITY)
	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.75
	cap.height = bounds.size.y
	shape.shape = cap
	shape.position = bounds.get_center() + Vector3(0.0, 0.0, 0.1)
	sb.add_child(shape)
	return sb


## The gown shell: the sculpture's skirt (triangles below GOWN_TOP, bottom cap left out) pushed out
## along the normals, stretched and flared below GOWN_STRETCH_FROM so the veil of light trails past
## the porcelain hem. Built once per run (cached).
static func gown_mesh(src: Mesh) -> ArrayMesh:
	if _gown_mesh_cache != null:
		return _gown_mesh_cache
	var out := ArrayMesh.new()
	if src == null or src.get_surface_count() == 0:
		return out
	var arrays := src.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	if indices.is_empty():
		indices = PackedInt32Array(range(verts.size()))
	var remap := PackedInt32Array()
	remap.resize(verts.size())
	remap.fill(-1)
	var nv := PackedVector3Array()
	var nn := PackedVector3Array()
	var ni := PackedInt32Array()
	var bottom := GOWN_STRETCH_FROM
	for k in range(0, indices.size(), 3):
		var a := indices[k]
		var b := indices[k + 1]
		var c := indices[k + 2]
		if verts[a].y > GOWN_TOP or verts[b].y > GOWN_TOP or verts[c].y > GOWN_TOP:
			continue
		# Only the skirt: hands and forearms hang beside it at the same heights.
		if not _in_skirt(verts[a]) or not _in_skirt(verts[b]) or not _in_skirt(verts[c]):
			continue
		var fn := (normals[a] + normals[b] + normals[c]).normalized()
		if fn.y < -0.55:
			continue # bottom cap of the hem
		for idx in [a, b, c]:
			if remap[idx] < 0:
				remap[idx] = nv.size()
				var p := verts[idx] + normals[idx] * GOWN_OFFSET
				if p.y < bottom:
					var s := bottom - p.y
					var flare := 1.0 + GOWN_FLARE * s / 2.0
					p = Vector3(p.x * flare, bottom - s * (1.0 + GOWN_STRETCH), p.z * flare)
				nv.append(p)
				nn.append(normals[idx])
			ni.append(remap[idx])
	if ni.is_empty():
		return out
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = nv
	arr[Mesh.ARRAY_NORMAL] = nn
	arr[Mesh.ARRAY_INDEX] = ni
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	_gown_mesh_cache = out
	return out


## True when an object-space point belongs to the skirt's envelope (a bell around the Y axis that
## widens below the hips: SKIRT_RADIUS at the hips, + SKIRT_FLARE · depth^1.2 below SKIRT_FLARE_FROM).
static func _in_skirt(p: Vector3) -> bool:
	var below := maxf(SKIRT_FLARE_FROM - p.y, 0.0)
	return Vector2(p.x, p.z).length() < SKIRT_RADIUS + SKIRT_FLARE * pow(below, 1.2)
