extends SceneTree
## Génère data/levels.json : pour chaque palier, tire des niveaux au hasard, garde
## un niveau faisable dont le taux de réussite « au hasard » est le plus proche de la cible.
## Chaque niveau reçoit un « par » : le plus petit nombre de places d'attente qui suffit.
## Usage : godot --headless --path . -s tools/gen_levels.gd

const Game := preload("res://src/triage_game.gd")
const Solver := preload("res://src/triage_solver.gd")

## Valeurs d'essai, à ajuster librement. Chaque palier produit `count` niveaux dont la
## cible de réussite au hasard descend de `from` à `to` ; un nouveau palier repart un peu
## plus facile, pour alterner tension et respiration.
## `sizes` : longueurs de train possibles ; `hidden` : part de wagons mystère (à 0 pour
## l'instant : jugés trop perturbants à l'essai, le mécanisme reste disponible) ;
## `hint` : message affiché au premier niveau du palier.
const TIERS: Array[Dictionary] = [
	{"count": 1, "colors": 2, "trains_per_color": 1, "tracks": 2, "buffer": 4, "sizes": [3], "hidden": 0.0, "from": 0.90, "to": 0.90,
		"hint": "Touchez une voie pour envoyer son wagon du bas vers son train. S'il n'est pas attendu, il patiente sur la voie d'attente."},
	{"count": 2, "colors": 3, "trains_per_color": 1, "tracks": 3, "buffer": 2, "sizes": [3], "hidden": 0.0, "from": 0.65, "to": 0.55},
	{"count": 3, "colors": 3, "trains_per_color": 2, "tracks": 3, "buffer": 4, "sizes": [2, 3, 4], "hidden": 0.0, "from": 0.45, "to": 0.30,
		"hint": "Nouveau : les trains n'ont pas tous la même longueur."},
	{"count": 4, "colors": 4, "trains_per_color": 2, "tracks": 4, "buffer": 4, "sizes": [3], "hidden": 0.0, "from": 0.30, "to": 0.15},
	{"count": 5, "colors": 4, "trains_per_color": 2, "tracks": 4, "buffer": 3, "sizes": [2, 3, 4], "hidden": 0.0, "from": 0.20, "to": 0.08},
	{"count": 5, "colors": 5, "trains_per_color": 2, "tracks": 4, "buffer": 5, "sizes": [2, 3, 4], "hidden": 0.0, "from": 0.14, "to": 0.06},
	{"count": 5, "colors": 5, "trains_per_color": 2, "tracks": 4, "buffer": 4, "sizes": [2, 3, 4], "hidden": 0.0, "from": 0.08, "to": 0.03},
	{"count": 5, "colors": 6, "trains_per_color": 2, "tracks": 5, "buffer": 5, "sizes": [2, 3, 4], "hidden": 0.0, "from": 0.07, "to": 0.02},
]
## Nombre maximal de wagons par voie (hauteur disponible à l'écran).
const TRACK_ROWS := 8
const CANDIDATES := 40
const PLAYOUTS := 200
const TRAIN_SIZE := 3


func _init() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 20261116
	var levels: Array = []
	for spec: Dictionary in _specs():
		var best: Dictionary = {}
		var best_gap: float = 2.0
		var best_rate: float = 0.0
		for c: int in CANDIDATES:
			var level: Dictionary = _random_level(spec, rng)
			var par: int = _par(level)
			if par < 0:
				continue
			level["par"] = par
			var g: Game = Game.new()
			g.load_level(level)
			var rate: float = Solver.random_win_rate(g, PLAYOUTS, rng)
			var gap: float = absf(rate - float(spec["target"]))
			if gap < best_gap:
				best_gap = gap
				best = level
				best_rate = rate
		print("palier %d : %d wagons, par %d/%d, réussite au hasard %.0f %% (cible %.0f %%)" % [
			levels.size() + 1, _count(best),
			best["par"], best["buffer"], best_rate * 100.0, float(spec["target"]) * 100.0])
		if spec.has("hint"):
			best["hint"] = spec["hint"]
		levels.append(best)
	var f: FileAccess = FileAccess.open("res://data/levels.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(levels, "\t") + "\n")
	f.close()
	quit(0)


func _specs() -> Array[Dictionary]:
	var specs: Array[Dictionary] = []
	for tier: Dictionary in TIERS:
		var count: int = tier["count"]
		for i: int in count:
			var spec: Dictionary = tier.duplicate()
			if i > 0:
				spec.erase("hint")
			var t: float = 0.0 if count == 1 else float(i) / float(count - 1)
			spec["target"] = lerpf(tier["from"], tier["to"], t)
			specs.append(spec)
	return specs


## Plus petit nombre de places d'attente avec lequel le niveau reste faisable (-1 si infaisable).
func _par(level: Dictionary) -> int:
	for b: int in int(level["buffer"]) + 1:
		var trial: Dictionary = level.duplicate()
		trial["buffer"] = b
		var g: Game = Game.new()
		g.load_level(trial)
		if Solver.solve(g)["solvable"]:
			return b
	return -1


func _count(level: Dictionary) -> int:
	var n: int = 0
	for track: Array in level["tracks"]:
		n += track.size()
	return n


func _random_level(spec: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var sizes: Array = spec["sizes"]
	var track_count: int = spec["tracks"]
	var wagons: Array[int] = []
	var train_colors: Array[int] = []
	var train_sizes: Array[int] = []
	while true:
		wagons.clear()
		train_colors.clear()
		train_sizes.clear()
		for color: int in int(spec["colors"]):
			for t: int in int(spec["trains_per_color"]):
				var size: int = sizes[rng.randi_range(0, sizes.size() - 1)]
				train_colors.append(color)
				train_sizes.append(size)
				for w: int in size:
					wagons.append(color)
		if wagons.size() <= track_count * TRACK_ROWS:
			break
	_shuffle(wagons, rng)
	# Mélange les trains en gardant couleur et longueur appariées.
	var order: Array[int] = []
	for i: int in train_colors.size():
		order.append(i)
	_shuffle(order, rng)
	var trains: Array[int] = []
	var lengths: Array[int] = []
	for i: int in order:
		trains.append(train_colors[i])
		lengths.append(train_sizes[i])
	var tracks: Array = []
	var hidden: Array = []
	for t: int in track_count:
		tracks.append([])
		hidden.append([])
	for i: int in wagons.size():
		var track: Array = tracks[i % track_count]
		# Le wagon de tête (premier de la voie) n'est jamais masqué.
		var masked: bool = not track.is_empty() and rng.randf() < float(spec["hidden"])
		track.append(wagons[i])
		hidden[i % track_count].append(1 if masked else 0)
	return {
		"tracks": tracks,
		"hidden": hidden,
		"trains": trains,
		"train_sizes": lengths,
		"buffer": spec["buffer"],
		"slots": 2,
	}


func _shuffle(a: Array[int], rng: RandomNumberGenerator) -> void:
	for i: int in range(a.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var tmp: int = a[i]
		a[i] = a[j]
		a[j] = tmp
