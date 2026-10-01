class_name MaterialLibrary
extends RefCounted
## Shared surface materials of the KORIUM UNIVERSE. Owner: art-director.
## Every getter returns the same cached instance on each call, so a uniform set by one entity
## (e.g. `finish` on structure()) is seen by every user of that material. Entities that need an
## independent copy (e.g. several halos with different strength) call `.duplicate()` on it.
## All colours come from Palette; no textures. Rules and rationale: docs/VISUAL_DIRECTION.md.

const SHADER_DIR := "res://src/style/shaders/"

static var _cache: Dictionary = {}


## Structure segments (FragmentStructure MultiMesh with use_custom_data = true).
## INSTANCE_CUSTOM: r = assembly, g = verify flash, b = selection/hover, a = build energy.
## Uniforms: finish, scan_y, scan_strength, final_lock, energy (all floats, see shader header).
static func structure() -> ShaderMaterial:
	if not _cache.has(&"structure"):
		var m := _shader_material("structure")
		m.set_shader_parameter("raw_color", Palette.ASH.lerp(Palette.BONE, 0.55))
		m.set_shader_parameter("finished_color", Palette.SLATE.lerp(Palette.ASH, 0.65))
		m.set_shader_parameter("edge_color", Palette.BONE)
		m.set_shader_parameter("ember_color", Palette.EMBER)
		m.set_shader_parameter("pale_color", Palette.PALE)
		m.set_shader_parameter("select_color", Palette.BONE)
		m.set_shader_parameter("finish", 0.0)
		m.set_shader_parameter("scan_y", -100.0)
		m.set_shader_parameter("scan_strength", 0.0)
		m.set_shader_parameter("final_lock", 0.0)
		m.set_shader_parameter("energy", 1.0)
		_cache[&"structure"] = m
	return _cache[&"structure"]


## Faceted dark shell of the origin core; uniform `energy` 0..1 (0 = dormant, no EMBER).
static func core_shell() -> ShaderMaterial:
	if not _cache.has(&"core_shell"):
		var m := _shader_material("core_shell")
		m.set_shader_parameter("shell_color", Palette.GRAPHITE)
		m.set_shader_parameter("rim_color", Palette.BONE)
		m.set_shader_parameter("ember_color", Palette.EMBER)
		m.set_shader_parameter("energy", 0.0)
		_cache[&"core_shell"] = m
	return _cache[&"core_shell"]


## Emissive EMBER heart of the core; uniforms `energy` 0..1 and `pulse` 0..1.
static func core_heart() -> ShaderMaterial:
	if not _cache.has(&"core_heart"):
		var m := _shader_material("core_heart")
		m.set_shader_parameter("ember_color", Palette.EMBER)
		m.set_shader_parameter("ember_deep_color", Palette.EMBER_DEEP)
		m.set_shader_parameter("energy", 0.0)
		m.set_shader_parameter("pulse", 0.0)
		_cache[&"core_heart"] = m
	return _cache[&"core_heart"]


## Verification sweep ring: PALE, additive; uniform `strength` 0..1.
static func scan_ring() -> ShaderMaterial:
	if not _cache.has(&"scan_ring"):
		var m := _shader_material("emissive_band")
		m.set_shader_parameter("color", Palette.PALE)
		m.set_shader_parameter("strength", 0.0)
		m.set_shader_parameter("intensity", 1.0)
		m.set_shader_parameter("softness", 0.85)
		_cache[&"scan_ring"] = m
	return _cache[&"scan_ring"]


## Subtle emissive halo ring; uniforms `color` (a Palette colour) and `strength` 0..1.
## Default colour BONE; set EMBER only for halos that mark energy (activation, final form).
static func halo() -> ShaderMaterial:
	if not _cache.has(&"halo"):
		var m := _shader_material("emissive_band")
		m.set_shader_parameter("color", Palette.BONE)
		m.set_shader_parameter("strength", 0.0)
		m.set_shader_parameter("intensity", 0.6)
		m.set_shader_parameter("softness", 0.9)
		_cache[&"halo"] = m
	return _cache[&"halo"]


## Chamber floor: almost black, rough, with a faint glossy reflection of the lit structure; albedo
## and specular fade to zero over the outer 15 % of the disc (uniform `edge_fade`, radius share
## 0.85 -> 1.0) so the floor dissolves into the void instead of ending in a lit edge.
## Expects a CylinderMesh (the radius is read from its cap UVs, see shaders/chamber_floor).
## (Named floor_material in GDScript would be clearer, but the contract name is kept.)
static func floor() -> ShaderMaterial:
	if not _cache.has(&"floor"):
		var m := _shader_material("chamber_floor")
		m.set_shader_parameter("floor_color", Palette.ABYSS)
		m.set_shader_parameter("specular_amount", 0.18)
		m.set_shader_parameter("roughness_amount", 0.55)
		m.set_shader_parameter("edge_fade", Vector2(0.85, 1.0))
		_cache[&"floor"] = m
	return _cache[&"floor"]


## Pillars, columns and the oculus frame: dark architectural stone-metal, never shinier than
## the structure so the eye stays on the core.
static func architecture() -> StandardMaterial3D:
	if not _cache.has(&"architecture"):
		var m := StandardMaterial3D.new()
		m.albedo_color = Palette.GRAPHITE
		m.metallic = 0.25
		m.metallic_specular = 0.4
		m.roughness = 0.72
		_cache[&"architecture"] = m
	return _cache[&"architecture"]


## Dormant seed of a future construct (UNIVERSE); uniform `energy` 0..1 (0 = cold, no EMBER).
## Hover/selection writes only `select` 0..1 (BONE rim); cold_color/cold_energy stay at rest.
static func dormant_seed() -> ShaderMaterial:
	if not _cache.has(&"dormant_seed"):
		var m := _shader_material("dormant_seed")
		m.set_shader_parameter("body_color", Palette.ABYSS)
		m.set_shader_parameter("cold_color", Palette.ASH)
		m.set_shader_parameter("ember_color", Palette.EMBER)
		m.set_shader_parameter("select_color", Palette.BONE)
		m.set_shader_parameter("energy", 0.0)
		m.set_shader_parameter("select", 0.0)
		_cache[&"dormant_seed"] = m
	return _cache[&"dormant_seed"]


## Mote material for billboarded particles (GPUParticles3D draw pass on a QuadMesh): unshaded,
## additive, round soft disc (shaders/particle_mote.gdshader), alpha from the particle colour
## ramp (vertex colour). Uniform `near_fade` (Vector2, view metres: hidden -> visible), default
## (3.5, 8.0). `color` must be a Palette colour; cached per colour — duplicate() to tune near_fade.
## GOLD-family motes (red minus blue above GOLD_MOTE_WARMTH) draw a smaller disc and only a share of
## their instances (from instance 8 on; the first motes of a cloud are never touched).
const GOLD_MOTE_WARMTH := 0.15
const GOLD_MOTE_DISC := 0.6
const GOLD_MOTE_KEEP := 0.55


static func mote(color: Color) -> ShaderMaterial:
	var key := StringName("mote_" + color.to_html(true))
	if not _cache.has(key):
		var m := _shader_material("particle_mote")
		m.set_shader_parameter("color", color)
		m.set_shader_parameter("near_fade", Vector2(3.5, 8.0))
		if color.r - color.b > GOLD_MOTE_WARMTH:
			# GOLD family: fewer, smaller motes (dust, never bokeh).
			m.set_shader_parameter("disc_radius", GOLD_MOTE_DISC)
			m.set_shader_parameter("keep_share", GOLD_MOTE_KEEP)
		_cache[key] = m
	return _cache[key]


## Solid emissive shard (non-billboard meshes such as the emission sparks): unshaded, additive,
## double-sided, colour from the material only. `color` must be a Palette colour; cached per colour.
static func spark(color: Color) -> StandardMaterial3D:
	var key := StringName("spark_" + color.to_html(true))
	if not _cache.has(key):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.albedo_color = color
		m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		m.disable_receive_shadows = true
		_cache[key] = m
	return _cache[key]


# --- GENESIS (Loop 4, v2 look). Shaders in shaders/genesis/; rules in docs/VISUAL_DIRECTION.md. ---
# Uniform conventions shared by the v2 materials:
#  - `motion_time` (float, seconds): ambient motion clock. The shaders never read TIME; the scene
#    calls MaterialLibrary.set_motion_time(MotionClock.now()) once per frame (cached instances) and
#    sets it on its own duplicates.
#  - `breath` (0..1): sine of Palette.T_BREATH, written by the animator where listed.
#  - `select` (0..1): hover/selection rim, where listed.
#  - `formation` (0..1): accretion / draw-in; 1 = complete. Never a flash.
# Instances are cached and shared; bodies with their own state (each planet, moon, thread, orbit)
# take `.duplicate()`.

const GENESIS_DIR := "genesis/"

## Octaves of the procedural noise per quality level (QualityProfiles.Level: LOW, MEDIUM, HIGH, ULTRA).
const SKY_DETAIL: Array[int] = [3, 4, 5, 5]
const PLANET_DETAIL: Array[int] = [3, 3, 4, 4]


## MIKU's body — lunar porcelain (pearl, fake subsurface, iridescent grazing sheen pearl -> rose
## -> pale gold, inner light). Vertex colour red = baked AO. Uniforms: `awaken` 0..1, `breath`
## 0..1, `select` 0..1, `inner_glow`, `sheen`, `backlight_amount`, `ao_strength`, `hollow_fill`;
## statuary (`face_soften`, `face_ao`, `torso_soften`, `head_center`/`head_radii`); skirt dissolve
## (`dissolve_top/bottom`, `light_turn`, `lip_intensity`); awakening **`reveal` 0..1** (radial from
## `reveal_origin` = the brow seed, opaque with a soft gold edge; replaces fading the whole body
## with GeometryInstance3D.transparency, which showed the skirt's inner wall).
static func miku_body() -> ShaderMaterial:
	if not _cache.has(&"miku_body"):
		var m := _shader_material(GENESIS_DIR + "miku_body")
		m.set_shader_parameter("pearl_color", Palette.PEARL)
		m.set_shader_parameter("blush_color", Palette.BLUSH)
		m.set_shader_parameter("rose_color", Palette.DUSK_ROSE)
		m.set_shader_parameter("gold_color", Palette.GOLD)
		m.set_shader_parameter("shadow_color", Palette.NEBULA.lerp(Palette.DUSK_ROSE, 0.7))
		m.set_shader_parameter("reveal_color", Palette.GOLD.lerp(Palette.PEARL, 0.25))
		m.set_shader_parameter("reveal", 1.0)
		m.set_shader_parameter("awaken", 1.0)
		m.set_shader_parameter("breath", 0.5)
		m.set_shader_parameter("select", 0.0)
		_cache[&"miku_body"] = m
	return _cache[&"miku_body"]


## Colour of a link strand's tip in MIKU's hair and of the start of every relation thread (the
## hair and the graph are one fibre): the strand runs rose -> ICE and warms to this pale gold at
## the very tip, where its thread begins.
static func hair_link_tip() -> Color:
	return Palette.GOLD.lerp(Palette.PEARL, 0.45)


## MIKU's hair — one nebula mass of additive light ribbons, pale gold (root) -> dusk rose -> lilac
## (tip), each tuft with its own tone and opacity; link strands (CUSTOM0.x) are thin bright fibres
## turning ICE -> hair_link_tip() at the tip, where their relation thread begins. Mesh: HairRibbons
## (UV.x root->tip, UV.y across; vertex alpha = strand opacity; CUSTOM0 = link, tuft, length).
## Uniforms: `reveal` 0..1, `motion_time`, `intensity`, `seed` (duplicate per ribbon set),
## `root_level` (damped stacked roots), `tone_variation`, `opacity_variation`, `link_intensity`,
## `link_core`, `link_pulse` (position 0..1 of a gold pulse on the link strands; outside = none).
static func miku_hair() -> ShaderMaterial:
	if not _cache.has(&"miku_hair"):
		var m := _shader_material(GENESIS_DIR + "miku_hair")
		m.set_shader_parameter("root_color", Palette.GOLD.lerp(Palette.PEARL, 0.35))
		m.set_shader_parameter("mid_color", Palette.DUSK_ROSE)
		m.set_shader_parameter("tip_color", Palette.LILAC)
		m.set_shader_parameter("tuft_mid_color", Palette.LILAC.lerp(Palette.PEARL, 0.3))
		m.set_shader_parameter("tuft_tip_color", Palette.NEBULA.lerp(Palette.LILAC, 0.55))
		m.set_shader_parameter("link_color", Palette.ICE)
		m.set_shader_parameter("link_tip_color", hair_link_tip())
		m.set_shader_parameter("pulse_color", Palette.GOLD.lerp(Palette.PEARL, 0.3))
		m.set_shader_parameter("link_pulse", -1.0)
		m.set_shader_parameter("reveal", 1.0)
		_cache[&"miku_hair"] = m
	return _cache[&"miku_hair"]


## MIKU's gown — additive veil of light dissolving downward into star dust (object-space Y from
## `fade_top` to `fade_bottom`, in the mesh's local units). Uniforms: `fade_top`, `fade_bottom`,
## `presence` 0..1, `motion_time`, `intensity`.
static func miku_gown() -> ShaderMaterial:
	if not _cache.has(&"miku_gown"):
		var m := _shader_material(GENESIS_DIR + "miku_gown")
		m.set_shader_parameter("top_color", Palette.PEARL.lerp(Palette.BLUSH, 0.4))
		m.set_shader_parameter("bottom_color", Palette.LILAC.lerp(Palette.DUSK_ROSE, 0.35))
		m.set_shader_parameter("dust_color", Palette.PEARL)
		m.set_shader_parameter("presence", 1.0)
		_cache[&"miku_gown"] = m
	return _cache[&"miku_gown"]


## MIKU's halo — incomplete astrolabe arc with fine graduation, drawn on a flat quad (QuadMesh /
## PlaneMesh). Constant pixel-width lines. Uniforms: `strength` 0..1, `breath` 0..1, `arc_span`.
static func halo_arc() -> ShaderMaterial:
	if not _cache.has(&"halo_arc"):
		var m := _shader_material(GENESIS_DIR + "halo_arc")
		m.set_shader_parameter("color", Palette.GOLD.lerp(Palette.PEARL, 0.45))
		m.set_shader_parameter("inner_color", Palette.DUSK_ROSE)
		m.set_shader_parameter("strength", 1.0)
		m.set_shader_parameter("breath", 0.5)
		_cache[&"halo_arc"] = m
	return _cache[&"halo_arc"]


## Auxiliary hands — legible night stone (satin, low clearcoat) with nebular depth and stars inside
## the stone, a thin ICE rim and gold kintsugi veins (always a dim inlay). Vertex colour red = baked
## AO. Uniforms: `veins` 0..1 (lit network + glow), `motion_time`, `select` 0..1, `vein_scale`,
## `star_scale`, `wrist_point`/`forearm_end`/`wrist_fade` (see set_hand_wrist).
static func hand_stone() -> ShaderMaterial:
	if not _cache.has(&"hand_stone"):
		var m := _shader_material(GENESIS_DIR + "hand_stone")
		m.set_shader_parameter("stone_color", Palette.STONE)
		m.set_shader_parameter("stone_light_color", Palette.NEBULA.lerp(Palette.LILAC, 0.12))
		m.set_shader_parameter("star_color", Palette.PEARL.lerp(Palette.ICE, 0.4))
		m.set_shader_parameter("gold_color", Palette.GOLD)
		m.set_shader_parameter("gold_deep_color", Palette.GOLD_DEEP)
		m.set_shader_parameter("rim_color", Palette.ICE)
		m.set_shader_parameter("depth_color", Palette.NEBULA.lerp(Palette.LILAC, 0.3))
		m.set_shader_parameter("veins", 0.0)
		m.set_shader_parameter("select", 0.0)
		_cache[&"hand_stone"] = m
	return _cache[&"hand_stone"]


## Wrist dissolve of a hand_stone() duplicate: the forearm turns into grains from `wrist` toward
## `forearm_end` (object space of the hand mesh: the sculpt's "wrist_center" / "forearm_end"
## anchors). `fade` = shares of that segment where the dissolve starts / nothing is left.
static func set_hand_wrist(m: ShaderMaterial, wrist: Vector3, forearm_end: Vector3,
		fade := Vector2(0.05, 0.85)) -> void:
	m.set_shader_parameter("wrist_point", wrist)
	m.set_shader_parameter("forearm_end", forearm_end)
	m.set_shader_parameter("wrist_fade", fade)


## Forming planet (sub-agent). Uniforms 0..1: `formation` (accretion, gold growing edge), `heat`
## (flowing golden magma), `crust` (dark cracked plates, glowing cracks), `atmosphere` (lit ICE
## limb, DUSK_ROSE terminator, haze; the formed world's seas, rose land and drifting clouds). Also
## `motion_time`, `seed` (per planet), `detail` (octaves), `select`, `world_style`, and the look of
## the formed world: `terminator_amount`, `scatter_amount`, `wrap_amount`, `glint_amount`,
## `cloud_amount`. Far, already-formed planets use a duplicate with formation 1, heat ~0.1,
## crust 1, atmosphere 1 and their family (set_far_world_style).
static func planet_forming() -> ShaderMaterial:
	if not _cache.has(&"planet_forming"):
		var m := _shader_material(GENESIS_DIR + "planet_forming")
		m.set_shader_parameter("magma_hot_color", Palette.GOLD)
		m.set_shader_parameter("magma_mid_color", Palette.MAGMA)
		m.set_shader_parameter("magma_deep_color", Palette.GOLD_DEEP)
		m.set_shader_parameter("crust_color", Palette.STONE)
		m.set_shader_parameter("crust_light_color", Palette.INDIGO.lerp(Palette.DUSK_ROSE, 0.18))
		m.set_shader_parameter("atmo_inner_color", Palette.ICE)
		m.set_shader_parameter("atmo_outer_color", Palette.DUSK_ROSE)
		m.set_shader_parameter("accretion_color", Palette.GOLD)
		m.set_shader_parameter("land_color", Palette.DUSK_ROSE.lerp(Palette.GOLD, 0.2))
		m.set_shader_parameter("ocean_color", Palette.INDIGO.lerp(Palette.ICE, 0.42))
		m.set_shader_parameter("cloud_color", Palette.PEARL.lerp(Palette.ICE, 0.2))
		m.set_shader_parameter("band_color", Palette.ICE.lerp(Palette.PEARL, 0.2))
		m.set_shader_parameter("dust_color", Palette.DUSK_ROSE.lerp(Palette.BLUSH, 0.3))
		m.set_shader_parameter("formation", 1.0)
		m.set_shader_parameter("heat", 1.0)
		m.set_shader_parameter("crust", 0.0)
		m.set_shader_parameter("atmosphere", 0.0)
		m.set_shader_parameter("detail", PLANET_DETAIL[2])
		_cache[&"planet_forming"] = m
	return _cache[&"planet_forming"]


## Families of the distant, already-formed worlds (`world_style` of planet_forming()): x = ICE
## latitude bands, y = rose dust. Index = GenesisScript.FAR_PLANET_NAMES order.
const FAR_WORLD_STYLES: Array[Vector2] = [Vector2(1.0, 0.0), Vector2(0.0, 1.0)]


## Gives a planet_forming() duplicate the look of distant world `index` (FAR_WORLD_STYLES).
static func set_far_world_style(m: ShaderMaterial, index: int) -> void:
	m.set_shader_parameter("world_style", FAR_WORLD_STYLES[posmod(index, FAR_WORLD_STYLES.size())])


## Documentation moon — knowledge ice: frosted pale ice with faint strata (pages), cool
## backlight, thin ice rim. Uniforms: `formation` 0..1 (accretion), `glow` 0..1, `seed`, `select`.
static func moon_doc() -> ShaderMaterial:
	if not _cache.has(&"moon_doc"):
		var m := _shader_material(GENESIS_DIR + "moon_doc")
		m.set_shader_parameter("ice_color", Palette.ICE)
		m.set_shader_parameter("deep_color", Palette.INDIGO.lerp(Palette.ICE, 0.25))
		m.set_shader_parameter("light_color", Palette.PEARL)
		m.set_shader_parameter("accretion_color", Palette.ICE.lerp(Palette.PEARL, 0.5))
		m.set_shader_parameter("formation", 1.0)
		m.set_shader_parameter("glow", 0.5)
		m.set_shader_parameter("select", 0.0)
		_cache[&"moon_doc"] = m
	return _cache[&"moon_doc"]


## Skill ring — fine bands of pale gold light on a flat quad (PlaneMesh; radius from UV, between
## `inner` and `outer` shares of the half-size). Uniforms: `formation` 0..1 (angular sweep with a
## warm leading edge), `intensity`, `inner`, `outer`, `bands`, `seed`.
static func ring_skill() -> ShaderMaterial:
	if not _cache.has(&"ring_skill"):
		var m := _shader_material(GENESIS_DIR + "ring_skill")
		m.set_shader_parameter("color", Palette.GOLD.lerp(Palette.PEARL, 0.3))
		m.set_shader_parameter("accent_color", Palette.GOLD)
		m.set_shader_parameter("formation", 1.0)
		_cache[&"ring_skill"] = m
	return _cache[&"ring_skill"]


## Memory belt rocks — rough night stone with a nebula rim; a share of the rocks (by INSTANCE_ID)
## hold a quiet gold glint. Uniforms: `memory` 0..1 (glints), `glint_share`, `rim_intensity`.
static func asteroid_memory() -> ShaderMaterial:
	if not _cache.has(&"asteroid_memory"):
		var m := _shader_material(GENESIS_DIR + "asteroid_memory")
		m.set_shader_parameter("rock_color", Palette.STONE)
		m.set_shader_parameter("rock_light_color", Palette.INDIGO.lerp(Palette.DUSK_ROSE, 0.2))
		m.set_shader_parameter("rim_color", Palette.DUSK_ROSE.lerp(Palette.LILAC, 0.5))
		m.set_shader_parameter("glint_color", Palette.GOLD)
		m.set_shader_parameter("memory", 1.0)
		_cache[&"asteroid_memory"] = m
	return _cache[&"asteroid_memory"]


## Orbit — thin additive line fading along the arc behind the body. Mesh: closed ribbon, UV.x
## along the orbit (direction of motion), UV.y across. Uniforms: `head` 0..1 (body position),
## `trail`, `base`, `formation` 0..1 (draw-in), `intensity`, `color`.
static func orbit_line() -> ShaderMaterial:
	if not _cache.has(&"orbit_line"):
		var m := _shader_material(GENESIS_DIR + "orbit_line")
		m.set_shader_parameter("color", Palette.PEARL.lerp(Palette.LILAC, 0.6))
		m.set_shader_parameter("head", 0.0)
		m.set_shader_parameter("formation", 1.0)
		_cache[&"orbit_line"] = m
	return _cache[&"orbit_line"]


## Relation thread (link) — fibre of light prolonging the hair: hair_link_tip() at the source (the
## colour a link strand of the hair ends with) -> `color_to`
## at the target (default ICE; GOLD for the forming planet). Mesh: UV.x source->target, UV.y
## across. Uniforms: `pulse` (0..1 position of a travelling gold pulse; outside = none), `woven`
## 0..1 (spun out from the source), `intensity`, `color_to`.
static func relation_thread() -> ShaderMaterial:
	if not _cache.has(&"relation_thread"):
		var m := _shader_material(GENESIS_DIR + "relation_thread")
		m.set_shader_parameter("color_from", hair_link_tip())
		m.set_shader_parameter("color_to", Palette.ICE)
		m.set_shader_parameter("pulse_color", Palette.GOLD.lerp(Palette.PEARL, 0.3))
		m.set_shader_parameter("pulse", -1.0)
		m.set_shader_parameter("woven", 1.0)
		_cache[&"relation_thread"] = m
	return _cache[&"relation_thread"]


## GENESIS sky (Sky.sky_material): indigo/violet nebula with a warm dusk-rose core toward
## `warm_dir` (default: world -Z slightly above the horizon — behind MIKU from the FORGE camera),
## dark dust lanes, three star layers, dithering. Uniforms: `warm_dir`, `motion_time` (star
## twinkle; see the shader note about radiance updates), `detail` (octaves), `sky_energy`,
## `star_intensity`, `nebula_intensity`, `warm_intensity`, `radiance_strength`.
static func nebula_sky() -> ShaderMaterial:
	if not _cache.has(&"nebula_sky"):
		var m := _shader_material(GENESIS_DIR + "nebula_sky")
		m.set_shader_parameter("deep_color", Palette.SPACE_DEEP)
		m.set_shader_parameter("indigo_color", Palette.INDIGO)
		m.set_shader_parameter("nebula_color", Palette.NEBULA)
		m.set_shader_parameter("lilac_color", Palette.LILAC)
		m.set_shader_parameter("warm_color", Palette.DUSK_ROSE)
		m.set_shader_parameter("core_color", Palette.GOLD.lerp(Palette.BLUSH, 0.5))
		m.set_shader_parameter("pearl_color", Palette.PEARL)
		m.set_shader_parameter("gold_color", Palette.GOLD)
		m.set_shader_parameter("star_color", Palette.PEARL)
		m.set_shader_parameter("star_warm_color", Palette.BLUSH)
		m.set_shader_parameter("star_cool_color", Palette.ICE)
		m.set_shader_parameter("warm_dir", Vector3(0.0, 0.22, -1.0))
		m.set_shader_parameter("detail", SKY_DETAIL[2])
		_cache[&"nebula_sky"] = m
	return _cache[&"nebula_sky"]


## Names of the GENESIS getters (tests, lookdev, quality/motion broadcasts).
const GENESIS_MATERIALS: Array[StringName] = [
	&"miku_body", &"miku_hair", &"miku_gown", &"halo_arc", &"hand_stone", &"planet_forming",
	&"moon_doc", &"ring_skill", &"asteroid_memory", &"orbit_line", &"relation_thread", &"nebula_sky",
]


## GENESIS material by name (one of GENESIS_MATERIALS); null for an unknown name.
static func genesis(material_name: StringName) -> ShaderMaterial:
	match material_name:
		&"miku_body": return miku_body()
		&"miku_hair": return miku_hair()
		&"miku_gown": return miku_gown()
		&"halo_arc": return halo_arc()
		&"hand_stone": return hand_stone()
		&"planet_forming": return planet_forming()
		&"moon_doc": return moon_doc()
		&"ring_skill": return ring_skill()
		&"asteroid_memory": return asteroid_memory()
		&"orbit_line": return orbit_line()
		&"relation_thread": return relation_thread()
		&"nebula_sky": return nebula_sky()
	return null


## Writes `motion_time` on every cached material that has it (call once per frame with
## MotionClock.now()). Duplicates are owned by their entity, which sets it itself.
static func set_motion_time(t: float) -> void:
	_motion_time = t
	for key: StringName in _cache:
		var m := _cache[key] as ShaderMaterial
		if m != null and _has_uniform(m, &"motion_time"):
			m.set_shader_parameter("motion_time", t)


## Noise octaves of the sky and the planets per quality profile (QualityProfiles.get_profile);
## affects the cached instances — duplicates made afterwards inherit it.
static func apply_quality(profile: Dictionary) -> void:
	var level := clampi(int(profile.get("level", 2)), 0, SKY_DETAIL.size() - 1)
	nebula_sky().set_shader_parameter("detail", SKY_DETAIL[level])
	planet_forming().set_shader_parameter("detail", PLANET_DETAIL[level])


static var _uniform_cache: Dictionary = {}
## Last value given to set_motion_time (new materials start from it).
static var _motion_time: float = 0.0


static func _has_uniform(m: ShaderMaterial, uniform_name: StringName) -> bool:
	if m.shader == null:
		return false
	var key := "%s|%s" % [m.shader.resource_path, uniform_name]
	if not _uniform_cache.has(key):
		var found := false
		for u: Dictionary in m.shader.get_shader_uniform_list():
			if StringName(u["name"]) == uniform_name:
				found = true
				break
		_uniform_cache[key] = found
	return _uniform_cache[key]


## Drops every cached material (tests / hot reload). Existing users keep their instances.
static func clear_cache() -> void:
	_cache.clear()


static func _shader_material(shader_name: String) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load(SHADER_DIR + shader_name + ".gdshader") as Shader
	# A material created after set_motion_time() starts at the current motion clock.
	if _has_uniform(m, &"motion_time"):
		m.set_shader_parameter("motion_time", _motion_time)
	return m
