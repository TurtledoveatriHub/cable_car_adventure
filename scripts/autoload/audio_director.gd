extends Node
## 程序化音频：无需外部音频素材即可获得点击、碰撞、收客、成功、失败和循环 BGM。
## 生成的 AudioStreamWAV 在桌面端与 Web / 微信小游戏导出中都兼容。
## 音乐与音效开关来自 SaveManager 设置，不直接读写文件。

const SAMPLE_RATE := 22050

var music_enabled: bool = true
var sfx_enabled: bool = true

var _music_player: AudioStreamPlayer
var _music_player_b: AudioStreamPlayer
var _active_music_player: AudioStreamPlayer
var _music_tween: Tween
var _current_background: String = "paradise"
var _sfx_players: Array[AudioStreamPlayer] = []
var _sfx_index: int = 0
var _streams: Dictionary = {}
var _music_start_scheduled: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# 无头测试 / CI 不需要音频资源；跳过合成，避免音频服务器在进程退出时报告资源残留。
	if DisplayServer.get_name().to_lower() == "headless":
		set_process(false)
		return
	# 音乐循环按需生成：启动时只生成当前背景，避免微信首屏一次合成 5 首 BGM。
	_streams["click"] = _build_click()
	_streams["move"] = _build_move()
	_streams["pickup"] = _build_pickup()
	_streams["hit"] = _build_hit()
	_streams["success"] = _build_success()
	_streams["fail"] = _build_fail()
	_streams["countdown"] = _build_countdown(false)
	_streams["go"] = _build_countdown(true)

	_music_player = AudioStreamPlayer.new()
	_music_player.name = "MusicPlayerA"
	_music_player.bus = "Music"
	_music_player.volume_db = -3.0
	add_child(_music_player)
	_music_player_b = AudioStreamPlayer.new()
	_music_player_b.name = "MusicPlayerB"
	_music_player_b.bus = "Music"
	_music_player_b.volume_db = -60.0
	add_child(_music_player_b)
	_active_music_player = _music_player

	for index in 10:
		var player := AudioStreamPlayer.new()
		player.name = "SfxPlayer%d" % index
		player.bus = "SFX"
		player.volume_db = -2.0
		add_child(player)
		_sfx_players.append(player)

	# 首次 BGM 合成延后到首屏显示后，避免把音乐波形生成算进“引擎初始化”黑屏。
	_schedule_music_start()
	_apply_saved_settings_deferred()


func _notification(what: int) -> void:
	# 某些 Windows 音频驱动在播放中直接销毁对象会崩溃，关闭窗口前先停止全部声音。
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		stop_all()


func _exit_tree() -> void:
	stop_all()


func _apply_saved_settings_deferred() -> void:
	await get_tree().process_frame
	if is_instance_valid(SaveManager):
		if not SaveManager.data_changed.is_connected(_apply_saved_settings):
			SaveManager.data_changed.connect(_apply_saved_settings)
	_apply_saved_settings()


func _apply_saved_settings() -> void:
	music_enabled = bool(SaveManager.get_setting("music_enabled", true))
	sfx_enabled = bool(SaveManager.get_setting("sfx_enabled", true))
	if music_enabled:
		_schedule_music_start()
	else:
		if is_instance_valid(_music_player):
			_music_player.stop()
		if is_instance_valid(_music_player_b):
			_music_player_b.stop()
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Music"), not music_enabled)
	AudioServer.set_bus_mute(AudioServer.get_bus_index("SFX"), not sfx_enabled)


func _schedule_music_start() -> void:
	if _music_start_scheduled:
		return
	_music_start_scheduled = true
	await get_tree().create_timer(0.30, true, false, true).timeout
	_music_start_scheduled = false
	_start_music_if_allowed()


func _start_music_if_allowed() -> void:
	if not music_enabled:
		return
	if _active_music_player == null:
		_active_music_player = _music_player
	if _active_music_player == null:
		return
	if _active_music_player.stream == null:
		var stream := _music_stream(_current_background)
		if stream == null:
			return
		_active_music_player.stream = stream
	if not _active_music_player.playing:
		_active_music_player.volume_db = -3.0
		_active_music_player.play()


## 按背景生成/复用音乐；首次进入某个背景时才支付合成成本。
func _music_stream(background_id: String) -> AudioStreamWAV:
	var key := "music_" + background_id
	if not _streams.has(key):
		var safe_id := background_id if background_id in ["paradise", "forest", "snow", "clouds", "dream"] else "paradise"
		_streams[key] = _build_music_loop(safe_id)
	return _streams[key] as AudioStreamWAV


## 切换关卡/工坊背景 BGM；两路播放器交叉淡入淡出，避免硬切。
func set_background_music(background_id: String) -> void:
	var target := background_id if background_id in ["paradise", "forest", "snow", "clouds", "dream"] else "paradise"
	if target == _current_background:
		return
	_current_background = target
	if _active_music_player == null:
		return
	var stream := _music_stream(target)
	if stream == null:
		return
	if not music_enabled:
		_active_music_player.stream = stream
		return
	if _music_tween != null and _music_tween.is_valid():
		_music_tween.kill()
	var current := _active_music_player
	var next := _music_player_b if current == _music_player else _music_player
	next.stop()
	next.stream = stream
	next.volume_db = -60.0
	next.play()
	_music_tween = create_tween().set_parallel(true)
	_music_tween.tween_property(current, "volume_db", -60.0, 0.8)
	_music_tween.tween_property(next, "volume_db", -3.0, 0.8)
	_music_tween.chain().tween_callback(current.stop)
	_active_music_player = next


func set_music_enabled(enabled: bool) -> void:
	SaveManager.set_setting("music_enabled", enabled)
	_apply_saved_settings()


func set_sfx_enabled(enabled: bool) -> void:
	SaveManager.set_setting("sfx_enabled", enabled)
	_apply_saved_settings()


func toggle_music() -> void:
	set_music_enabled(not music_enabled)


func toggle_sfx() -> void:
	set_sfx_enabled(not sfx_enabled)


func play_click() -> void:
	_play("click", -8.0, randf_range(0.97, 1.03))


func play_move() -> void:
	_play("move", -14.0, randf_range(0.95, 1.05))


func play_pickup() -> void:
	_play("pickup", -7.5, randf_range(0.98, 1.04))


func play_hit() -> void:
	_play("hit", -4.0, randf_range(0.94, 1.02))


func play_success() -> void:
	_play("success", -5.0, 1.0)


func play_fail() -> void:
	_play("fail", -6.0, 1.0)


func play_countdown(is_final: bool) -> void:
	_play("go" if is_final else "countdown", -8.0, 1.0)


## 在退出 / 切后台前停止所有播放，避免个别音频驱动在对象释放时崩溃。
func stop_all() -> void:
	if is_instance_valid(_music_player):
		_music_player.stop()
		_music_player.stream = null
	if is_instance_valid(_music_player_b):
		_music_player_b.stop()
		_music_player_b.stream = null
	for player in _sfx_players:
		if is_instance_valid(player):
			player.stop()
			player.stream = null


## 测试 / 退出清理：停止播放并释放所有程序化音频资源。
func shutdown() -> void:
	stop_all()
	_streams.clear()
	if is_instance_valid(_music_player):
		_music_player.queue_free()
		_music_player = null
	if is_instance_valid(_music_player_b):
		_music_player_b.queue_free()
		_music_player_b = null
	_active_music_player = null
	for player in _sfx_players:
		if is_instance_valid(player):
			player.queue_free()
	_sfx_players.clear()


func _play(stream_key: String, volume_db: float, pitch_scale: float) -> void:
	if not sfx_enabled or not _streams.has(stream_key):
		return
	if _sfx_players.is_empty():
		return
	var player := _sfx_players[_sfx_index]
	_sfx_index = (_sfx_index + 1) % _sfx_players.size()
	player.stop()
	player.stream = _streams[stream_key]
	player.volume_db = volume_db
	player.pitch_scale = pitch_scale
	player.play()


func _make_wav(samples: PackedFloat32Array, loop: bool = false) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for index in samples.size():
		var sample := clampf(samples[index], -1.0, 1.0)
		bytes.encode_s16(index * 2, int(round(sample * 32767.0)))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SAMPLE_RATE
	wav.stereo = false
	wav.data = bytes
	if loop:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = samples.size()
	return wav


func _make_buffer(seconds: float) -> PackedFloat32Array:
	var buffer := PackedFloat32Array()
	buffer.resize(int(seconds * SAMPLE_RATE))
	buffer.fill(0.0)
	return buffer


func _add_tone(
	buffer: PackedFloat32Array,
	start_seconds: float,
	duration: float,
	frequency: float,
	amplitude: float,
	waveform: String = "sine",
	attack: float = 0.01,
	release: float = 0.08
) -> void:
	var start := int(start_seconds * SAMPLE_RATE)
	var count := int(duration * SAMPLE_RATE)
	if start >= buffer.size() or count <= 0 or frequency <= 0.0:
		return
	var attack_samples := maxi(1, int(attack * SAMPLE_RATE))
	var release_samples := maxi(1, int(release * SAMPLE_RATE))
	for offset in count:
		var index := start + offset
		if index < 0 or index >= buffer.size():
			continue
		var t := float(offset) / SAMPLE_RATE
		var phase := fmod(t * frequency, 1.0)
		var wave := 0.0
		match waveform:
			"square":
				wave = 1.0 if phase < 0.5 else -1.0
			"saw":
				wave = phase * 2.0 - 1.0
			"triangle":
				wave = 4.0 * absf(phase - 0.5) - 1.0
			"noise":
				wave = randf_range(-1.0, 1.0)
			_:
				wave = sin(phase * TAU)
		var envelope := 1.0
		if offset < attack_samples:
			envelope = float(offset) / attack_samples
		elif offset > count - release_samples:
			envelope = maxf(0.0, float(count - offset) / release_samples)
		buffer[index] += wave * amplitude * envelope * envelope


func _add_kick(buffer: PackedFloat32Array, start_seconds: float, amplitude: float = 0.12) -> void:
	var duration := 0.12
	var start := int(start_seconds * SAMPLE_RATE)
	var count := int(duration * SAMPLE_RATE)
	for offset in count:
		var index := start + offset
		if index < 0 or index >= buffer.size():
			continue
		var t := float(offset) / SAMPLE_RATE
		var env := exp(-t * 22.0)
		var freq := lerpf(120.0, 48.0, clampf(t / duration, 0.0, 1.0))
		buffer[index] += sin(TAU * freq * t) * amplitude * env


func _add_hat(buffer: PackedFloat32Array, start_seconds: float, amplitude: float = 0.03) -> void:
	var duration := 0.045
	var start := int(start_seconds * SAMPLE_RATE)
	var count := int(duration * SAMPLE_RATE)
	for offset in count:
		var index := start + offset
		if index < 0 or index >= buffer.size():
			continue
		var env := exp(-float(offset) / (SAMPLE_RATE * 0.01))
		buffer[index] += randf_range(-1.0, 1.0) * amplitude * env


func _build_music_loop(background_id: String) -> AudioStreamWAV:
	# 五个背景各自一套 16bit 芯片音循环；共享和声骨架，但速度、音色、配器和律动不同。
	var configs := {
		"paradise": {
			"bpm": 138.0, "transpose": 0, "lead_wave": "square", "lead_amp": 0.082,
			"pad_wave": "triangle", "pad_amp": 0.052, "arp_wave": "sine", "arp_amp": 0.024,
			"kick": true, "hat": true, "sparkle": false,
		},
		"forest": {
			"bpm": 108.0, "transpose": -2, "lead_wave": "triangle", "lead_amp": 0.074,
			"pad_wave": "sine", "pad_amp": 0.046, "arp_wave": "triangle", "arp_amp": 0.020,
			"kick": true, "hat": true, "sparkle": false,
		},
		"snow": {
			"bpm": 126.0, "transpose": 5, "lead_wave": "sine", "lead_amp": 0.060,
			"pad_wave": "triangle", "pad_amp": 0.034, "arp_wave": "sine", "arp_amp": 0.028,
			"kick": false, "hat": true, "sparkle": true,
		},
		"clouds": {
			"bpm": 92.0, "transpose": 7, "lead_wave": "sine", "lead_amp": 0.052,
			"pad_wave": "triangle", "pad_amp": 0.050, "arp_wave": "sine", "arp_amp": 0.016,
			"kick": false, "hat": false, "sparkle": false,
		},
		"dream": {
			"bpm": 78.0, "transpose": -5, "lead_wave": "triangle", "lead_amp": 0.050,
			"pad_wave": "sine", "pad_amp": 0.044, "arp_wave": "sine", "arp_amp": 0.014,
			"kick": false, "hat": false, "sparkle": false,
		},
	}
	var config: Dictionary = configs.get(background_id, configs["paradise"])
	var step_seconds := 60.0 / float(config["bpm"]) / 2.0
	var total_steps := 32
	var duration := step_seconds * total_steps
	var buffer := _make_buffer(duration)
	var transpose := int(config["transpose"])
	var lead_notes := [
		72, 76, 79, 76, 81, 79, 76, 72,
		69, 72, 76, 72, 77, 76, 72, 69,
		65, 69, 72, 69, 74, 72, 69, 65,
		67, 71, 74, 71, 76, 74, 71, 67,
	]
	var rests := [1, 0, 0, 1, 0, 0, 1, 0, 1, 0, 0, 1, 0, 0, 1, 0, 1, 0, 0, 1, 0, 0, 1, 0, 1, 0, 0, 1, 0, 0, 1, 0]
	var chords := [
		[48, 52, 55], [48, 52, 55], [45, 48, 52], [45, 48, 52],
		[41, 45, 48], [41, 45, 48], [43, 47, 50], [43, 47, 50],
	]
	var lead_wave := str(config["lead_wave"])
	var lead_amp := float(config["lead_amp"])
	var pad_wave := str(config["pad_wave"])
	var pad_amp := float(config["pad_amp"])
	var arp_wave := str(config["arp_wave"])
	var arp_amp := float(config["arp_amp"])
	var has_kick := bool(config["kick"])
	var has_hat := bool(config["hat"])
	for step in total_steps:
		var step_time := step * step_seconds
		var chord: Array = chords[int(step / 4.0) % chords.size()]
		var lead_midi: int = int(lead_notes[step]) + transpose
		if rests[step] == 0:
			_add_tone(buffer, step_time, step_seconds * 0.84, _midi_to_hz(lead_midi), lead_amp, lead_wave, 0.006, 0.07)
			if background_id == "dream":
				_add_tone(buffer, step_time, step_seconds * 0.84, _midi_to_hz(lead_midi) * 1.006, lead_amp * 0.55, "sine", 0.006, 0.09)
		if step % 4 == 0:
			_add_tone(buffer, step_time, step_seconds * 3.5, _midi_to_hz(int(chord[0]) + transpose - 12), pad_amp, pad_wave, 0.02, 0.18)
			_add_tone(buffer, step_time, step_seconds * 3.2, _midi_to_hz(int(chord[0]) + transpose), pad_amp * 0.55, pad_wave, 0.02, 0.16)
		if step % 2 == 0:
			var chord_note: int = int(chord[int(step / 2.0) % chord.size()]) + transpose + 12
			if background_id == "snow":
				chord_note += 12
			_add_tone(buffer, step_time, step_seconds * 1.4, _midi_to_hz(chord_note), arp_amp, arp_wave, 0.005, 0.10)
		if background_id == "snow" and step % 2 == 1:
			_add_tone(buffer, step_time, step_seconds * 0.9, _midi_to_hz(int(chord[0]) + transpose + 24), 0.014, "sine", 0.004, 0.08)
		if has_kick and step % (2 if background_id == "paradise" else 4) == 0:
			_add_kick(buffer, step_time, 0.09 if step % 8 == 0 else 0.054)
		if has_hat and step % 2 == 1:
			_add_hat(buffer, step_time, 0.016)

	var fade := int(0.012 * SAMPLE_RATE)
	for index in fade:
		var gain := float(index) / fade
		buffer[index] *= gain
		buffer[buffer.size() - 1 - index] *= gain
	return _make_wav(buffer, true)


func _midi_to_hz(midi: int) -> float:
	return 440.0 * pow(2.0, (float(midi) - 69.0) / 12.0)


func _build_click() -> AudioStreamWAV:
	var buffer := _make_buffer(0.075)
	var sample_count := int(0.075 * SAMPLE_RATE)
	for index in sample_count:
		var t := float(index) / SAMPLE_RATE
		var env := exp(-t * 80.0)
		var freq := lerpf(960.0, 660.0, clampf(t / 0.075, 0.0, 1.0))
		buffer[index] = sin(TAU * freq * t) * 0.26 * env
	return _make_wav(buffer)


func _build_move() -> AudioStreamWAV:
	var buffer := _make_buffer(0.055)
	var sample_count := int(0.055 * SAMPLE_RATE)
	for index in sample_count:
		var t := float(index) / SAMPLE_RATE
		var env := exp(-t * 60.0)
		buffer[index] = sin(TAU * 520.0 * t) * 0.12 * env
	return _make_wav(buffer)


func _build_pickup() -> AudioStreamWAV:
	var buffer := _make_buffer(0.42)
	var notes := [523.25, 659.25, 783.99, 1046.5]
	for index in notes.size():
		_add_tone(buffer, index * 0.065, 0.23, notes[index], 0.17, "sine", 0.005, 0.16)
		_add_tone(buffer, index * 0.065, 0.18, notes[index] * 2.0, 0.04, "triangle", 0.005, 0.12)
	return _make_wav(buffer)


func _build_hit() -> AudioStreamWAV:
	var buffer := _make_buffer(0.4)
	var sample_count := int(0.4 * SAMPLE_RATE)
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	for index in sample_count:
		var t := float(index) / SAMPLE_RATE
		var env := exp(-t * 14.0)
		var noise := rng.randf_range(-1.0, 1.0)
		var thump := sin(TAU * lerpf(150.0, 55.0, clampf(t / 0.4, 0.0, 1.0)) * t)
		buffer[index] = (noise * 0.1 + thump * 0.34) * env
	_add_tone(buffer, 0.02, 0.18, 330.0, 0.12, "square", 0.005, 0.16)
	return _make_wav(buffer)


func _build_success() -> AudioStreamWAV:
	var buffer := _make_buffer(1.35)
	var notes := [523.25, 659.25, 783.99, 1046.5, 1318.5]
	for index in notes.size():
		_add_tone(buffer, index * 0.12, 0.34, notes[index], 0.15, "square", 0.006, 0.2)
		_add_tone(buffer, index * 0.12, 0.3, notes[index] * 0.5, 0.06, "triangle", 0.006, 0.2)
	_add_tone(buffer, 0.56, 0.7, 1567.98, 0.08, "sine", 0.01, 0.4)
	return _make_wav(buffer)


func _build_fail() -> AudioStreamWAV:
	var buffer := _make_buffer(1.05)
	var notes := [392.0, 349.23, 293.66, 246.94, 196.0]
	for index in notes.size():
		_add_tone(buffer, index * 0.14, 0.28, notes[index], 0.16, "saw", 0.006, 0.2)
	_add_tone(buffer, 0.7, 0.34, 98.0, 0.14, "triangle", 0.01, 0.25)
	return _make_wav(buffer)


func _build_countdown(is_final: bool) -> AudioStreamWAV:
	var duration := 0.32 if is_final else 0.14
	var buffer := _make_buffer(duration)
	var frequency := 1046.5 if is_final else 523.25
	var sample_count := int(duration * SAMPLE_RATE)
	for index in sample_count:
		var t := float(index) / SAMPLE_RATE
		var env := exp(-t * (5.5 if is_final else 18.0))
		buffer[index] = sin(TAU * frequency * t) * 0.18 * env
		if is_final:
			buffer[index] += sin(TAU * frequency * 1.5 * t) * 0.06 * env
	return _make_wav(buffer)
