extends RefCounted
## Solveur et mesure de difficulté pour la gare de triage.

const Game := preload("res://src/triage_game.gd")


## Cherche une solution depuis l'état donné (non modifié).
## Renvoie {solvable: bool, moves: Array[int], states: int} ; `moves` liste les voies choisies.
## `limit` > 0 : abandonne après ce nombre d'états visités (`aborted` vaut alors true et
## `solvable` false, sans que le niveau soit forcément infaisable).
static func solve(game: Game, limit: int = 0) -> Dictionary:
	var start: Game = game.clone() as Game
	start.settle()
	var seen: Dictionary = {}
	var path: Array[int] = []
	var ok: bool = _dfs(start, seen, path, limit)
	return {"solvable": ok, "moves": path, "states": seen.size(),
		"aborted": not ok and limit > 0 and seen.size() >= limit}


static func _dfs(g: Game, seen: Dictionary, path: Array[int], limit: int = 0) -> bool:
	if limit > 0 and seen.size() >= limit:
		return false
	var st: int = g.status()
	if st == Game.WON:
		return true
	if st == Game.LOST:
		return false
	var k: String = g.key()
	if seen.has(k):
		return false
	seen[k] = true
	for t: int in g.tracks.size():
		if not g.can_take(t):
			continue
		var n: Game = g.clone() as Game
		n.take(t)
		n.settle()
		path.append(t)
		if _dfs(n, seen, path, limit):
			return true
		path.pop_back()
	return false


## Part des parties gagnées en jouant au hasard : plus c'est bas, plus le niveau est dur.
static func random_win_rate(game: Game, tries: int, rng: RandomNumberGenerator) -> float:
	var wins: int = 0
	for i: int in tries:
		var g: Game = game.clone() as Game
		g.settle()
		while g.status() == Game.PLAYING:
			var options: Array[int] = []
			for t: int in g.tracks.size():
				if g.can_take(t):
					options.append(t)
			g.take(options[rng.randi_range(0, options.size() - 1)])
			g.settle()
		if g.status() == Game.WON:
			wins += 1
	return float(wins) / float(tries)
