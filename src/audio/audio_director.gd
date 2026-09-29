class_name AudioDirector
extends Node
## The sound of KORIUM UNIVERSE (GENESIS). Plays the cosmic ambience loop and the formation
## one-shots, driven only by Simulation signals (see docs/AUDIO.md).
##
## - Ambience: amb_cosmos_loop on bus Ambience, faded in on start; ducked a few dB under the big
##   SFX (tween, not sidechain: deterministic and only for the sounds that deserve it);
##   ~-6 dB and darker while PAUSED.
## - SFX: `Simulation.event_emitted` -> `sound_for(event)` -> a pooled player on bus SFX.
##   With an anchor registered for the sound's source (`set_anchor(&"planet", node)` ...) it
##   plays positionally on an AudioStreamPlayer3D that follows the anchor; otherwise 2D.
## - Seek/reset (`world_rebuilt`): SFX in flight fade out quickly; events more than
##   LATE_TOLERANCE s behind `Simulation.time` are ignored (never a burst of past sounds).
## - PAUSED: SFX fade out and pause; they resume on PLAYING.
## - Event types without a sound (ORIGIN CHAMBER types, session.*) are ignored on purpose.
## Buses (Master, Ambience, SFX, UI) come from res://default_bus_layout.tres.

const BUS_MASTER := &"Master"
const BUS_AMBIENCE := &"Ambience"
const BUS_SFX := &"SFX"
const BUS_UI := &"UI"
const BUSES: Array[StringName] = [BUS_MASTER, BUS_AMBIENCE, BUS_SFX, BUS_UI]

const AUDIO_DIR := "res://assets/audio/"
const AMBIENCE := &"amb_cosmos_loop"

## Event type -> sound (file `AUDIO_DIR + sound + ".ogg"`). `planet.layer` is resolved by its
## payload `layer` through LAYER_SOUNDS. Unlisted types play nothing.
const EVENT_SOUNDS: Dictionary = {
	&"miku.awaken": &"sfx_miku_awaken",
	&"hands.summoned": &"sfx_hands_summon",
	&"dust.gathered": &"sfx_dust_gather",
	&"planet.seeded": &"sfx_planet_seed",
	&"planet.layer": &"sfx_accretion_0",
	&"moon.formed": &"sfx_moon_form",
	&"ring.formed": &"sfx_ring_form",
	&"belt.formed": &"sfx_belt_form",
	&"links.woven": &"sfx_links_woven",
	&"planet.stable": &"sfx_planet_stable",
}
## planet.layer payload `layer` 0 (magma), 1 (crust), 2 (atmosphere).
const LAYER_SOUNDS: Array[StringName] = [&"sfx_accretion_0", &"sfx_accretion_1", &"sfx_accretion_2"]
const UI_SOUNDS: Array[StringName] = [&"ui_tick", &"ui_select"]

## Source of each sound in the world: the anchor kind registered with set_anchor().
## Sounds not listed (belt, stable) are deliberately non-positional: they surround the listener.
const SOUND_ANCHORS: Dictionary = {
	&"sfx_miku_awaken": &"miku",
	&"sfx_hands_summon": &"hands",
	&"sfx_dust_gather": &"planet",
	&"sfx_planet_seed": &"planet",
	&"sfx_accretion_0": &"planet",
	&"sfx_accretion_1": &"planet",
	&"sfx_accretion_2": &"planet",
	&"sfx_moon_form": &"planet",
	&"sfx_ring_form": &"planet",
	&"sfx_links_woven": &"miku",
}
## Mix trims (dB) on top of the asset level (assets: SFX ~-17 LUFS short-term, ambience -24 LUFS).
const SOUND_GAIN_DB: Dictionary = {
	&"sfx_miku_awaken": 0.0,
	&"sfx_hands_summon": 0.0,
	&"sfx_dust_gather": -1.5,
	&"sfx_planet_seed": 0.0,
	&"sfx_accretion_0": -1.0,
	&"sfx_accretion_1": -2.0,
	&"sfx_accretion_2": -1.5,
	&"sfx_moon_form": -2.0,
	&"sfx_ring_form": -1.5,
	&"sfx_belt_form": -2.0,
	&"sfx_links_woven": -1.5,
	&"sfx_planet_stable": 0.0,
	&"ui_tick": 0.0,
	&"ui_select": 0.0,
}
## The big moments: they duck the ambience by DUCK_DB.
const DUCKING_SOUNDS: Array[StringName] = [
	&"sfx_miku_awaken", &"sfx_hands_summon", &"sfx_planet_seed", &"sfx_planet_stable",
]
## Second moon one whole tone up (E6/B6 -> F#6/C#7, still A pentatonic).
const MOON_PITCH_STEP := 1.122462

## Events whose time is this far (s) behind the playhead are stale and not played.
const LATE_TOLERANCE := 0.5
const AMBIENCE_DB := -2.0
const AMBIENCE_FADE_IN := 4.0
const PAUSE_AMBIENCE_DB := -6.0
const PAUSE_CUTOFF_HZ := 2400.0
const OPEN_CUTOFF_HZ := 20000.0
const DUCK_DB := -4.0
const DUCK_ATTACK := 0.6
const DUCK_HOLD := 2.5
const DUCK_RELEASE := 3.0
const STOP_FADE := 0.25
const PAUSE_FADE := 0.35
const SILENT_DB := -60.0
const POOL_2D := 8
const POOL_3D := 6
## 3D: gentle inverse-distance roll-off; full level within UNIT_SIZE, -6 dB per doubling after.
const UNIT_SIZE := 16.0
const PANNING_STRENGTH := 0.7

## Last sound started by handle_event()/play_sound() and how many were started (diagnostics).
var last_played: StringName = &""
var played_count := 0
var ambience_player: AudioStreamPlayer

var _streams: Dictionary = {}
var _anchors: Dictionary = {}
var _pool_2d: Array[AudioStreamPlayer] = []
var _pool_3d: Array[AudioStreamPlayer3D] = []
var _ui_player: AudioStreamPlayer
## player -> anchor Node3D it follows while playing.
var _following: Dictionary = {}
## player -> running volume Tween.
var _voice_tweens: Dictionary = {}
var _paused := false
## Ambience gain components (dB), summed every frame.
var _amb_fade_db := SILENT_DB
var _amb_duck_db := 0.0
var _amb_pause_db := 0.0
var _amb_fade_tween: Tween
var _duck_tween: Tween
var _pause_tween: Tween


func _init() -> void:
	name = "AudioDirector"
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	for s in all_sounds():
		var stream := load(sound_path(s)) as AudioStream
		if stream:
			_streams[s] = stream
		else:
			push_warning("AudioDirector: missing sound %s" % sound_path(s))
	_build_players()
	Simulation.event_emitted.connect(_on_event_emitted)
	Simulation.world_rebuilt.connect(_on_world_rebuilt)
	Simulation.playback_changed.connect(_on_playback_changed)
	start_ambience()


func _exit_tree() -> void:
	_set_ambience_cutoff(OPEN_CUTOFF_HZ)
	if Simulation.event_emitted.is_connected(_on_event_emitted):
		Simulation.event_emitted.disconnect(_on_event_emitted)
		Simulation.world_rebuilt.disconnect(_on_world_rebuilt)
		Simulation.playback_changed.disconnect(_on_playback_changed)


func _process(_delta: float) -> void:
	if ambience_player:
		ambience_player.volume_db = ambience_db()
	for p in _following.keys():
		var anchor: Variant = _following[p]
		if not is_instance_valid(anchor) or not (p as AudioStreamPlayer3D).playing:
			_following.erase(p)
			continue
		if (anchor as Node3D).is_inside_tree():
			(p as AudioStreamPlayer3D).global_position = (anchor as Node3D).global_position


# ------------------------------------------------------------------ pure mapping


## Sound for a simulation event, or &"" when the event has no sound.
static func sound_for(event: SimEvent) -> StringName:
	if event == null:
		return &""
	if event.type == &"planet.layer":
		var layer := int(event.payload.get("layer", -1))
		if layer < 0 or layer >= LAYER_SOUNDS.size():
			return &""
		return LAYER_SOUNDS[layer]
	return EVENT_SOUNDS.get(event.type, &"")


## Pitch scale for an event's sound (only the second moon differs).
static func pitch_for(event: SimEvent) -> float:
	if event != null and event.type == &"moon.formed" and int(event.payload.get("index", 0)) % 2 == 1:
		return MOON_PITCH_STEP
	return 1.0


## True when the event is too far behind the playhead to be heard (after seek, or a hitch).
static func is_late(event: SimEvent, now: float) -> bool:
	return now - event.time > LATE_TOLERANCE


static func sound_path(sound: StringName) -> String:
	return AUDIO_DIR + String(sound) + ".ogg"


## Every sound the director may play (ambience, event sounds, UI).
static func all_sounds() -> Array[StringName]:
	var out: Array[StringName] = [AMBIENCE]
	for s in EVENT_SOUNDS.values():
		if not out.has(s):
			out.append(s)
	for s in LAYER_SOUNDS + UI_SOUNDS:
		if not out.has(s):
			out.append(s)
	return out


# ------------------------------------------------------------------ buses


static func set_bus_volume_db(bus: StringName, db: float) -> void:
	var i := AudioServer.get_bus_index(bus)
	if i >= 0:
		AudioServer.set_bus_volume_db(i, db)


static func get_bus_volume_db(bus: StringName) -> float:
	var i := AudioServer.get_bus_index(bus)
	return AudioServer.get_bus_volume_db(i) if i >= 0 else 0.0


static func set_bus_mute(bus: StringName, muted: bool) -> void:
	var i := AudioServer.get_bus_index(bus)
	if i >= 0:
		AudioServer.set_bus_mute(i, muted)


static func is_bus_muted(bus: StringName) -> bool:
	var i := AudioServer.get_bus_index(bus)
	return AudioServer.is_bus_mute(i) if i >= 0 else false


# ------------------------------------------------------------------ anchors


## Registers the world node a kind of sound comes from (&"planet", &"miku", &"hands").
## null unregisters it; the kind's sounds then play non-positionally.
func set_anchor(kind: StringName, node: Node3D) -> void:
	if node == null:
		_anchors.erase(kind)
	else:
		_anchors[kind] = node


func get_anchor(kind: StringName) -> Node3D:
	var n: Variant = _anchors.get(kind)
	if not is_instance_valid(n):
		_anchors.erase(kind)
		return null
	return n if (n as Node3D).is_inside_tree() else null


# ------------------------------------------------------------------ playback


## Plays the event's sound unless it has none or it is late. Returns the sound started or &"".
func handle_event(event: SimEvent, now: float) -> StringName:
	var sound := sound_for(event)
	if sound == &"" or is_late(event, now):
		return &""
	return sound if play_sound(sound, pitch_for(event)) else &""


## Starts a one-shot (SFX bus, or UI bus for UI_SOUNDS). Returns false if it is unknown.
func play_sound(sound: StringName, pitch := 1.0) -> bool:
	var stream: AudioStream = _streams.get(sound)
	if stream == null:
		return false
	var base_db: float = SOUND_GAIN_DB.get(sound, 0.0)
	if UI_SOUNDS.has(sound):
		_ui_player.stream = stream
		_ui_player.volume_db = base_db
		_ui_player.play()
	else:
		var anchor := get_anchor(SOUND_ANCHORS.get(sound, &""))
		var p: Node = _take_voice(anchor != null)
		p.set_meta(&"base_db", base_db)
		p.set_meta(&"started_ms", Time.get_ticks_msec())
		_kill_voice_tween(p)
		p.set(&"stream", stream)
		p.set(&"pitch_scale", pitch)
		p.set(&"volume_db", base_db)
		p.set(&"stream_paused", false)
		if anchor:
			(p as AudioStreamPlayer3D).global_position = anchor.global_position
			_following[p] = anchor
		p.call(&"play")
		if DUCKING_SOUNDS.has(sound):
			duck()
	last_played = sound
	played_count += 1
	return true


func play_ui(sound: StringName) -> bool:
	return UI_SOUNDS.has(sound) and play_sound(sound)


## Number of one-shot voices currently playing (2D + 3D).
func active_voices() -> int:
	var n := 0
	for p in _all_voices():
		if p.get(&"playing"):
			n += 1
	return n


## Fades out and stops every one-shot in flight.
func stop_all_sfx(fade := STOP_FADE) -> void:
	for p in _all_voices():
		if not p.get(&"playing"):
			continue
		_fade_voice(p, SILENT_DB, fade, true)
	_following.clear()


func start_ambience() -> void:
	if ambience_player == null or not _streams.has(AMBIENCE):
		return
	if not ambience_player.playing:
		ambience_player.play()
	if _amb_fade_tween:
		_amb_fade_tween.kill()
	_amb_fade_db = SILENT_DB
	_amb_fade_tween = create_tween()
	_amb_fade_tween.tween_property(self, "_amb_fade_db", AMBIENCE_DB, AMBIENCE_FADE_IN) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


## Current ambience player level (dB): fade-in + ducking + pause offset.
func ambience_db() -> float:
	return maxf(_amb_fade_db + _amb_duck_db + _amb_pause_db, SILENT_DB)


## Ducks the ambience by DUCK_DB for a big moment, then releases it.
func duck() -> void:
	if _duck_tween:
		_duck_tween.kill()
	_duck_tween = create_tween()
	_duck_tween.tween_property(self, "_amb_duck_db", DUCK_DB, DUCK_ATTACK) \
		.set_trans(Tween.TRANS_SINE)
	_duck_tween.tween_interval(DUCK_HOLD)
	_duck_tween.tween_property(self, "_amb_duck_db", 0.0, DUCK_RELEASE) \
		.set_trans(Tween.TRANS_SINE)


func set_paused(paused: bool) -> void:
	if paused == _paused:
		return
	_paused = paused
	if _pause_tween:
		_pause_tween.kill()
	_pause_tween = create_tween().set_parallel()
	_pause_tween.tween_property(self, "_amb_pause_db", PAUSE_AMBIENCE_DB if paused else 0.0, 0.8) \
		.set_trans(Tween.TRANS_SINE)
	var fx := _ambience_filter()
	if fx:
		_pause_tween.tween_property(fx, "cutoff_hz", PAUSE_CUTOFF_HZ if paused else OPEN_CUTOFF_HZ,
			0.8).set_trans(Tween.TRANS_SINE)
	for p in _all_voices():
		if paused:
			if p.get(&"playing") and not p.get(&"stream_paused"):
				_fade_voice(p, SILENT_DB, PAUSE_FADE, false, true)
		elif p.get(&"stream_paused"):
			p.set(&"stream_paused", false)
			_fade_voice(p, p.get_meta(&"base_db", 0.0), PAUSE_FADE, false)


# ------------------------------------------------------------------ signals


func _on_event_emitted(event: SimEvent) -> void:
	handle_event(event, Simulation.time)


func _on_world_rebuilt() -> void:
	stop_all_sfx()
	if _duck_tween:
		_duck_tween.kill()
	_amb_duck_db = 0.0


func _on_playback_changed(status: EventTimeline.Status) -> void:
	set_paused(status == EventTimeline.Status.PAUSED)


# ------------------------------------------------------------------ internals


func _build_players() -> void:
	ambience_player = AudioStreamPlayer.new()
	ambience_player.name = "Ambience"
	ambience_player.bus = BUS_AMBIENCE
	ambience_player.stream = _streams.get(AMBIENCE)
	ambience_player.volume_db = SILENT_DB
	add_child(ambience_player)
	for i in POOL_2D:
		var p := AudioStreamPlayer.new()
		p.name = "Sfx2D_%d" % i
		p.bus = BUS_SFX
		add_child(p)
		_pool_2d.append(p)
	for i in POOL_3D:
		var p := AudioStreamPlayer3D.new()
		p.name = "Sfx3D_%d" % i
		p.bus = BUS_SFX
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		p.unit_size = UNIT_SIZE
		p.max_db = 0.0
		p.panning_strength = PANNING_STRENGTH
		p.attenuation_filter_cutoff_hz = 20500.0  # no distance low-pass: the tails are already soft
		add_child(p)
		_pool_3d.append(p)
	_ui_player = AudioStreamPlayer.new()
	_ui_player.name = "Ui"
	_ui_player.bus = BUS_UI
	_ui_player.max_polyphony = 4
	add_child(_ui_player)


func _all_voices() -> Array[Node]:
	var out: Array[Node] = []
	out.append_array(_pool_2d)
	out.append_array(_pool_3d)
	return out


## A free voice of the requested kind, or the oldest one (stolen).
func _take_voice(positional: bool) -> Node:
	var pool: Array = _pool_3d if positional else _pool_2d
	var oldest: Node = pool[0]
	for p in pool:
		if not p.get(&"playing") and not p.get(&"stream_paused"):
			return p
		if int(p.get_meta(&"started_ms", 0)) < int(oldest.get_meta(&"started_ms", 0)):
			oldest = p
	oldest.call(&"stop")
	_following.erase(oldest)
	return oldest


func _kill_voice_tween(p: Node) -> void:
	var t: Tween = _voice_tweens.get(p)
	if t:
		t.kill()
	_voice_tweens.erase(p)


func _fade_voice(p: Node, to_db: float, dur: float, stop_after: bool, pause_after := false) -> void:
	_kill_voice_tween(p)
	var t := create_tween()
	t.tween_property(p, "volume_db", to_db, dur).set_trans(Tween.TRANS_SINE)
	if stop_after:
		t.tween_callback(p.stop)
	elif pause_after:
		t.tween_callback(p.set.bind(&"stream_paused", true))
	_voice_tweens[p] = t


func _ambience_filter() -> AudioEffectFilter:
	var bus := AudioServer.get_bus_index(BUS_AMBIENCE)
	if bus < 0:
		return null
	for i in AudioServer.get_bus_effect_count(bus):
		var fx := AudioServer.get_bus_effect(bus, i)
		if fx is AudioEffectLowPassFilter:
			return fx
	return null


func _set_ambience_cutoff(hz: float) -> void:
	var fx := _ambience_filter()
	if fx:
		fx.cutoff_hz = hz
