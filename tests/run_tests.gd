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
		_check(g.take(0)["slot"] == 0, "wagon attendu : monte dans le train")
	g.settle()
	_check(g.status() == Game.WON, "train complet parti : gagné")
	_check(g.peak_buffer == 0, "aucune attente utilisée")


func _test_unexpected_wagon_waits_then_boards() -> void:
	# Train rouge (0) à quai, puis bleu (1). Le bleu de tête doit patienter.
	var g: Game = _game([[1, 0, 0, 0, 1, 1]], [0, 1], 2)
	_check(g.take(0)["slot"] == -1, "wagon non attendu : voie d'attente")
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


func _test_levels_are_consistent_and_solvable() -> void:
	var levels: Array = _levels()
	_check(levels.size() >= 30, "au moins trente niveaux")
	for n: int in levels.size():
		var level: Dictionary = levels[n]
		var sizes: Array = level.get("train_sizes", [])
		var wagons: Dictionary = {}
		for track: Variant in level["tracks"]:
			for c: Variant in track:
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
		var tight: Dictionary = level.duplicate()
		tight["buffer"] = int(level["par"])
		g = Game.new()
		g.load_level(tight)
		_check(Solver.solve(g)["solvable"], "niveau %d : trois étoiles atteignables" % (n + 1))


func _test_solution_replay_conserves_wagons() -> void:
	for level: Variant in _levels():
		var g: Game = Game.new()
		g.load_level(level)
		var total: int = g.wagons_in_play()
		var departed: int = 0
		var solution: Array = Solver.solve(g)["moves"]
		var ok: bool = true
		var step: int = 0
		while true:
			var ev: Dictionary = g.settle_step()
			if ev.is_empty():
				if step >= solution.size():
					break
				ok = ok and not g.take(solution[step]).is_empty()
				step += 1
			elif ev["type"] == "depart":
				departed += ev["ids"].size()
			ok = ok and g.wagons_in_play() + departed == total
			ok = ok and g.buffer.size() <= g.buffer_size
		_check(ok, "bilan des wagons et capacité d'attente respectés pendant la solution")
		_check(g.status() == Game.WON and departed == total, "la solution du solveur gagne")
