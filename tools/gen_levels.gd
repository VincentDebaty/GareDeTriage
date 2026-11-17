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
## `links` : nombre de paires de wagons attelés ; `bonus` : nombre de wagons « +1 place d'attente » ;
## `hint` : message affiché au premier niveau du palier.
const TIERS: Array[Dictionary] = [
	{"count": 1, "colors": 2, "trains_per_color": 1, "tracks": 2, "buffer": 4, "sizes": [3], "hidden": 0.0, "links": 0, "bonus": 0, "from": 0.90, "to": 0.90,
		"hint": "Touchez une voie pour envoyer son wagon du bas vers son train. S'il n'est pas attendu, il patiente sur la voie d'attente."},
	{"count": 2, "colors": 3, "trains_per_color": 1, "tracks": 3, "buffer": 2, "sizes": [3], "hidden": 0.0, "links": 0, "bonus": 0, "from": 0.65, "to": 0.55},
	{"count": 3, "colors": 3, "trains_per_color": 2, "tracks": 3, "buffer": 4, "sizes": [2, 3, 4], "hidden": 0.0, "links": 0, "bonus": 0, "from": 0.45, "to": 0.30,
		"hint": "Nouveau : les trains n'ont pas tous la même longueur."},
	{"count": 4, "colors": 4, "trains_per_color": 2, "tracks": 4, "buffer": 4, "sizes": [2, 3, 4], "hidden": 0.0, "links": 2, "bonus": 0, "from": 0.30, "to": 0.15,
		"hint": "Nouveau : deux wagons attelés partent ensemble. Il faut une place pour chacun."},
	{"count": 5, "colors": 4, "trains_per_color": 2, "tracks": 4, "buffer": 3, "sizes": [2, 3, 4], "hidden": 0.0, "links": 2, "bonus": 1, "from": 0.20, "to": 0.08,
		"hint": "Nouveau : le wagon « +1 » ajoute une place d'attente pour le reste du niveau."},
	{"count": 5, "colors": 5, "trains_per_color": 2, "tracks": 5, "buffer": 5, "sizes": [2, 3, 4], "hidden": 0.0, "links": 3, "bonus": 1, "from": 0.14, "to": 0.06},
	{"count": 5, "colors": 5, "trains_per_color": 2, "tracks": 5, "buffer": 4, "sizes": [2, 3, 4], "hidden": 0.0, "links": 3, "bonus": 2, "from": 0.08, "to": 0.03},
	{"count": 5, "colors": 6, "trains_per_color": 2, "tracks": 5, "buffer": 5, "sizes": [2, 3, 4], "hidden": 0.0, "links": 4, "bonus": 2, "from": 0.07, "to": 0.02},
]
## Nombre de trains à quai en même temps, pour les niveaux qui s'écartent des 2 habituels
## (numéro de niveau -> quais). Un seul quai oblige à suivre l'ordre des trains : la voie
## d'attente y gagne 2 places. Trois quais donnent de l'air : elle en perd une.
const QUAYS: Dictionary = {9: 3, 13: 1, 14: 3, 17: 1, 18: 3, 21: 1, 22: 3, 25: 1, 26: 3, 28: 1, 29: 3}
const QUAY_HINTS: Dictionary = {
	9: "Nouveau : trois trains à quai.",
	13: "Nouveau : un seul quai, un train à la fois.",
}
## Barrières : numéro de niveau -> pour chaque voie fermée, nombre de trains qui doivent partir
## avant qu'elle s'ouvre. Les voies fermées sont tirées au hasard.
const GATES: Dictionary = {15: [2], 19: [2], 20: [3], 23: [2], 24: [3], 27: [2, 3], 30: [2, 4]}
const GATE_HINT := "Nouveau : la barrière s'ouvre après 2 trains partis."
## À partir de ce niveau, les voies d'arrivée n'ont plus toutes la même longueur.
const UNEVEN_FROM := 4
## Nombre de places d'attente que l'écran peut montrer.
const MAX_PLACES := 8
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
		for c: int in CANDIDATES * 6:
			# Aucun tirage faisable : on redonne une place d'attente et on recommence.
			if c > 0 and c % CANDIDATES == 0:
				if not best.is_empty():
					break
				var most: int = MAX_PLACES - int(spec["bonus"])
				if int(spec["buffer"]) < most:
					spec["buffer"] = int(spec["buffer"]) + 1
				else:
					# Voie d'attente déjà au maximum : les barrières s'ouvrent un train plus tôt.
					var easier: Array = []
					for g: int in spec.get("gates", []):
						if g > 1:
							easier.append(g - 1)
					spec["gates"] = easier
			var level: Dictionary = _random_level(spec, rng)
			var par: int = _par(level)
			if par < 0:
				continue
			# Le « par » est le plus grand nombre de wagons en attente d'une partie idéale :
			# les places de base strictement nécessaires, plus celles des wagons « +1 ».
			level["par"] = par + int(spec["bonus"])
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
	for i: int in specs.size():
		var number: int = i + 1
		specs[i]["uneven"] = number >= UNEVEN_FROM
		if QUAYS.has(number):
			var quays: int = QUAYS[number]
			specs[i]["slots"] = quays
			specs[i]["buffer"] = maxi(2, int(specs[i]["buffer"]) + (2 if quays == 1 else -1))
			# L'écran montre 8 places d'attente au plus, wagons « +1 » compris.
			specs[i]["buffer"] = mini(int(specs[i]["buffer"]), MAX_PLACES - int(specs[i]["bonus"]))
		if QUAY_HINTS.has(number):
			specs[i]["hint"] = QUAY_HINTS[number]
		if GATES.has(number):
			specs[i]["gates"] = GATES[number].duplicate()
	var first_gate: int = GATES.keys().min()
	specs[first_gate - 1]["hint"] = GATE_HINT
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
		# Chaque voie garde une place libre pour un éventuel wagon « +1 ».
		if wagons.size() <= track_count * (TRACK_ROWS - (1 if int(spec["bonus"]) > 0 else 0)):
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
	# Longueur de chaque voie : égales au départ, puis des wagons passent d'une voie à
	# l'autre pour que le plateau n'ait pas toujours la même silhouette.
	var room: int = TRACK_ROWS - (1 if int(spec["bonus"]) > 0 else 0)
	var sizes_of: Array[int] = []
	for t: int in track_count:
		sizes_of.append(wagons.size() / track_count + (1 if t < wagons.size() % track_count else 0))
	if spec.get("uneven", false):
		for step: int in wagons.size() * 3:
			var a: int = rng.randi_range(0, track_count - 1)
			var b: int = rng.randi_range(0, track_count - 1)
			if a != b and sizes_of[a] > 2 and sizes_of[b] < room:
				sizes_of[a] -= 1
				sizes_of[b] += 1
	var next: int = 0
	for t: int in track_count:
		for k: int in sizes_of[t]:
			# Le wagon de tête (premier de la voie) n'est jamais masqué.
			var masked: bool = k > 0 and rng.randf() < float(spec["hidden"])
			tracks[t].append(wagons[next])
			hidden[t].append(1 if masked else 0)
			next += 1
	# Wagons « +1 » : chacun au milieu d'une voie différente (centre à un wagon près), pour qu'on
	# aille le chercher sans qu'il soit ni offert d'entrée ni enfoui au fond.
	var free: Array[int] = []
	for t: int in track_count:
		free.append(t)
	_shuffle(free, rng)
	for j: int in mini(int(spec["bonus"]), track_count):
		var n: int = tracks[free[j]].size()
		var k: int = clampi(n / 2 + rng.randi_range(-1, 1), 1, maxi(n - 1, 1))
		tracks[free[j]].insert(k, Game.BONUS)
		hidden[free[j]].insert(k, 0)
	# Paires de wagons attelés : deux wagons voisins d'une même voie, jamais un « +1 »,
	# jamais deux paires qui se touchent.
	var links: Array = []
	for track: Array in tracks:
		var row: Array = []
		row.resize(track.size())
		row.fill(0)
		links.append(row)
	var placed: int = 0
	for attempt: int in 200:
		if placed >= int(spec["links"]):
			break
		var t: int = rng.randi_range(0, track_count - 1)
		var track: Array = tracks[t]
		if track.size() < 2:
			continue
		var k: int = rng.randi_range(0, track.size() - 2)
		if track[k] == Game.BONUS or track[k + 1] == Game.BONUS:
			continue
		if links[t][k] == 1 or links[t][k + 1] == 1 or (k > 0 and links[t][k - 1] == 1):
			continue
		links[t][k] = 1
		placed += 1
	# Barrières : sur des voies différentes, jamais sur toutes.
	var gates: Array[int] = []
	for t: int in track_count:
		gates.append(0)
	var closed: Array[int] = []
	for t: int in track_count:
		closed.append(t)
	_shuffle(closed, rng)
	var wanted: Array = spec.get("gates", [])
	for j: int in mini(wanted.size(), track_count - 1):
		gates[closed[j]] = int(wanted[j])
	return {
		"gates": gates,
		"tracks": tracks,
		"hidden": hidden,
		"links": links,
		"trains": trains,
		"train_sizes": lengths,
		"buffer": spec["buffer"],
		"slots": int(spec.get("slots", 2)),
	}


func _shuffle(a: Array[int], rng: RandomNumberGenerator) -> void:
	for i: int in range(a.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var tmp: int = a[i]
		a[i] = a[j]
		a[j] = tmp
