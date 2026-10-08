extends Node

const BGM_ROOM := preload("res://assets/audio/music/ambient_room_01.wav")
const BGM_COURTYARD := preload("res://assets/audio/music/ambient_courtyard_02.wav")
const SFX_GUNSHOT := preload("res://assets/audio/sfx/gunshot.wav")
const SFX_RELOAD := preload("res://assets/audio/sfx/reload.wav")
const SFX_FOOTSTEP := preload("res://assets/audio/sfx/footstep.wav")
const SFX_VICTORY := preload("res://assets/audio/sfx/victory.wav")
const SFX_DEFEAT := preload("res://assets/audio/sfx/defeat.wav")
const SFX_UI_CLICK := preload("res://assets/audio/sfx/ui_click.wav")

var _tracks: Array[AudioStreamWAV] = []
var _level_music := {
	&"MainMenu": 0,
	&"Level01": 0,
	&"Level02": 1,
	&"Main": 1,
}

var _bgm_a: AudioStreamPlayer
var _bgm_b: AudioStreamPlayer
var _active_bgm := 0
var _current_track := -2
var _crossfade: Tween

var _sfx_pool: Array[AudioStreamPlayer] = []
var _sfx_index := 0
const SFX_POOL_SIZE := 10

func _ready() -> void:
	_ensure_buses()
	_bgm_a = AudioStreamPlayer.new()
	_bgm_b = AudioStreamPlayer.new()
	_bgm_a.bus = "Music"
	_bgm_b.bus = "Music"
	_bgm_a.process_mode = Node.PROCESS_MODE_ALWAYS
	_bgm_b.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_bgm_a)
	add_child(_bgm_b)
	_tracks.clear()
	_tracks.append(BGM_ROOM)
	_tracks.append(BGM_COURTYARD)
	for t in _tracks:
		t.loop_mode = AudioStreamWAV.LOOP_FORWARD
		t.loop_begin = 0
		t.loop_end = t.data.size() / 2
	for i in SFX_POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		p.process_mode = Node.PROCESS_MODE_ALWAYS
		_sfx_pool.append(p)
		add_child(p)

func _process(_delta: float) -> void:
	_auto_switch_bgm()

func _ensure_buses() -> void:
	if AudioServer.get_bus_index("Music") == -1:
		AudioServer.add_bus()
		AudioServer.set_bus_name(AudioServer.bus_count - 1, "Music")
		AudioServer.set_bus_volume_db(AudioServer.bus_count - 1, -8.0)
	if AudioServer.get_bus_index("SFX") == -1:
		AudioServer.add_bus()
		AudioServer.set_bus_name(AudioServer.bus_count - 1, "SFX")
		AudioServer.set_bus_volume_db(AudioServer.bus_count - 1, -10.0)

func _auto_switch_bgm() -> void:
	var cs := get_tree().current_scene
	if cs == null:
		return
	var idx: int = _level_music.get(cs.name, -1)
	if idx == _current_track:
		return
	_fade_to_track(idx)

func _fade_to_track(idx: int) -> void:
	_current_track = idx
	var from_p := _bgm_a if _active_bgm == 0 else _bgm_b
	var to_p := _bgm_b if _active_bgm == 0 else _bgm_a
	_active_bgm = 1 - _active_bgm
	if _crossfade and _crossfade.is_valid():
		_crossfade.kill()
	if idx < 0 or idx >= _tracks.size():
		_crossfade = create_tween()
		_crossfade.tween_property(from_p, "volume_db", -40.0, 1.0)
		_crossfade.tween_callback(from_p.stop)
		return
	to_p.stream = _tracks[idx]
	to_p.volume_db = -40.0
	to_p.play()
	_crossfade = create_tween()
	_crossfade.tween_property(to_p, "volume_db", -12.0, 1.2)
	_crossfade.tween_property(from_p, "volume_db", -40.0, 1.2)
	_crossfade.tween_callback(from_p.stop)

func play_bgm(idx: int, fade: float = 1.2) -> void:
	if idx < 0 or idx >= _tracks.size():
		return
	_current_track = idx
	var from_p := _bgm_a if _active_bgm == 0 else _bgm_b
	var to_p := _bgm_b if _active_bgm == 0 else _bgm_a
	_active_bgm = 1 - _active_bgm
	if _crossfade and _crossfade.is_valid():
		_crossfade.kill()
	if to_p.stream == null or to_p.stream != _tracks[idx]:
		to_p.stream = _tracks[idx]
		to_p.volume_db = -40.0
	to_p.play()
	_crossfade = create_tween()
	_crossfade.set_trans(Tween.TRANS_SINE)
	_crossfade.set_ease(Tween.EASE_IN_OUT)
	_crossfade.tween_property(to_p, "volume_db", -12.0, fade)
	_crossfade.tween_property(from_p, "volume_db", -40.0, fade)
	_crossfade.tween_callback(from_p.stop)

func _play_sfx(stream: AudioStream, volume_db: float, pitch: float = 1.0) -> void:
	var p := _sfx_pool[_sfx_index]
	_sfx_index = (_sfx_index + 1) % SFX_POOL_SIZE
	p.stream = stream
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.play()

func play_gunshot() -> void:
	_play_sfx(SFX_GUNSHOT, -6.0, randf_range(0.95, 1.06))

func play_enemy_shot() -> void:
	_play_sfx(SFX_GUNSHOT, -14.0, randf_range(0.9, 1.0))

func play_reload() -> void:
	_play_sfx(SFX_RELOAD, -8.0)

func play_footstep() -> void:
	_play_sfx(SFX_FOOTSTEP, -16.0, randf_range(0.9, 1.1))

func play_victory() -> void:
	_play_sfx(SFX_VICTORY, -6.0)
	_play_sfx(SFX_VICTORY, -12.0)

func play_defeat() -> void:
	_play_sfx(SFX_DEFEAT, -8.0)

func play_ui_click() -> void:
	_play_sfx(SFX_UI_CLICK, -6.0, randf_range(0.95, 1.05))