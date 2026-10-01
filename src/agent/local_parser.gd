class_name LocalParser
extends RefCounted
## Deterministic local parser (pt-BR + en) of what the user tells MIKU on the call line
## (Loop 5, ADR-016). No tokens, no network, no randomness: same text + same worlds = same Intent.
##
## Rules, first match wins:
##   1. structured   "appearance.height 1.04", "chest_volume 0.52", "set behaviour.patience 0.7",
##                   "defina glow 0,8" -> CONFIG_PATCH (absolute)
##   2. compound     contrast or several changes in one sentence ("mais curiosa, mas menos
##                   impulsiva") -> SEMANTIC (only a provider could weigh it)
##   3. asset        a body/appearance feature with no rig support (asas, cabelo, roupa, wings...)
##                   -> CONFIG_PATCH on appearance.<feature> (the validator says REQUIRES_ASSET)
##   4. appearance   a supported appearance property + a direction ("aumente sua altura", "ombros
##                   um pouco mais largos", "a bit taller") -> CONFIG_PATCH (relative: one schema
##                   step x magnitude: "um pouco"/"a bit" 0.5, default 1, "muito"/"a lot" 2)
##   5. world        a world by side (esquerda/direita/centro, left/right/center) or by name
##                   ("trabalhe no planeta da esquerda", "work on ORRIN") -> WORLD_TARGET
##   6. attention    only her name and call words ("Miku!", "Miku, olha aqui", "look at me")
##                   -> ATTENTION
##   7. otherwise    any other words -> SEMANTIC (personality in natural language — "fique mais
##                   curiosa" — is subjective by design); no words -> UNKNOWN
## Worlds are given by the caller: [{"id": StringName, "name": String, "side": &"left"|&"center"|&"right"}]
## (LivingInteraction computes the sides from what the camera shows).

const NAME := "miku"

## Words that only call her (rule 6).
const CALL_WORDS: Array[String] = [
	"ei", "oi", "ola", "hey", "hi", "hello", "psst", "por", "favor", "please", "aqui", "here",
	"olha", "olhe", "olhar", "look", "me", "mim", "at", "para", "pra", "venha", "vem", "come",
	"atencao", "attention", "ai", "querida", "dear", "you", "voce", "ca", "over",
]
## Contrast/conjunction words that make a sentence compound (rule 2).
const CONTRAST_WORDS: Array[String] = ["mas", "porem", "entretanto", "contudo", "but", "however", "although", "though"]

## Asset feature words (rule 3) -> ConfigSchema.ASSET_REQUESTS key.
const ASSET_WORDS := {
	"cabelo": "hair", "cabelos": "hair", "hair": "hair", "franja": "hair", "tranca": "hair",
	"olhos": "eye_color", "olho": "eye_color", "eyes": "eye_color", "eye": "eye_color",
	"asas": "wings", "asa": "wings", "wings": "wings", "wing": "wings",
	"roupa": "outfit", "roupas": "outfit", "vestido": "outfit", "outfit": "outfit", "dress": "outfit",
	"clothes": "outfit", "clothing": "outfit",
	"cauda": "tail", "rabo": "tail", "tail": "tail",
	"chifres": "horns", "chifre": "horns", "horns": "horns", "horn": "horns",
	"pele": "skin_color", "skin": "skin_color",
	"rosto": "face", "face": "face",
	"coroa": "accessory", "crown": "accessory", "oculos": "accessory", "glasses": "accessory",
	"brincos": "accessory", "earrings": "accessory", "colar": "accessory", "necklace": "accessory",
}

## Supported appearance properties (rule 4): words naming them, and property-specific
## adjectives with their direction (+1 / -1).
const PROPERTY_WORDS := {
	"height": ["altura", "estatura", "height", "alta", "alto", "baixa", "baixo", "taller", "tall",
		"cresca", "crescer"],
	"shoulder_width": ["ombro", "ombros", "shoulder", "shoulders"],
	"neck_length": ["pescoco", "neck"],
	"chest_volume": ["peito", "busto", "torax", "chest", "bust"],
	"halo_radius": ["halo", "aureola"],
	"glow": ["brilho", "glow", "luz", "luminosidade", "brilhe", "brilhar", "brilhante", "shine",
		"brighter", "dimmer", "radiance"],
}
const PROPERTY_ADJECTIVES := {
	"height": {"alta": 1, "alto": 1, "altas": 1, "tall": 1, "taller": 1, "cresca": 1, "crescer": 1,
		"grow": 1, "baixa": -1, "baixo": -1, "short": -1, "shorter": -1, "shrink": -1},
	"shoulder_width": {"largos": 1, "largo": 1, "larga": 1, "largas": 1, "wide": 1, "wider": 1,
		"broad": 1, "broader": 1, "estreitos": -1, "estreito": -1, "estreita": -1, "narrow": -1,
		"narrower": -1},
	"neck_length": {"longo": 1, "comprido": 1, "longa": 1, "long": 1, "longer": 1, "curto": -1,
		"curta": -1, "short": -1, "shorter": -1},
	"chest_volume": {"volumoso": 1, "cheio": 1, "fuller": 1, "full": 1, "bigger": 1,
		"plano": -1, "flat": -1, "flatter": -1, "smaller": -1},
	"halo_radius": {"largo": 1, "wide": 1, "wider": 1, "larger": 1, "bigger": 1, "estreito": -1,
		"narrower": -1, "smaller": -1, "tighter": -1},
	"glow": {"brilhante": 1, "brilhe": 1, "brilhar": 1, "shine": 1, "brighter": 1, "bright": 1,
		"luminosa": 1, "apagada": -1, "dimmer": -1, "dim": -1, "apague": -1, "fosca": -1},
}
const UP_WORDS: Array[String] = [
	"aumente", "aumentar", "aumenta", "aumento", "mais", "maior", "maiores", "increase", "raise",
	"more", "bigger", "larger", "higher", "eleve", "suba", "amplie", "alongue", "estique",
	"alargue", "alarga", "up", "expand", "grow",
]
const DOWN_WORDS: Array[String] = [
	"diminua", "diminuir", "diminui", "reduza", "reduzir", "reduz", "menos", "menor", "menores",
	"decrease", "reduce", "lower", "less", "smaller", "encurte", "estreite", "abaixe", "down",
]
## Negators of a following adjective ("menos alta" = shorter).
const NEGATORS: Array[String] = ["menos", "less"]
const SMALL_WORDS: Array[String] = ["pouco", "pouquinho", "levemente", "ligeiramente", "slightly", "bit", "little", "tico", "tad"]
const LARGE_WORDS: Array[String] = ["muito", "bem", "bastante", "much", "lot", "way", "lots"]
const SMALL_FACTOR := 0.5
const LARGE_FACTOR := 2.0

const SIDE_WORDS := {
	"esquerda": &"left", "esquerdo": &"left", "left": &"left",
	"direita": &"right", "direito": &"right", "right": &"right",
	"centro": &"center", "meio": &"center", "central": &"center", "center": &"center",
	"middle": &"center",
}
const WORLD_WORDS: Array[String] = ["planeta", "planetas", "mundo", "mundos", "world", "worlds", "planet", "planets", "obra"]

const PT_MARKERS: Array[String] = [
	"voce", "sua", "seu", "mais", "menos", "um", "pouco", "da", "do", "no", "na", "planeta",
	"mundo", "olha", "olhe", "aqui", "trabalhe", "aumente", "diminua", "fique", "mas", "ombros",
	"altura", "brilho", "para", "pra", "de", "e", "que", "com", "muito", "me", "mim",
]
const EN_MARKERS: Array[String] = [
	"your", "you", "the", "a", "bit", "more", "less", "planet", "world", "look", "here", "work",
	"on", "increase", "decrease", "make", "but", "taller", "shoulders", "height", "glow", "at",
	"please", "be", "and", "of", "to", "much", "little",
]

static var _structured: RegEx


## Intent of `text`. `worlds`: the selectable worlds (see class doc).
static func parse(text: String, worlds: Array = []) -> Intent:
	var raw := text.strip_edges()
	var norm := normalize(raw)
	var words := tokenize(norm)
	var lang := detect_language(raw, words)

	# 1. structured command
	var structured := _parse_structured(norm)
	if structured != null:
		return _done(_config_intent(raw, structured), lang, "structured")
	if words.is_empty():
		return _done(Intent.make(Intent.Kind.UNKNOWN, raw), lang, "empty")

	# 2. compound / contrast
	var props := _properties_in(words)
	for w in words:
		if CONTRAST_WORDS.has(w):
			return _done(Intent.make(Intent.Kind.SEMANTIC, raw), lang, "compound:" + w)
	if props.size() > 1:
		return _done(Intent.make(Intent.Kind.SEMANTIC, raw), lang, "compound:properties")

	# 3. appearance feature that needs new assets
	for w in words:
		if ASSET_WORDS.has(w):
			var key: String = ASSET_WORDS[w]
			var p := StructuredPatch.absolute("%s.%s" % [ConfigSchema.APPEARANCE, key], raw)
			p.text = raw
			return _done(_config_intent(raw, p), lang, "asset:" + key)

	# 4. supported appearance property + direction
	if props.size() == 1:
		var key: String = props[0]
		var dir := _direction(key, words)
		if dir != 0:
			var step := float(ConfigSchema.spec(ConfigSchema.APPEARANCE, key)["step"])
			var p := StructuredPatch.relative_change("%s.%s" % [ConfigSchema.APPEARANCE, key],
				step * _magnitude(words) * dir)
			p.text = raw
			return _done(_config_intent(raw, p), lang, "appearance:" + key)
		return _done(Intent.make(Intent.Kind.SEMANTIC, raw), lang, "appearance_without_direction:" + key)

	# 5. world by name or side
	var world_rule := _world_reference(words, worlds)
	if world_rule.size() > 0:
		var id: StringName = world_rule[0]
		if id == &"":
			return _done(Intent.make(Intent.Kind.UNKNOWN, raw), lang, "world_not_found:" + String(world_rule[1]))
		return _done(Intent.make(Intent.Kind.WORLD_TARGET, raw, id), lang, "world:" + String(world_rule[1]))

	# 6. attention
	var rest := PackedStringArray()
	for w in words:
		if w != NAME and not CALL_WORDS.has(w):
			rest.append(w)
	if rest.is_empty():
		return _done(Intent.make(Intent.Kind.ATTENTION, raw, &"miku"), lang, "attention")

	# 7. anything else in words
	return _done(Intent.make(Intent.Kind.SEMANTIC, raw), lang, "natural")


## Lower case, accents folded (á -> a, ç -> c...), whitespace collapsed. Keeps punctuation.
static func normalize(text: String) -> String:
	var t := text.to_lower()
	var from := "áàâãäéèêëíìîïóòôõöúùûüçñ"
	var to := "aaaaaeeeeiiiiooooouuuucn"
	var out := ""
	for ch in t:
		var i := from.find(ch)
		out += to[i] if i >= 0 else ch
	var ws := RegEx.create_from_string("\\s+")
	return ws.sub(out, " ", true).strip_edges()


## Words of a normalized text (letters and digits only).
static func tokenize(norm: String) -> PackedStringArray:
	var re := RegEx.create_from_string("[a-z0-9]+")
	var out := PackedStringArray()
	for m in re.search_all(norm):
		out.append(m.get_string())
	return out


## "pt" | "en" | "" (undecided): accents count for Portuguese, then marker words.
static func detect_language(raw: String, words: PackedStringArray) -> String:
	var pt := 0
	var en := 0
	for ch in raw.to_lower():
		if "áàâãéêíóôõúç".contains(ch):
			pt += 1
	for w in words:
		if PT_MARKERS.has(w):
			pt += 1
		if EN_MARKERS.has(w):
			en += 1
	if pt == 0 and en == 0:
		return ""
	return "pt" if pt >= en else "en"


# ------------------------------------------------------------------ rules


## Rule 1: "[miku[,:]] [set|defina|definir|ajuste|ajustar|configure] <path> [=|:|to|para|em] <value>".
## Only when <path> is "section.key" with a known section, or a known key / asset feature.
static func _parse_structured(norm: String) -> StructuredPatch:
	if _structured == null:
		_structured = RegEx.create_from_string(
			"^(?:miku\\s*[,:!]?\\s*)?(?:(?:set|defina|definir|ajuste|ajustar|configure|configurar)\\s+)?"
			+ "([a-z_]+(?:\\.[a-z_]+)?)\\s*(?:=|:|\\bto\\b|\\bpara\\b|\\bem\\b)?\\s*([a-z0-9#_.,+-]+)\\s*[.!]?$")
	var m := _structured.search(norm)
	if m == null:
		return null
	var path := m.get_string(1)
	var parts := ConfigSchema.split_path(path)
	var section: StringName = parts[0]
	var key: String = parts[1]
	var known := ConfigSchema.section_of(key) != &"" or ConfigSchema.requires_asset(key)
	if section != &"":
		if not (ConfigSchema.has_section(section) or known):
			return null
	elif not known:
		return null
	var value_text := m.get_string(2)
	var number := value_text.replace(",", ".")
	var value: Variant = value_text
	if number.is_valid_float():
		value = number.to_float()
	var p := StructuredPatch.absolute(path, value)
	p.text = norm
	return p


## Supported appearance properties named in `words` (each once, schema order).
static func _properties_in(words: PackedStringArray) -> Array[String]:
	var out: Array[String] = []
	for key: String in PROPERTY_WORDS:
		for w in words:
			if (PROPERTY_WORDS[key] as Array).has(w):
				out.append(key)
				break
	return out


## +1 / -1 / 0: property adjectives first (negated by a preceding "menos"/"less"), then generic
## up/down words.
static func _direction(key: String, words: PackedStringArray) -> int:
	var adjectives: Dictionary = PROPERTY_ADJECTIVES.get(key, {})
	for i in words.size():
		if adjectives.has(words[i]):
			var d: int = adjectives[words[i]]
			if i > 0 and NEGATORS.has(words[i - 1]):
				d = -d
			return d
	for w in words:
		if UP_WORDS.has(w):
			return 1
		if DOWN_WORDS.has(w):
			return -1
	return 0


static func _magnitude(words: PackedStringArray) -> float:
	for w in words:
		if SMALL_WORDS.has(w):
			return SMALL_FACTOR
	for w in words:
		if LARGE_WORDS.has(w):
			return LARGE_FACTOR
	return 1.0


## [world id, rule word] for a world named or placed by side in `words`; [&"", word] when the
## reference names nothing known; [] when the words do not refer to a world.
static func _world_reference(words: PackedStringArray, worlds: Array) -> Array:
	for w: Dictionary in worlds:
		var wname := normalize(String(w.get("name", "")))
		if wname != "" and words.has(wname):
			return [StringName(w.get("id", &"")), wname]
		var short := String(w.get("id", "")).trim_prefix("world_")
		if short != "" and words.has(short):
			return [StringName(w.get("id", &"")), short]
	var side: StringName = &""
	var side_word := ""
	for word in words:
		if SIDE_WORDS.has(word):
			side = SIDE_WORDS[word]
			side_word = word
			break
	if side == &"":
		return []
	var mentions_world := false
	for word in words:
		if WORLD_WORDS.has(word):
			mentions_world = true
	if not mentions_world and not words.has("trabalhe") and not words.has("work"):
		return []
	for w: Dictionary in worlds:
		if StringName(w.get("side", &"")) == side:
			return [StringName(w.get("id", &"")), side_word]
	return [&"", side_word]


static func _config_intent(raw: String, patch: StructuredPatch) -> Intent:
	var i := Intent.make(Intent.Kind.CONFIG_PATCH, raw, &"miku")
	i.patch = patch
	return i


static func _done(i: Intent, lang: String, rule: String) -> Intent:
	i.lang = lang
	i.rule = rule
	return i
