class_name ConfigSchema
extends RefCounted
## Schema of MIKU's configuration (Loop 5, ADR-016): three sections, every property typed, with
## a range, a step for relative requests ("a bit taller") and what really carries it in the game.
## Pure data. Defaults live in res://config/miku_default.json (versioned); tests keep both in sync.
##
## - identity   — modulates the mind (temperament, curiosity, patience, pride).
## - appearance — only what the rig/material really supports: bone scales (height,
##                shoulder_width, neck_length, chest_volume) and material/halo (halo_radius, glow).
##                Anything else (new hair, wings, clothes, colours...) needs new assets: listed in
##                ASSET_REQUESTS and classified REQUIRES_ASSET by the validator.
## - behaviour  — thresholds of the composure model (frustration_threshold, aggression_peak,
##                recovery_speed, interruption_tolerance).
## Property spec keys: "type" (TYPE_FLOAT), "min", "max", "step" (one relative unit),
## "binding" (what consumes it: "bone:<name> scale", "material:<uniform>", "mind:<field>"),
## "pt"/"en" (human names, used in explanations).

const IDENTITY := &"identity"
const APPEARANCE := &"appearance"
const BEHAVIOUR := &"behaviour"
const SECTIONS: Array[StringName] = [IDENTITY, APPEARANCE, BEHAVIOUR]

## Name of the configuration file artifact MIKU grabs and edits (also the user file's name).
const FILE := "miku.config.json"
## Format tag written in every config file.
const FORMAT := "korium-universe/miku-config"
## Schema version (bump on breaking changes; the store ignores user files of other versions).
const VERSION := 1

const PROPERTIES := {
	IDENTITY: {
		"temperament": {"type": TYPE_FLOAT, "min": 0.0, "max": 1.0, "step": 0.1,
			"binding": "mind:temperament (0 serene .. 1 fiery)", "pt": "temperamento", "en": "temperament"},
		"curiosity": {"type": TYPE_FLOAT, "min": 0.0, "max": 1.0, "step": 0.1,
			"binding": "mind:curiosity", "pt": "curiosidade", "en": "curiosity"},
		"patience": {"type": TYPE_FLOAT, "min": 0.0, "max": 1.0, "step": 0.1,
			"binding": "mind:patience", "pt": "paciência", "en": "patience"},
		"pride": {"type": TYPE_FLOAT, "min": 0.0, "max": 1.0, "step": 0.1,
			"binding": "mind:pride", "pt": "orgulho", "en": "pride"},
	},
	APPEARANCE: {
		"height": {"type": TYPE_FLOAT, "min": 0.9, "max": 1.1, "step": 0.03,
			"binding": "bone:root scale (uniform)", "pt": "altura", "en": "height"},
		"shoulder_width": {"type": TYPE_FLOAT, "min": 0.85, "max": 1.15, "step": 0.04,
			"binding": "bone:clavicle.L/R scale x", "pt": "largura dos ombros", "en": "shoulder width"},
		"neck_length": {"type": TYPE_FLOAT, "min": 0.9, "max": 1.12, "step": 0.03,
			"binding": "bone:neck scale y", "pt": "comprimento do pescoço", "en": "neck length"},
		"chest_volume": {"type": TYPE_FLOAT, "min": 0.35, "max": 0.65, "step": 0.03,
			"binding": "bone:chest scale xz (0.5 = sculpted)", "pt": "volume do peito", "en": "chest volume"},
		"halo_radius": {"type": TYPE_FLOAT, "min": 0.8, "max": 1.25, "step": 0.06,
			"binding": "halo:radius scale", "pt": "raio do halo", "en": "halo radius"},
		"glow": {"type": TYPE_FLOAT, "min": 0.0, "max": 1.0, "step": 0.1,
			"binding": "material:glow (emission energy)", "pt": "brilho", "en": "glow"},
	},
	BEHAVIOUR: {
		"frustration_threshold": {"type": TYPE_FLOAT, "min": 0.1, "max": 0.95, "step": 0.1,
			"binding": "mind:composure loss threshold", "pt": "limiar de frustração", "en": "frustration threshold"},
		"aggression_peak": {"type": TYPE_FLOAT, "min": 0.0, "max": 1.0, "step": 0.1,
			"binding": "mind:peak hand aggression", "pt": "pico de agressividade", "en": "aggression peak"},
		"recovery_speed": {"type": TYPE_FLOAT, "min": 0.1, "max": 1.0, "step": 0.1,
			"binding": "mind:composure recovery rate", "pt": "velocidade de recuperação", "en": "recovery speed"},
		"interruption_tolerance": {"type": TYPE_FLOAT, "min": 0.0, "max": 1.0, "step": 0.1,
			"binding": "mind:tolerance to being interrupted", "pt": "tolerância a interrupções", "en": "interruption tolerance"},
	},
}

## Appearance requests with no real support (they would need new assets): key -> {"pt", "en"}.
## A structured patch on one of these (e.g. "appearance.hair_color pink") or a phrase naming one
## ("Miku, me dê asas") is REQUIRES_ASSET. Never applied.
const ASSET_REQUESTS := {
	"hair": {"pt": "cabelo", "en": "hair"},
	"hair_color": {"pt": "cor do cabelo", "en": "hair colour"},
	"eye_color": {"pt": "cor dos olhos", "en": "eye colour"},
	"wings": {"pt": "asas", "en": "wings"},
	"outfit": {"pt": "roupa", "en": "outfit"},
	"tail": {"pt": "cauda", "en": "tail"},
	"horns": {"pt": "chifres", "en": "horns"},
	"skin_color": {"pt": "cor da pele", "en": "skin colour"},
	"face": {"pt": "rosto", "en": "face"},
	"accessory": {"pt": "acessório", "en": "accessory"},
}


static func has_section(section: StringName) -> bool:
	return SECTIONS.has(section)


## Spec of `section.key` ({} if unknown).
static func spec(section: StringName, key: String) -> Dictionary:
	var props: Dictionary = PROPERTIES.get(section, {})
	return props.get(key, {})


static func has_property(section: StringName, key: String) -> bool:
	return not spec(section, key).is_empty()


## Section that owns `key` (&"" if no section has it). Every key is unique across sections.
static func section_of(key: String) -> StringName:
	for s in SECTIONS:
		if (PROPERTIES[s] as Dictionary).has(key):
			return s
	return &""


## True when `key` names an appearance change that needs new assets.
static func requires_asset(key: String) -> bool:
	return ASSET_REQUESTS.has(key)


## Every supported "section.key" path, in schema order.
static func paths() -> PackedStringArray:
	var out := PackedStringArray()
	for s in SECTIONS:
		for k: String in PROPERTIES[s]:
			out.append("%s.%s" % [s, k])
	return out


## Splits "section.key" (or a bare "key") into [section, key]; section is &"" when absent.
static func split_path(path: String) -> Array:
	var p := path.strip_edges().to_lower()
	var dot := p.find(".")
	if dot < 0:
		return [&"", p]
	return [StringName(p.substr(0, dot)), p.substr(dot + 1)]


## Human name of a property in `lang` ("pt" | "en"), or the key itself.
static func label(section: StringName, key: String, lang: String = "pt") -> String:
	var s := spec(section, key)
	if s.is_empty():
		var a: Dictionary = ASSET_REQUESTS.get(key, {})
		return String(a.get(lang, key))
	return String(s.get(lang, key))


## Fresh section dictionaries filled with each property's range midpoint (only used when the
## versioned default file is unreadable; the store warns).
static func fallback_values() -> Dictionary:
	var out := {}
	for s in SECTIONS:
		var sec := {}
		for k: String in PROPERTIES[s]:
			var p: Dictionary = PROPERTIES[s][k]
			sec[k] = (float(p["min"]) + float(p["max"])) * 0.5
		out[String(s)] = sec
	return out
