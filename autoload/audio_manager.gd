extends Node
## Bus routing and a one-shot SFX helper. Decides HOW sounds play, never WHEN.
##
## Every sound in the game is synthesised here at startup from sines and noise, so the
## build ships no audio files and nothing needs a licence. Generation takes well under a
## second and happens behind the splash screen.

const RATE := 22050
const SFX_POOL_SIZE := 10

var _library: Dictionary = {}
var _sfx_players: Array[AudioStreamPlayer] = []
var _music: AudioStreamPlayer
var _ambience: AudioStreamPlayer
var _current_music: String = ""
var _music_tween: Tween
var _generated: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in SFX_POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_sfx_players.append(p)
	_music = AudioStreamPlayer.new()
	_music.bus = "Music"
	add_child(_music)
	_ambience = AudioStreamPlayer.new()
	_ambience.bus = "Music"
	add_child(_ambience)
	_generate_library()


# --- Public API -----------------------------------------------------------------

func play_sfx(sfx_name: String, volume_db: float = 0.0, pitch_variation: float = 0.0) -> void:
	var stream: AudioStreamWAV = _library.get(sfx_name)
	if stream == null:
		return
	var player := _free_player()
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = 1.0 + randf_range(-pitch_variation, pitch_variation)
	player.play()


## Positional one-shot. Used so you can hear another racer shift gravity across a cavern.
func play_sfx_3d(sfx_name: String, position: Vector3, volume_db: float = 0.0) -> void:
	var stream: AudioStreamWAV = _library.get(sfx_name)
	if stream == null:
		return
	var scene := get_tree().current_scene
	if scene == null:
		return
	var player := AudioStreamPlayer3D.new()
	player.bus = "SFX"
	player.stream = stream
	player.volume_db = volume_db
	player.unit_size = 6.0
	player.max_distance = 60.0
	scene.add_child(player)
	player.global_position = position
	player.finished.connect(player.queue_free)
	player.play()


## Raw access for nodes that loop their own positional sound (wind, fire).
func get_stream(stream_name: String) -> AudioStreamWAV:
	return _library.get(stream_name)


func play_music(track: String, volume_db: float = -6.0) -> void:
	if _current_music == track and _music.playing:
		return
	_current_music = track
	# A fade-out still running from stop_music would otherwise stop this new track.
	if _music_tween != null and _music_tween.is_valid():
		_music_tween.kill()
	_music.stream = _library.get(track)
	_music.volume_db = volume_db
	_music.play()


func stop_music() -> void:
	_current_music = ""
	if _music_tween != null and _music_tween.is_valid():
		_music_tween.kill()
	_music_tween = create_tween()
	_music_tween.tween_property(_music, "volume_db", -40.0, 0.5)
	_music_tween.tween_callback(_music.stop)


func play_ambience() -> void:
	if _ambience.playing:
		return
	_ambience.stream = _library.get("ambience")
	_ambience.volume_db = -10.0
	_ambience.play()


func stop_ambience() -> void:
	_ambience.stop()


func _free_player() -> AudioStreamPlayer:
	for p: AudioStreamPlayer in _sfx_players:
		if not p.playing:
			return p
	return _sfx_players[randi() % _sfx_players.size()]


# --- Synthesis ------------------------------------------------------------------

func _generate_library() -> void:
	if _generated:
		return
	_generated = true

	_library["ui_hover"] = _wav(_tone(0.05, 900.0, 900.0, 0.22))
	_library["ui_click"] = _wav(_tone(0.09, 640.0, 420.0, 0.4))
	_library["ui_back"] = _wav(_tone(0.09, 420.0, 300.0, 0.35))
	_library["notify"] = _wav(_mix([_tone(0.08, 740.0, 740.0, 0.3), _tone(0.1, 1110.0, 1110.0, 0.12)]))
	_library["countdown"] = _wav(_tone(0.14, 587.0, 587.0, 0.5))
	_library["go"] = _wav(_mix([_tone(0.35, 880.0, 880.0, 0.45), _tone(0.35, 1320.0, 1320.0, 0.25)]))

	# The gravity shift is the most important sound in the game: a rising sweep with a
	# breath of noise underneath, then a firm low thud when the new floor arrives.
	_library["shift"] = _wav(_mix([
		_tone(0.42, 150.0, 640.0, 0.55, 0.01, 1.2),
		_tone(0.42, 300.0, 1280.0, 0.18, 0.01, 1.6),
		_noise(0.38, 0.28, 0.06, 1.4, 5),
	]))
	_library["shift_done"] = _wav(_mix([_tone(0.2, 90.0, 60.0, 0.7, 0.002, 2.5), _noise(0.05, 0.2, 0.001, 3.0, 2)]))
	_library["racer_shift"] = _wav(_tone(0.22, 420.0, 840.0, 0.35, 0.01, 1.5))
	_library["denied"] = _wav(_mix([_square(0.1, 190.0, 0.3), _shift(_square(0.1, 170.0, 0.3), 0.13)]))

	_library["damage"] = _wav(_mix([_noise(0.22, 0.5, 0.002, 2.2, 3), _tone(0.25, 150.0, 85.0, 0.5, 0.002, 2.0)]))
	_library["footstep"] = _wav(_noise(0.055, 0.32, 0.002, 3.0, 8))
	_library["jump"] = _wav(_tone(0.11, 260.0, 440.0, 0.28))
	_library["land"] = _wav(_mix([_tone(0.13, 120.0, 70.0, 0.45, 0.002, 2.2), _noise(0.06, 0.15, 0.001, 3.0, 6)]))

	_library["box_open"] = _wav(_mix([
		_notes([523.0, 659.0, 784.0], 0.12, 0.35),
		_shift(_noise(0.12, 0.12, 0.01, 2.0, 4), 0.0),
	]))
	_library["heart"] = _wav(_notes([659.0, 988.0], 0.16, 0.4))
	_library["move_refill"] = _wav(_notes([440.0, 660.0, 880.0], 0.1, 0.4))
	_library["speed"] = _wav(_tone(0.32, 300.0, 1400.0, 0.35, 0.01, 1.0))
	_library["shield"] = _wav(_mix([_tone(0.45, 500.0, 500.0, 0.3, 0.02, 1.0), _tone(0.45, 750.0, 752.0, 0.2, 0.02, 1.0)]))
	_library["penalty"] = _wav(_vibrato(0.55, 380.0, 170.0, 0.4, 9.0))
	_library["clue"] = _wav(_mix([_tremolo(1.0, 660.0, 0.3, 6.0), _tremolo(1.0, 990.0, 0.18, 6.0), _tone(1.0, 1320.0, 1320.0, 0.06, 0.2, 1.0)]))
	_library["finish"] = _wav(_mix([_notes([523.0, 659.0, 784.0, 1046.0], 0.17, 0.4), _shift(_tone(0.7, 1046.0, 1046.0, 0.3, 0.02, 1.0), 0.68)]))
	_library["eliminated"] = _wav(_mix([_tone(1.0, 320.0, 70.0, 0.45, 0.01, 1.0), _noise(0.6, 0.15, 0.05, 1.5, 4)]))
	_library["record"] = _wav(_notes([784.0, 988.0, 1175.0, 1568.0], 0.13, 0.4))

	_library["crumble"] = _wav(_mix([_noise(0.7, 0.45, 0.01, 1.2, 12), _tone(0.5, 80.0, 45.0, 0.4, 0.01, 1.5)]))
	_library["piston"] = _wav(_mix([_tone(0.35, 70.0, 38.0, 0.9, 0.001, 2.2), _noise(0.25, 0.5, 0.001, 2.5, 6)]))
	_library["spider"] = _wav(_noise(0.45, 0.35, 0.02, 0.8, 1))
	_library["whoosh"] = _wav(_noise(0.3, 0.3, 0.08, 1.2, 3))
	_library["heartbeat"] = _wav(_mix([_tone(0.12, 60.0, 45.0, 0.9, 0.002, 2.0),
		_shift(_tone(0.1, 55.0, 42.0, 0.7, 0.002, 2.0), 0.2)]))
	_library["second_chance"] = _wav(_mix([_notes([392.0, 523.0, 784.0], 0.14, 0.4),
		_shift(_tremolo(0.8, 1046.0, 0.2, 10.0), 0.3)]))
	_library["emote"] = _wav(_notes([880.0, 1175.0], 0.08, 0.3))
	_library["gate"] = _wav(_mix([_tone(0.6, 110.0, 70.0, 0.6, 0.01, 1.2), _noise(0.5, 0.25, 0.02, 1.4, 10)]))
	_library["wind"] = _wav(_wind_loop(), true)
	_library["fire_loop"] = _wav(_fire_loop(), true)
	_library["music_race"] = _wav(_race_music(), true)

	_library["music_menu"] = _wav(_menu_music(), true)
	_library["ambience"] = _wav(_cave_ambience(), true)


## A slow four-chord loop with a plucked arpeggio. Eight seconds, seamless.
func _menu_music() -> PackedFloat32Array:
	var chords := [
		[220.0, 261.63, 329.63],   # A minor
		[174.61, 220.0, 261.63],   # F
		[196.0, 246.94, 293.66],   # G
		[164.81, 196.0, 246.94],   # E minor
	]
	var chord_len := 2.0
	var total := chord_len * chords.size()
	var frames := int(total * RATE)
	var out := PackedFloat32Array()
	out.resize(frames)
	var arp_len := 0.25
	for i in frames:
		var t := float(i) / RATE
		var ci := int(t / chord_len) % chords.size()
		var chord: Array = chords[ci]
		var local := fmod(t, chord_len)
		var v := 0.0
		# Pad: three detuned sines with a gentle swell per chord.
		var swell := sin(PI * local / chord_len)
		for f: float in chord:
			v += sin(TAU * f * 0.5 * t) * 0.10 * (0.6 + 0.4 * swell)
			v += sin(TAU * f * 0.503 * t) * 0.05 * swell
		# Arpeggio: a decaying pluck every quarter second cycling the chord tones.
		var step := int(local / arp_len)
		var since := fmod(local, arp_len)
		var note: float = chord[step % 3] * (2.0 if step % 4 == 3 else 1.0)
		v += sin(TAU * note * 2.0 * t) * 0.14 * exp(-since * 9.0)
		# Soft bass pulse on the downbeat.
		v += sin(TAU * chord[0] * 0.25 * t) * 0.12 * exp(-local * 1.6)
		out[i] = v
	return _fade_edges(out, 0.05)


## Hollow gusting noise. Four seconds, seamless.
func _wind_loop() -> PackedFloat32Array:
	var frames := int(4.0 * RATE)
	var out := PackedFloat32Array()
	out.resize(frames)
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var lp := 0.0
	for i in frames:
		var t := float(i) / RATE
		lp = lerpf(lp, rng.randf() * 2.0 - 1.0, 0.06)
		out[i] = lp * 0.9 * (0.55 + 0.45 * sin(TAU * t / 4.0 * 2.0))
	return _fade_edges(out, 0.03)


## Crackle: sparse sharp pops over a soft roar. Three seconds, seamless.
func _fire_loop() -> PackedFloat32Array:
	var frames := int(3.0 * RATE)
	var out := PackedFloat32Array()
	out.resize(frames)
	var rng := RandomNumberGenerator.new()
	rng.seed = 555
	var lp := 0.0
	var pop := 0.0
	for i in frames:
		lp = lerpf(lp, rng.randf() * 2.0 - 1.0, 0.03)
		if rng.randf() < 0.0009:
			pop = 1.0
		pop *= 0.992
		out[i] = lp * 0.5 + (rng.randf() * 2.0 - 1.0) * pop * 0.5
	return _fade_edges(out, 0.02)


## A low pulse under the race: two alternating bass notes and a ticking hat. Eight
## seconds, seamless. Quiet by design -- the ambience and the gravity shift lead.
func _race_music() -> PackedFloat32Array:
	var frames := int(8.0 * RATE)
	var out := PackedFloat32Array()
	out.resize(frames)
	var rng := RandomNumberGenerator.new()
	rng.seed = 31
	var beat := 0.5
	for i in frames:
		var t := float(i) / RATE
		var bar := int(t / 2.0) % 4
		var root: float = [55.0, 55.0, 49.0, 61.74][bar]
		var since := fmod(t, beat)
		var v := sin(TAU * root * t) * 0.22 * exp(-since * 5.0)
		v += sin(TAU * root * 2.0 * t) * 0.05
		var half := fmod(t + beat * 0.5, beat)
		v += (rng.randf() * 2.0 - 1.0) * 0.05 * exp(-half * 60.0)
		v += sin(TAU * root * 3.0 * t) * 0.03 * (0.5 + 0.5 * sin(TAU * t / 8.0))
		out[i] = v
	return _fade_edges(out, 0.02)


## Brown noise draught plus a low hum, drifting slowly. Six seconds, seamless.
func _cave_ambience() -> PackedFloat32Array:
	var frames := int(6.0 * RATE)
	var out := PackedFloat32Array()
	out.resize(frames)
	var brown := 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	for i in frames:
		var t := float(i) / RATE
		brown += (rng.randf() * 2.0 - 1.0) * 0.02
		brown *= 0.995
		var drift := 0.6 + 0.4 * sin(TAU * t / 6.0)
		var hum := sin(TAU * 55.0 * t) * 0.07 + sin(TAU * 110.5 * t) * 0.03
		out[i] = brown * 1.8 * drift + hum * (0.5 + 0.5 * drift)
	return _fade_edges(out, 0.02)


# --- Primitive builders ---------------------------------------------------------

## Sine sweep from f0 to f1 with a short attack and a power-curve decay.
func _tone(duration: float, f0: float, f1: float, gain: float, attack: float = 0.005,
		decay_pow: float = 1.8) -> PackedFloat32Array:
	var frames := int(duration * RATE)
	var out := PackedFloat32Array()
	out.resize(frames)
	var phase := 0.0
	for i in frames:
		var t := float(i) / RATE
		var u := t / duration
		var f := lerpf(f0, f1, u)
		phase += TAU * f / RATE
		var env := minf(1.0, t / maxf(attack, 0.0001)) * pow(1.0 - u, decay_pow)
		out[i] = sin(phase) * gain * env
	return out


func _square(duration: float, f: float, gain: float) -> PackedFloat32Array:
	var frames := int(duration * RATE)
	var out := PackedFloat32Array()
	out.resize(frames)
	for i in frames:
		var t := float(i) / RATE
		var s := 1.0 if fmod(t * f, 1.0) < 0.5 else -1.0
		out[i] = s * gain * (1.0 - t / duration)
	return out


## Noise burst. `smooth` averages neighbouring samples, which acts as a cheap low-pass.
func _noise(duration: float, gain: float, attack: float, decay_pow: float,
		smooth: int) -> PackedFloat32Array:
	var frames := int(duration * RATE)
	var raw := PackedFloat32Array()
	raw.resize(frames)
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	for i in frames:
		raw[i] = rng.randf() * 2.0 - 1.0
	var out := PackedFloat32Array()
	out.resize(frames)
	for i in frames:
		var acc := 0.0
		for k in smooth:
			acc += raw[maxi(0, i - k)]
		var t := float(i) / RATE
		var env := minf(1.0, t / maxf(attack, 0.0001)) * pow(1.0 - t / duration, decay_pow)
		out[i] = acc / float(smooth) * gain * env
	return out


func _vibrato(duration: float, f0: float, f1: float, gain: float, rate: float) -> PackedFloat32Array:
	var frames := int(duration * RATE)
	var out := PackedFloat32Array()
	out.resize(frames)
	var phase := 0.0
	for i in frames:
		var t := float(i) / RATE
		var u := t / duration
		var f := lerpf(f0, f1, u) * (1.0 + 0.04 * sin(TAU * rate * t))
		phase += TAU * f / RATE
		out[i] = sin(phase) * gain * (1.0 - u)
	return out


func _tremolo(duration: float, f: float, gain: float, rate: float) -> PackedFloat32Array:
	var frames := int(duration * RATE)
	var out := PackedFloat32Array()
	out.resize(frames)
	for i in frames:
		var t := float(i) / RATE
		var u := t / duration
		var env := sin(PI * u) * (0.65 + 0.35 * sin(TAU * rate * t))
		out[i] = sin(TAU * f * t) * gain * env
	return out


## Sequential notes, each a short decaying sine.
func _notes(freqs: Array, note_len: float, gain: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for f: float in freqs:
		out.append_array(_tone(note_len, f, f, gain, 0.004, 1.2))
	return out


func _shift(buf: PackedFloat32Array, seconds: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(int(seconds * RATE))
	out.fill(0.0)
	out.append_array(buf)
	return out


func _mix(layers: Array) -> PackedFloat32Array:
	var length := 0
	for l: PackedFloat32Array in layers:
		length = maxi(length, l.size())
	var out := PackedFloat32Array()
	out.resize(length)
	out.fill(0.0)
	for l: PackedFloat32Array in layers:
		for i in l.size():
			out[i] += l[i]
	return out


func _fade_edges(buf: PackedFloat32Array, seconds: float) -> PackedFloat32Array:
	var n := int(seconds * RATE)
	for i in n:
		var g := float(i) / float(n)
		buf[i] *= g
		buf[buf.size() - 1 - i] *= g
	return buf


func _wav(samples: PackedFloat32Array, loop: bool = false) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		var v := int(clampf(samples[i], -1.0, 1.0) * 32767.0)
		bytes.encode_s16(i * 2, v)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = bytes
	if loop:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = samples.size()
	return wav
