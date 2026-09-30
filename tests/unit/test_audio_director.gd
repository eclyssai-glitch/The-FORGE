extends GutTest
## AudioDirector: event -> sound mapping, assets on disk, buses, stale/ORIGIN events.

const GENESIS_TYPES: Array[StringName] = [
	&"miku.awaken", &"hands.summoned", &"dust.gathered", &"planet.seeded", &"planet.layer",
	&"moon.formed", &"ring.formed", &"belt.formed", &"links.woven", &"planet.stable",
]

var director: AudioDirector


func after_each() -> void:
	if director:
		director.queue_free()
		director = null


func _event(type: StringName, time: float, payload := {}) -> SimEvent:
	return SimEvent.new(&"test", time, type, "TEST", "test event", &"", payload)


func _director() -> AudioDirector:
	director = AudioDirector.new()
	add_child(director)
	return director


func test_every_genesis_event_has_a_sound() -> void:
	for t in GENESIS_TYPES:
		var e := _event(t, 1.0, {"layer": 0, "index": 0})
		assert_ne(AudioDirector.sound_for(e), &"", "no sound for %s" % t)


func test_planet_layers_map_to_the_three_accretion_sounds() -> void:
	for layer in 3:
		var e := _event(&"planet.layer", 20.0, {"layer": layer})
		assert_eq(AudioDirector.sound_for(e), StringName("sfx_accretion_%d" % layer))
	assert_eq(AudioDirector.sound_for(_event(&"planet.layer", 20.0, {"layer": 3})), &"")
	assert_eq(AudioDirector.sound_for(_event(&"planet.layer", 20.0)), &"")


func test_second_moon_is_pitched_within_the_scale() -> void:
	assert_eq(AudioDirector.pitch_for(_event(&"moon.formed", 37.0, {"index": 0})), 1.0)
	assert_almost_eq(AudioDirector.pitch_for(_event(&"moon.formed", 40.0, {"index": 1})),
		pow(2.0, 2.0 / 12.0), 0.0001)


func test_every_sound_exists_and_loads_as_ogg_vorbis() -> void:
	for s in AudioDirector.all_sounds():
		var path := AudioDirector.sound_path(s)
		assert_true(ResourceLoader.exists(path), "missing %s" % path)
		var stream := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
		assert_true(stream is AudioStreamOggVorbis, "%s is not AudioStreamOggVorbis" % path)
		assert_gt((stream as AudioStream).get_length(), 0.2, "%s is empty" % path)


func test_ambience_stems_loop_together_and_one_shots_do_not() -> void:
	var lengths: Array[float] = []
	for s in AudioDirector.AMBIENCE_STEMS:
		var amb := ResourceLoader.load(AudioDirector.sound_path(s), "",
			ResourceLoader.CACHE_MODE_IGNORE) as AudioStreamOggVorbis
		assert_true(amb.loop, "ambience stem %s must loop" % s)
		assert_between(amb.get_length(), 60.0, 90.0)
		lengths.append(amb.get_length())
	assert_almost_eq(lengths[0], lengths[1], 0.001, "stems must have the same length (sync)")
	for s in AudioDirector.EVENT_SOUNDS.values() + AudioDirector.LAYER_SOUNDS:
		var one := ResourceLoader.load(AudioDirector.sound_path(s), "",
			ResourceLoader.CACHE_MODE_IGNORE) as AudioStreamOggVorbis
		assert_false(one.loop, "%s must not loop" % s)
		assert_between(one.get_length(), 2.0, 8.05, "%s duration" % s)


func test_ambience_plays_the_two_stems_sample_locked() -> void:
	var d := _director()
	var sync := d.ambience_player.stream as AudioStreamSynchronized
	assert_not_null(sync, "ambience must be an AudioStreamSynchronized")
	assert_eq(sync.stream_count, AudioDirector.AMBIENCE_STEMS.size())
	assert_eq(sync.get_sync_stream(AudioDirector.AMB_FLOOR).resource_path,
		AudioDirector.sound_path(AudioDirector.AMBIENCE_FLOOR))
	assert_eq(sync.get_sync_stream(1).resource_path,
		AudioDirector.sound_path(AudioDirector.AMBIENCE_AIR))
	assert_true(d.ambience_player.playing)


func test_mix_tables_cover_every_sound() -> void:
	for s in AudioDirector.all_sounds():
		if AudioDirector.AMBIENCE_STEMS.has(s):
			continue
		assert_true(AudioDirector.SOUND_GAIN_DB.has(s), "no gain for %s" % s)
	for s in AudioDirector.SOUND_ANCHORS.keys() + AudioDirector.DUCKING_SOUNDS \
			+ AudioDirector.LOW_RECESS.keys():
		assert_has(AudioDirector.all_sounds(), s)


func test_bus_layout_has_the_four_buses_routed_to_master() -> void:
	var layout := load("res://default_bus_layout.tres")
	assert_true(layout is AudioBusLayout)
	for bus in AudioDirector.BUSES:
		assert_ne(AudioServer.get_bus_index(bus), -1, "bus %s missing" % bus)
	for bus in [AudioDirector.BUS_AMBIENCE, AudioDirector.BUS_SFX, AudioDirector.BUS_UI]:
		assert_eq(AudioServer.get_bus_send(AudioServer.get_bus_index(bus)), AudioDirector.BUS_MASTER)


func test_bus_volume_and_mute_are_settable() -> void:
	var before := AudioDirector.get_bus_volume_db(AudioDirector.BUS_SFX)
	AudioDirector.set_bus_volume_db(AudioDirector.BUS_SFX, -9.0)
	assert_almost_eq(AudioDirector.get_bus_volume_db(AudioDirector.BUS_SFX), -9.0, 0.001)
	AudioDirector.set_bus_mute(AudioDirector.BUS_UI, true)
	assert_true(AudioDirector.is_bus_muted(AudioDirector.BUS_UI))
	AudioDirector.set_bus_mute(AudioDirector.BUS_UI, false)
	AudioDirector.set_bus_volume_db(AudioDirector.BUS_SFX, before)


func test_origin_chamber_events_are_ignored() -> void:
	var d := _director()
	for e in OriginChamberScript.build():
		assert_eq(AudioDirector.sound_for(e), &"", "ORIGIN type %s should be silent" % e.type)
		assert_eq(d.handle_event(e, e.time), &"")
	assert_eq(d.played_count, 0)


func test_plays_on_time_and_ignores_late_events() -> void:
	var d := _director()
	var e := _event(&"planet.seeded", 18.0)
	assert_true(AudioDirector.is_late(e, 18.6))
	assert_false(AudioDirector.is_late(e, 18.3))
	assert_eq(d.handle_event(e, 30.0), &"", "late event must not play")
	assert_eq(d.played_count, 0)
	assert_eq(d.handle_event(e, 18.1), &"sfx_planet_seed")
	assert_eq(d.played_count, 1)
	assert_eq(d.active_voices(), 1)


func test_world_rebuilt_stops_sfx_without_replaying() -> void:
	var d := _director()
	d.handle_event(_event(&"miku.awaken", 3.0), 3.0)
	d.handle_event(_event(&"hands.summoned", 8.0), 8.0)
	assert_eq(d.active_voices(), 2)
	var count := d.played_count
	Simulation.world_rebuilt.emit()
	await wait_seconds(AudioDirector.STOP_FADE + 0.2)
	assert_eq(d.active_voices(), 0)
	assert_eq(d.played_count, count, "rebuild must not start sounds")


func test_pool_steals_voices_instead_of_allocating() -> void:
	var d := _director()
	var children := d.get_child_count()
	for i in AudioDirector.POOL_2D + 4:
		d.play_sound(&"sfx_moon_form")
	assert_eq(d.get_child_count(), children)
	assert_eq(d.active_voices(), AudioDirector.POOL_2D)


func test_anchor_routes_to_positional_player() -> void:
	var d := _director()
	var planet := Node3D.new()
	add_child_autofree(planet)
	planet.position = Vector3(0.0, 1.0, 4.0)
	d.set_anchor(&"planet", planet)
	assert_eq(d.get_anchor(&"planet"), planet)
	d.play_sound(&"sfx_ring_form")
	var positional := 0
	for c in d.get_children():
		if c is AudioStreamPlayer3D and c.playing:
			positional += 1
			assert_almost_eq(c.global_position, planet.global_position, Vector3.ONE * 0.001)
	assert_eq(positional, 1)
	d.set_anchor(&"planet", null)
	assert_null(d.get_anchor(&"planet"))


func test_pause_lowers_ambience_and_resume_restores_it() -> void:
	var d := _director()
	d.set_paused(true)
	await wait_seconds(1.0)
	assert_almost_eq(d._amb_pause_db, AudioDirector.PAUSE_AMBIENCE_DB, 0.01)
	d.set_paused(false)
	await wait_seconds(1.0)
	assert_almost_eq(d._amb_pause_db, 0.0, 0.01)


func test_big_low_moments_recess_the_ambience_floor() -> void:
	# the four moments the loop-4 critique heard as a sub-bass carpet
	for e in [_event(&"hands.summoned", 8.0), _event(&"planet.seeded", 18.0),
			_event(&"planet.layer", 22.0, {"layer": 0}), _event(&"planet.stable", 53.0)]:
		assert_true(AudioDirector.LOW_RECESS.has(AudioDirector.sound_for(e)),
			"%s must recess the floor" % e.type)
	for e in [_event(&"miku.awaken", 3.0), _event(&"moon.formed", 37.0, {"index": 0}),
			_event(&"links.woven", 50.0)]:
		assert_false(AudioDirector.LOW_RECESS.has(AudioDirector.sound_for(e)),
			"%s has no low register to make room for" % e.type)


func test_recess_lowers_only_the_floor_and_releases() -> void:
	var d := _director()
	var sync := d.ambience_player.stream as AudioStreamSynchronized
	d.handle_event(_event(&"planet.layer", 22.0, {"layer": 0}), 22.0)
	await wait_seconds(AudioDirector.RECESS_ATTACK + 0.3)
	assert_almost_eq(d.ambience_floor_db(), AudioDirector.RECESS_DB, 0.01)
	assert_almost_eq(sync.get_sync_stream_volume(AudioDirector.AMB_FLOOR), AudioDirector.RECESS_DB, 0.01)
	assert_almost_eq(sync.get_sync_stream_volume(1), 0.0, 0.001, "air stem untouched")
	assert_almost_eq(d._amb_duck_db, 0.0, 0.001, "magma does not duck the whole ambience")
	Simulation.world_rebuilt.emit()
	await wait_process_frames(2)
	assert_almost_eq(d.ambience_floor_db(), 0.0, 0.001, "rebuild resets the recess")


func test_climax_keeps_the_ambience_but_recesses_its_floor() -> void:
	var d := _director()
	assert_false(AudioDirector.DUCKING_SOUNDS.has(&"sfx_planet_stable"),
		"the climax is the fullest moment: no broadband duck")
	assert_eq(d.handle_event(_event(&"planet.stable", 53.0), 53.0), &"sfx_planet_stable")
	await wait_seconds(AudioDirector.RECESS_ATTACK + 0.3)
	assert_almost_eq(d._amb_duck_db, 0.0, 0.001)
	assert_almost_eq(d.ambience_floor_db(), AudioDirector.RECESS_DB, 0.01)
