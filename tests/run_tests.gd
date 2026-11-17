extends SceneTree
## Tests headless de la logique. Usage : godot --headless --path . -s tests/run_tests.gd

const Game := preload("res://src/triage_game.gd")
const Solver := preload("res://src/triage_solver.gd")

var _failed: int = 0
var _passed: int = 0


func _init() -> void:
	_test_expected_wagon_boards_train()
	_test_unexpected_wagon_waits_then_boards()
	_test_buffer_is_capped_and_blocks()
	_test_train_sizes_and_clone()
	_test_coupled_wagons()
	_test_bonus_place()
	_test_levels_are_consistent_and_solvable()
	_test_solution_replay_conserves_wagons()
	print("%d vérifications réussies, %d en échec" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


func _check(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		printerr("ÉCHEC : " + label)


func _game(tracks: Array, trains: Array, buffer: int, slots: int = 1) -> Game:
	var g: Game = Game.new()
	g.load_level({"tracks": tracks, "trains": trains, "buffer": buffer, "slots": slots})
	return g


func _levels() -> Array:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/levels.json"))


func _test_expected_wagon_boards_train() -> void:
	var g: Game = _game([[0, 0, 0]], [0], 0)
	for i: int in 3:
		_check(g.take(0)["moves"][0]["slot"] == 0, "wagon attendu : monte dans le train")
	g.settle()
	_check(g.status() == Game.WON, "train complet parti : gagné")
	_check(g.peak_buffer == 0, "aucune attente utilisée")


func _test_unexpected_wagon_waits_then_boards() -> void:
	# Train rouge (0) à quai, puis bleu (1). Le bleu de tête doit patienter.
	var g: Game = _game([[1, 0, 0, 0, 1, 1]], [0, 1], 2)
	_check(g.take(0)["moves"][0]["slot"] == -1, "wagon non attendu : voie d'attente")
	_check(g.buffer.size() == 1, "un wagon en attente")
	for i: int in 3:
		g.take(0)
	var ev: Dictionary = g.settle_step()
	_check(ev["type"] == "depart", "le train rouge part")
	ev = g.settle_step()
	_check(ev["type"] == "load" and g.buffer.is_empty(), "le bleu en attente monte dans le train bleu")
	g.take(0)
	g.take(0)
	g.settle()
	_check(g.status() == Game.WON, "partie gagnée")


func _test_buffer_is_capped_and_blocks() -> void:
	var g: Game = _game([[1, 1, 1, 0, 0, 0]], [0, 1], 2)
	g.take(0)
	g.take(0)
	_check(not g.can_take(0), "attente pleine : coup refusé")
	_check(g.take(0).is_empty(), "take renvoie {} quand le coup est impossible")
	_check(g.buffer.size() == 2, "capacité d'attente respectée")
	_check(g.status() == Game.LOST, "gare bloquée")


func _test_train_sizes_and_clone() -> void:
	# Un train rouge de 2 wagons, puis un train bleu de 4.
	var g: Game = Game.new()
	g.load_level({"tracks": [[0, 0, 1, 1, 1, 1]], "trains": [0, 1], "train_sizes": [2, 4],
		"hidden": [[0, 1, 1, 0, 0, 0]], "buffer": 0, "slots": 1})
	_check(g.hidden[1] == 1 and g.hidden[0] == 0, "wagons mystère lus depuis le niveau")
	g.take(0)
	var saved: Game = g.clone() as Game
	g.take(0)
	_check(g.settle_step()["type"] == "depart", "le train de 2 part dès 2 wagons")
	_check(g.slots[0]["size"] == 4, "le train suivant attend 4 wagons")
	for i: int in 4:
		g.take(0)
	g.settle()
	_check(g.status() == Game.WON, "partie gagnée avec des trains de longueurs différentes")
	_check(saved.tracks[0].size() == 5 and saved.slots[0]["ids"].size() == 1, "la copie (Annuler) n'est pas modifiée par la suite")


func _test_coupled_wagons() -> void:
	# Train rouge (0) à quai, puis bleu (1). Rouge et bleu attelés en tête de voie.
	var g: Game = Game.new()
	g.load_level({"tracks": [[0, 1, 0, 0, 1, 1]], "links": [[1, 0, 0, 0, 0, 0]],
		"trains": [0, 1], "buffer": 1, "slots": 1})
	var ev: Dictionary = g.take(0)
	_check(ev["moves"].size() == 2, "deux wagons attelés partent en un seul coup")
	_check(ev["moves"][0]["slot"] == 0 and ev["moves"][1]["slot"] == -1, "chacun va à sa place : train, attente")
	_check(g.moves == 1 and g.tracks[0].size() == 4, "un seul coup compté, deux wagons retirés")
	# Sans place d'attente pour le second, le coup est refusé en entier.
	var blocked: Game = Game.new()
	blocked.load_level({"tracks": [[0, 1, 0, 0, 1, 1]], "links": [[1, 0, 0, 0, 0, 0]],
		"trains": [0, 1], "buffer": 0, "slots": 1})
	_check(not blocked.can_take(0) and blocked.take(0).is_empty(), "pas de place pour les deux : coup refusé")
	_check(blocked.tracks[0].size() == 6, "rien n'a bougé après un coup refusé")
	# Deux wagons attelés de la même couleur ne dépassent pas la longueur du train.
	var same: Game = Game.new()
	same.load_level({"tracks": [[0, 0]], "links": [[1, 0]], "trains": [0], "train_sizes": [1],
		"buffer": 1, "slots": 1})
	ev = same.take(0)
	_check(ev["moves"][0]["slot"] == 0 and ev["moves"][1]["slot"] == -1, "le second de même couleur attend si le train est plein")


func _test_bonus_place() -> void:
	var b: int = Game.BONUS
	# Train rouge (0) à quai, puis bleu (1). Une seule place d'attente au départ.
	var g: Game = Game.new()
	g.load_level({"tracks": [[1, b, 1, 0, 0, 0, 1, b]], "trains": [0, 1], "buffer": 1, "slots": 1})
	g.take(0)
	_check(g.buffer.size() == 1 and g.buffer_size == 1, "un bleu en attente, attente pleine")
	var total: int = g.wagons_in_play()
	var ev: Dictionary = g.take(0)
	_check(ev["moves"][0]["slot"] == Game.TO_BONUS, "le wagon +1 est pris même quand l'attente est pleine")
	_check(g.buffer_size == 2 and g.buffer.size() == 1, "il ajoute une place d'attente sans en occuper")
	_check(g.wagons_in_play() == total - 1, "le wagon +1 quitte le jeu")
	_check(g.can_take(0), "le second bleu a maintenant une place")
	g.take(0)
	for i: int in 3:
		g.take(0)
	g.settle()
	g.take(0)
	g.settle()
	_check(g.tracks[0].size() == 1 and g.status() == Game.WON, "gagné même si un wagon +1 reste inutilisé")
	var saved: Game = g.clone() as Game
	_check(saved.buffer_size == 2, "la place ajoutée est conservée par la copie (Annuler)")


func _test_levels_are_consistent_and_solvable() -> void:
	var levels: Array = _levels()
	_check(levels.size() >= 30, "au moins trente niveaux")
	for n: int in levels.size():
		var level: Dictionary = levels[n]
		var sizes: Array = level.get("train_sizes", [])
		var wagons: Dictionary = {}
		for track: Variant in level["tracks"]:
			for c: Variant in track:
				if int(c) != Game.BONUS:
					wagons[int(c)] = int(wagons.get(int(c), 0)) + 1
		var wanted: Dictionary = {}
		for i: int in level["trains"].size():
			var c: int = int(level["trains"][i])
			var size: int = int(sizes[i]) if i < sizes.size() else int(level.get("train_size", 3))
			wanted[c] = int(wanted.get(c, 0)) + size
		_check(wagons == wanted, "niveau %d : wagons et trains concordent" % (n + 1))
		var g: Game = Game.new()
		g.load_level(level)
		_check(Solver.solve(g)["solvable"], "niveau %d : faisable" % (n + 1))
		var bonus: int = 0
		var middle: bool = true
		for track: Variant in level["tracks"]:
			var here: int = 0
			for k: int in track.size():
				if int(track[k]) == Game.BONUS:
					here += 1
					middle = middle and k >= 1 and k <= track.size() - 2
			middle = middle and here <= 1
			bonus += here
		_check(middle, "niveau %d : wagon +1 en milieu de voie, un par voie au plus" % (n + 1))
		var tight: Dictionary = level.duplicate()
		tight["buffer"] = int(level["par"]) - bonus
		g = Game.new()
		g.load_level(tight)
		_check(Solver.solve(g)["solvable"], "niveau %d : trois étoiles atteignables" % (n + 1))


func _test_solution_replay_conserves_wagons() -> void:
	for level: Variant in _levels():
		var g: Game = Game.new()
		g.load_level(level)
		var total: int = g.wagons_in_play()
		var departed: int = 0
		# Wagons « +1 » consommés : ils quittent le jeu sans partir en train.
		var consumed: int = 0
		var solution: Array = Solver.solve(g)["moves"]
		var ok: bool = true
		var step: int = 0
		while true:
			var ev: Dictionary = g.settle_step()
			if ev.is_empty():
				if step >= solution.size():
					break
				var taken: Dictionary = g.take(solution[step])
				ok = ok and not taken.is_empty()
				for m: Dictionary in taken.get("moves", []):
					if m["slot"] == Game.TO_BONUS:
						consumed += 1
				step += 1
			elif ev["type"] == "depart":
				departed += ev["ids"].size()
			ok = ok and g.wagons_in_play() + departed + consumed == total
			ok = ok and g.buffer.size() <= g.buffer_size
		_check(ok, "bilan des wagons et capacité d'attente respectés pendant la solution")
		# Un wagon « +1 » inutilisé peut rester sur une voie à la fin.
		_check(g.status() == Game.WON and departed + consumed + g.wagons_in_play() == total, "la solution du solveur gagne")
