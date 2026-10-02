class_name LivingLightRig
extends Node3D
## Light of the living prototype (Loop 5). Owner: animator. Colours from Palette.
## Key (warm, high front-left, the only shadow caster), rim (cool, from behind: her silhouette
## and the hands' edges), a low fill, and a WORK light at the world being worked whose energy is
## the world's own heat (WorldBuild.energy: it glows because the hands press it — causal).
## Mood (from Miku, eased): calm = warm key, soft fill; lost composure = the key cools and hardens,
## the fill drops, the rim sharpens (she reads colder, less human); recovery brings warmth back.

const GROUP := &"living_light"
const KEY_ROT := Vector3(-38.0, -32.0, 0.0)
const RIM_ROT := Vector3(-18.0, 158.0, 0.0)
const KEY_ENERGY := Vector2(1.15, 1.35)
const FILL_ENERGY := Vector2(0.35, 0.08)
const RIM_ENERGY := Vector2(1.1, 2.1)
const WORK_ENERGY := 2.4
const MOOD_TAU := 0.9

var key: DirectionalLight3D
var rim: DirectionalLight3D
var fill: OmniLight3D
var work: OmniLight3D
var cold := 0.0


func _init() -> void:
	name = "LivingLightRig"
	key = DirectionalLight3D.new()
	key.name = "Key"
	key.rotation_degrees = KEY_ROT
	key.light_color = Palette.PEARL.lerp(Palette.GOLD, 0.18)
	key.light_energy = KEY_ENERGY.x
	key.shadow_enabled = true
	key.shadow_blur = 1.5
	key.directional_shadow_max_distance = 40.0
	key.light_volumetric_fog_energy = 0.05
	add_child(key)
	rim = DirectionalLight3D.new()
	rim.name = "Rim"
	rim.rotation_degrees = RIM_ROT
	rim.light_color = Palette.LILAC
	rim.light_energy = RIM_ENERGY.x
	rim.light_volumetric_fog_energy = 0.05
	add_child(rim)
	fill = OmniLight3D.new()
	fill.name = "Fill"
	fill.position = Vector3(-3.0, 0.5, 7.0)
	fill.omni_range = 16.0
	fill.light_color = Palette.BLUSH
	fill.light_energy = FILL_ENERGY.x
	add_child(fill)
	work = OmniLight3D.new()
	work.name = "WorkLight"
	work.omni_range = 4.0
	work.light_color = Palette.GOLD
	work.light_energy = 0.0
	add_child(work)


func _ready() -> void:
	add_to_group(GROUP)
	if not Quality.profile.is_empty():
		_on_quality(Quality.profile)
	Quality.profile_changed.connect(_on_quality)


func _on_quality(profile: Dictionary) -> void:
	key.shadow_enabled = bool(profile.get("shadows", true))
	var splits := int(profile.get("shadow_splits", 4))
	key.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL if splits <= 1 else \
		(DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS if splits == 2 else DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS)


func _process(delta: float) -> void:
	var miku := get_tree().get_first_node_in_group(Miku.GROUP) as Miku if is_inside_tree() else null
	if miku == null:
		return
	var target := miku.mind.rigidity()
	cold = lerpf(cold, target, 1.0 - exp(-delta / MOOD_TAU))
	key.light_energy = lerpf(KEY_ENERGY.x, KEY_ENERGY.y, cold)
	key.light_color = Palette.PEARL.lerp(Palette.GOLD, 0.18).lerp(Palette.ICE, cold * 0.6)
	fill.light_energy = lerpf(FILL_ENERGY.x, FILL_ENERGY.y, cold)
	rim.light_energy = lerpf(RIM_ENERGY.x, RIM_ENERGY.y, cold)
	var site := miku.worlds.site(miku.work_world) if miku.worlds != null else null
	if site != null:
		work.global_position = site.global_position
		work.omni_range = site.radius * 4.5
		work.light_energy = WORK_ENERGY * site.build.energy
