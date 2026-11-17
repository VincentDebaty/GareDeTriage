extends Node
## Sons synthétisés au démarrage (aucun fichier audio), avec des timbres d'instruments :
## lames de bois pour les wagons, carillon pour les récompenses, sifflet à vapeur pour les
## départs, choc de métal pour l'attelage.

const RATE := 32000

## Timbres : liste de partiels [rapport de fréquence, volume, vitesse d'extinction].
## Lame de bois (marimba) : la note, son double octave qui s'éteint vite, un éclat aigu.
const WOOD: Array = [[1.0, 1.0, 9.0], [4.0, 0.28, 22.0], [9.2, 0.07, 45.0]]
## Carillon : partiels non harmoniques, longue résonance.
const BELL: Array = [[1.0, 1.0, 5.0], [2.76, 0.45, 7.0], [5.4, 0.2, 10.0], [8.9, 0.08, 14.0]]
## Bois sourd et grave, pour les refus.
const THUD: Array = [[1.0, 1.0, 28.0], [2.1, 0.3, 40.0]]

var _streams: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _next: int = 0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 7
	var b: PackedFloat32Array

	# Wagon qui monte dans son train : lame de bois claire.
	b = _buffer(0.32)
	_tone(b, 0.0, 659.0, 0.32, 0.8, WOOD)
	_noise(b, 0.0, 0.012, 0.25, 0.5)
	_streams["pop"] = _wav(b)

	# Wagon qui part en attente : la même lame, plus grave et plus douce.
	b = _buffer(0.30)
	_tone(b, 0.0, 392.0, 0.30, 0.6, WOOD)
	_noise(b, 0.0, 0.012, 0.18, 0.7)
	_streams["wait"] = _wav(b)

	# Coup impossible : deux petits chocs de bois sourd.
	b = _buffer(0.24)
	_tone(b, 0.0, 147.0, 0.12, 0.9, THUD)
	_tone(b, 0.10, 131.0, 0.14, 0.8, THUD)
	_noise(b, 0.0, 0.02, 0.2, 0.85)
	_noise(b, 0.10, 0.02, 0.2, 0.85)
	_streams["nope"] = _wav(b)

	# Wagon mystère dévoilé : deux notes de carillon montantes.
	b = _buffer(0.45)
	_tone(b, 0.0, 784.0, 0.3, 0.4, BELL)
	_tone(b, 0.07, 1175.0, 0.38, 0.4, BELL)
	_streams["reveal"] = _wav(b)

	b = _buffer(0.4)
	_tone(b, 0.0, 523.0, 0.25, 0.6, WOOD)
	_tone(b, 0.09, 392.0, 0.3, 0.6, WOOD)
	_streams["undo"] = _wav(b)

	# Récompense (étoile, place gagnée, joker, barrière ouverte) : carillon brillant.
	b = _buffer(0.75)
	_tone(b, 0.0, 988.0, 0.5, 0.42, BELL)
	_tone(b, 0.08, 1319.0, 0.67, 0.45, BELL)
	_streams["star"] = _wav(b)

	# Départ d'un train : deux coups de sifflet à vapeur.
	b = _buffer(0.78)
	_whistle(b, 0.0, 0.16)
	_whistle(b, 0.24, 0.50)
	_streams["whistle"] = _wav(b)

	# Niveau réussi : arpège de bois qui monte, puis accord de carillon.
	b = _buffer(1.5)
	var rise: Array[float] = [523.0, 659.0, 784.0, 1047.0]
	for i: int in rise.size():
		_tone(b, 0.11 * i, rise[i], 0.5, 0.55, WOOD)
	for f: float in [1047.0, 1319.0, 1568.0]:
		_tone(b, 0.46, f, 1.0, 0.24, BELL)
	_streams["win"] = _wav(b)

	# Gare bloquée : trois notes de bois qui descendent, douces.
	b = _buffer(1.0)
	var fall: Array[float] = [392.0, 311.0, 262.0]
	for i: int in fall.size():
		_tone(b, 0.2 * i, fall[i], 0.55, 0.55, WOOD)
	_streams["lose"] = _wav(b)

	# Attelage : choc de métal (bruit bref, coup sourd, tintement).
	b = _buffer(0.16)
	_noise(b, 0.0, 0.045, 0.7, 0.35)
	_tone(b, 0.0, 95.0, 0.1, 0.8, THUD)
	_tone(b, 0.0, 1480.0, 0.14, 0.16, [[1.0, 1.0, 30.0], [1.62, 0.6, 38.0]])
	_streams["clack"] = _wav(b)

	for i: int in 8:
		var p: AudioStreamPlayer = AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)


func play(sound: String, pitch: float = 1.0) -> void:
	var p: AudioStreamPlayer = _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = _streams[sound]
	p.pitch_scale = pitch
	p.play()


func _buffer(seconds: float) -> PackedFloat32Array:
	var b: PackedFloat32Array = PackedFloat32Array()
	b.resize(int(seconds * RATE))
	return b


## Ajoute une note frappée : chaque partiel démarre net puis s'éteint à sa propre vitesse.
func _tone(b: PackedFloat32Array, start: float, freq: float, duration: float, volume: float,
		partials: Array) -> void:
	var first: int = int(start * RATE)
	var n: int = mini(int(duration * RATE), b.size() - first)
	for partial: Array in partials:
		var step: float = TAU * freq * float(partial[0]) / RATE
		var level: float = volume * float(partial[1])
		var decay: float = float(partial[2]) / RATE
		for i: int in n:
			# Attaque de 2 ms et fin en fondu, pour éviter les claquements numériques.
			var edge: float = minf(1.0, i / 64.0) * minf(1.0, (n - i) / 160.0)
			b[first + i] += sin(step * i) * level * exp(-decay * i) * edge


## Ajoute un souffle bref. `smooth` (0 à 1) : plus il est haut, plus le bruit est sourd.
func _noise(b: PackedFloat32Array, start: float, duration: float, volume: float, smooth: float) -> void:
	var first: int = int(start * RATE)
	var n: int = mini(int(duration * RATE), b.size() - first)
	var previous: float = 0.0
	for i: int in n:
		previous = previous * smooth + _rng.randf_range(-1.0, 1.0) * (1.0 - smooth)
		b[first + i] += previous * volume * exp(-5.0 * i / n)


## Coup de sifflet à vapeur : trois tuyaux accordés, un léger tremblement et du souffle.
func _whistle(b: PackedFloat32Array, start: float, duration: float) -> void:
	var first: int = int(start * RATE)
	var n: int = mini(int(duration * RATE), b.size() - first)
	var pipes: Array[float] = [587.0, 698.0, 880.0]
	var phases: Array[float] = [0.0, 0.0, 0.0]
	var breath: float = 0.0
	for i: int in n:
		var t: float = float(i) / RATE
		# Le sifflet monte en pression, tient, puis retombe.
		var envelope: float = minf(1.0, t / 0.05) * minf(1.0, (duration - t) / 0.09)
		# La note glisse un peu vers le haut à l'attaque et tremble légèrement.
		var bend: float = 1.0 - 0.03 * exp(-t * 30.0) + 0.004 * sin(TAU * 6.0 * t)
		var v: float = 0.0
		for k: int in pipes.size():
			phases[k] += TAU * pipes[k] * bend / RATE
			v += sin(phases[k]) * 0.2 + sin(phases[k] * 2.0) * 0.05
		breath = breath * 0.55 + _rng.randf_range(-1.0, 1.0) * 0.45
		b[first + i] += (v + breath * 0.10) * envelope * 0.75


## Convertit le tampon en son 16 bits, avec un écrêtage doux.
func _wav(b: PackedFloat32Array) -> AudioStreamWAV:
	var data: PackedByteArray = PackedByteArray()
	data.resize(b.size() * 2)
	for i: int in b.size():
		data.encode_s16(i * 2, int(tanh(b[i]) * 32000.0))
	var wav: AudioStreamWAV = AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = data
	return wav
