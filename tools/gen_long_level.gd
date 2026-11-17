extends SceneTree
## Ajoute à data/levels.json un niveau d'essai très long (une centaine de wagons), pour
## juger des parties plus longues. Il remplace le niveau long déjà présent, s'il y en a un.
## Attention : tools/gen_levels.gd réécrit levels.json sans ce niveau ; relancer ce script après.
## Usage : godot --headless --path . -s tools/gen_long_level.gd

const Game := preload("res://src/triage_game.gd")
const Solver := preload("res://src/triage_solver.gd")

## Valeurs d'essai.
const TRACKS := 5
const PER_TRACK := 20
const COLORS := 6
const BONUS := 2
const LINKS := 5
## Places d'attente données au joueur. Avec les « +1 », 8 places au plus tiennent à l'écran.
const BUFFER := 6
## Le niveau retenu doit être faisable avec ce nombre de places au plus : le reste est de la marge.
const PAR_MAX := 4
const SIZES: Array[int] = [2, 3, 4]
const CANDIDATES := 40
## Plafond d'états explorés par recherche (au-delà, on passe au candidat suivant).
const STATE_LIMIT := 150000


func _init() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 20261117
	var best: Dictionary = {}
	for c: int in CANDIDATES:
		var level: Dictionary = _random_level(rng)
		var par: int = _par(level)
		print("candidat %d : par %d" % [c + 1, par])
		if par < 0:
			continue
		level["par"] = par + BONUS
		# On garde le candidat le moins exigeant : la marge du joueur est BUFFER - par.
		if best.is_empty() or int(level["par"]) < int(best["par"]):
			best = level
		if par <= 3:
			break
	if best.is_empty():
		push_error("aucun niveau long faisable trouvé")
		quit(1)
		return
	best["long"] = true
	var levels: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/levels.json"))
	levels = levels.filter(func(l: Dictionary) -> bool: return not l.get("long", false))
	levels.append(best)
	var f: FileAccess = FileAccess.open("res://data/levels.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(levels, "\t") + "\n")
	f.close()
	var n: int = 0
	for track: Array in best["tracks"]:
		n += track.size()
	print("niveau long : %d wagons, %d trains, par %d, %d niveaux au total" % [
		n, best["trains"].size(), best["par"], levels.size()])
	quit(0)


## Plus petit nombre de places d'attente avec lequel une solution est trouvée (-1 sinon).
func _par(level: Dictionary) -> int:
	for b: int in range(2, PAR_MAX + 1):
		var trial: Dictionary = level.duplicate()
		trial["buffer"] = b
		var g: Game = Game.new()
		g.load_level(trial)
		if Solver.solve(g, STATE_LIMIT)["solvable"]:
			return b
	return -1


func _random_level(rng: RandomNumberGenerator) -> Dictionary:
	var total: int = TRACKS * PER_TRACK - BONUS
	var wagons: Array[int] = []
	var trains: Array[int] = []
	var lengths: Array[int] = []
	var color: int = 0
	while total > 0:
		var size: int = SIZES[rng.randi_range(0, SIZES.size() - 1)]
		# Le dernier train prend ce qui reste, sans jamais laisser un wagon seul.
		if total - size < 2:
			size = total
		trains.append(color)
		lengths.append(size)
		for w: int in size:
			wagons.append(color)
		total -= size
		color = (color + 1) % COLORS
	_shuffle(wagons, rng)
	var order: Array[int] = []
	for i: int in trains.size():
		order.append(i)
	_shuffle(order, rng)
	var train_colors: Array[int] = []
	var train_sizes: Array[int] = []
	for i: int in order:
		train_colors.append(trains[i])
		train_sizes.append(lengths[i])
	var tracks: Array = []
	for t: int in TRACKS:
		tracks.append([])
	for i: int in wagons.size():
		tracks[i % TRACKS].append(wagons[i])
	# Wagons « +1 » : dans le premier tiers de deux voies différentes, pour servir tôt.
	var free: Array[int] = []
	for t: int in TRACKS:
		free.append(t)
	_shuffle(free, rng)
	for j: int in BONUS:
		tracks[free[j]].insert(rng.randi_range(3, 7), Game.BONUS)
	var links: Array = []
	for track: Array in tracks:
		var row: Array = []
		row.resize(track.size())
		row.fill(0)
		links.append(row)
	var placed: int = 0
	for attempt: int in 400:
		if placed >= LINKS:
			break
		var t: int = rng.randi_range(0, TRACKS - 1)
		var k: int = rng.randi_range(0, tracks[t].size() - 2)
		if tracks[t][k] == Game.BONUS or tracks[t][k + 1] == Game.BONUS:
			continue
		if links[t][k] == 1 or links[t][k + 1] == 1 or (k > 0 and links[t][k - 1] == 1):
			continue
		links[t][k] = 1
		placed += 1
	return {"tracks": tracks, "links": links, "trains": train_colors, "train_sizes": train_sizes,
		"buffer": BUFFER, "slots": 2}


func _shuffle(a: Array[int], rng: RandomNumberGenerator) -> void:
	for i: int in range(a.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var tmp: int = a[i]
		a[i] = a[j]
		a[j] = tmp
