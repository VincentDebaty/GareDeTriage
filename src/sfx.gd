extends Node
## Sons provisoires synthétisés au démarrage (aucun fichier audio).

const RATE := 22050

var _streams: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _next: int = 0


func _ready() -> void:
	# Chaque son est une suite de notes [fréquence en Hz, durée en s].
	_streams["pop"] = _make([[660.0, 0.10]], 0.5)
	_streams["wait"] = _make([[330.0, 0.10]], 0.4)
	_streams["nope"] = _make([[130.0, 0.18]], 0.5)
	_streams["whistle"] = _make([[880.0, 0.12], [1108.0, 0.30]], 0.3)
	_streams["win"] = _make([[523.0, 0.10], [659.0, 0.10], [784.0, 0.10], [1047.0, 0.35]], 0.4)
	_streams["lose"] = _make([[330.0, 0.18], [247.0, 0.18], [196.0, 0.40]], 0.4)
	for i: int in 6:
		var p: AudioStreamPlayer = AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)


func play(sound: String, pitch: float = 1.0) -> void:
	var p: AudioStreamPlayer = _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = _streams[sound]
	p.pitch_scale = pitch
	p.play()


func _make(notes: Array, volume: float) -> AudioStreamWAV:
	var total: int = 0
	for note: Array in notes:
		total += int(float(note[1]) * RATE)
	var data: PackedByteArray = PackedByteArray()
	data.resize(total * 2)
	var offset: int = 0
	var phase: float = 0.0
	for note: Array in notes:
		var n: int = int(float(note[1]) * RATE)
		for i: int in n:
			phase += TAU * float(note[0]) / RATE
			var envelope: float = minf(1.0, i / 60.0) * exp(-4.0 * i / n)
			var v: float = (sin(phase) * 0.8 + sin(phase * 2.0) * 0.2) * envelope * volume
			data.encode_s16(offset, int(clampf(v, -1.0, 1.0) * 32767.0))
			offset += 2
	var wav: AudioStreamWAV = AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = data
	return wav
