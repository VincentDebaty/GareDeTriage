extends RefCounted
## Logique pure de la gare de triage (version 2). Aucune dépendance au rendu.
##
## Règles :
## - plusieurs voies d'arrivée ; seul le wagon de tête de chaque voie est accessible ;
## - des trains à quai qui attendent chacun un nombre donné de wagons d'une couleur ;
## - une voie d'attente de `buffer_size` places.
## Le choix du joueur : quel wagon de tête prendre (`take`). S'il est attendu par un
## train à quai, il y monte ; sinon il va sur la voie d'attente. Les wagons en attente
## montent automatiquement quand leur train arrive (`settle_step` / `settle`).

const PLAYING := 0
const WON := 1
const LOST := 2

## Longueur par défaut d'un train quand le niveau ne la précise pas.
var train_size: int = 3
var buffer_size: int = 4
## Couleur de chaque wagon, indexée par identifiant.
var colors: PackedInt32Array = PackedInt32Array()
## 1 si le wagon est « mystère » (couleur masquée tant qu'il n'est pas en tête de voie).
## Purement informatif : la règle ne s'en sert pas, seul l'affichage le lit.
var hidden: PackedByteArray = PackedByteArray()
## Array[Array[int]] : l'index 0 de chaque voie est le wagon de tête.
var tracks: Array = []
var buffer: Array[int] = []
## Array[Dictionary] {color: int, size: int, ids: Array[int]} ; color = -1 pour un quai vide.
var slots: Array = []
## Couleurs des trains qui ne sont pas encore à quai.
var pending: Array[int] = []
## Longueur de chacun de ces trains (même ordre que `pending`).
var pending_sizes: Array[int] = []
var moves: int = 0
## Plus grand nombre de wagons en attente en même temps (sert à la note).
var peak_buffer: int = 0


func load_level(level: Dictionary) -> void:
	train_size = int(level.get("train_size", 3))
	buffer_size = int(level["buffer"])
	colors = PackedInt32Array()
	hidden = PackedByteArray()
	tracks.clear()
	var masks: Array = level.get("hidden", [])
	for t: int in level["tracks"].size():
		var track: Array = level["tracks"][t]
		var ids: Array[int] = []
		for k: int in track.size():
			ids.append(colors.size())
			colors.append(int(track[k]))
			hidden.append(1 if t < masks.size() and int(masks[t][k]) == 1 else 0)
		tracks.append(ids)
	buffer.clear()
	pending.clear()
	pending_sizes.clear()
	var sizes: Array = level.get("train_sizes", [])
	for i: int in level["trains"].size():
		pending.append(int(level["trains"][i]))
		pending_sizes.append(int(sizes[i]) if i < sizes.size() else train_size)
	slots.clear()
	for i: int in int(level.get("slots", 2)):
		slots.append(_next_train())
	moves = 0
	peak_buffer = 0


func _next_train() -> Dictionary:
	var ids: Array[int] = []
	if pending.is_empty():
		return {"color": -1, "size": 0, "ids": ids}
	return {"color": pending.pop_front(), "size": pending_sizes.pop_front(), "ids": ids}


func _slot_for(color: int) -> int:
	for s: int in slots.size():
		if slots[s]["color"] == color and slots[s]["ids"].size() < slots[s]["size"]:
			return s
	return -1


func can_take(track: int) -> bool:
	if tracks[track].is_empty():
		return false
	return _slot_for(colors[tracks[track][0]]) >= 0 or buffer.size() < buffer_size


## Prend le wagon de tête d'une voie. Renvoie {} si le coup est impossible,
## sinon {id, slot} avec slot = -1 quand le wagon part sur la voie d'attente.
func take(track: int) -> Dictionary:
	if not can_take(track):
		return {}
	var id: int = tracks[track].pop_front()
	moves += 1
	var slot: int = _slot_for(colors[id])
	if slot >= 0:
		slots[slot]["ids"].append(id)
	else:
		buffer.append(id)
		peak_buffer = maxi(peak_buffer, buffer.size())
	return {"id": id, "slot": slot}


## Applique un seul mouvement automatique et le décrit, ou renvoie {} s'il n'y en a pas.
## - {type: "depart", slot, ids} : un train complet part, le suivant prend le quai ;
## - {type: "load", id, slot} : un wagon en attente rejoint son train.
func settle_step() -> Dictionary:
	for s: int in slots.size():
		if slots[s]["color"] != -1 and slots[s]["ids"].size() >= slots[s]["size"]:
			var gone: Array = slots[s]["ids"]
			slots[s] = _next_train()
			return {"type": "depart", "slot": s, "ids": gone}
	for b: int in buffer.size():
		var slot: int = _slot_for(colors[buffer[b]])
		if slot >= 0:
			var id: int = buffer[b]
			buffer.remove_at(b)
			slots[slot]["ids"].append(id)
			return {"type": "load", "id": id, "slot": slot}
	return {}


func settle() -> void:
	while not settle_step().is_empty():
		pass


## État de la partie. À appeler une fois les mouvements automatiques épuisés.
func status() -> int:
	var empty: bool = buffer.is_empty()
	for t: Array in tracks:
		empty = empty and t.is_empty()
	for sl: Dictionary in slots:
		empty = empty and sl["color"] == -1
	if empty:
		return WON
	for t: int in tracks.size():
		if can_take(t):
			return PLAYING
	return LOST


## Nombre de wagons encore en jeu (voies + attente + trains à quai).
func wagons_in_play() -> int:
	var n: int = buffer.size()
	for t: Array in tracks:
		n += t.size()
	for sl: Dictionary in slots:
		n += sl["ids"].size()
	return n


func clone() -> RefCounted:
	var g: RefCounted = (get_script() as GDScript).new()
	g.train_size = train_size
	g.buffer_size = buffer_size
	g.colors = colors
	g.hidden = hidden
	g.tracks = tracks.duplicate(true)
	g.buffer = buffer.duplicate()
	g.slots = slots.duplicate(true)
	g.pending = pending.duplicate()
	g.pending_sizes = pending_sizes.duplicate()
	g.moves = moves
	g.peak_buffer = peak_buffer
	return g


## Clé d'état pour le solveur.
func key() -> String:
	var k: String = ""
	for t: Array in tracks:
		k += str(t.size()) + ","
	var waiting: PackedInt32Array = PackedInt32Array()
	for id: int in buffer:
		waiting.append(colors[id])
	waiting.sort()
	k += "|" + str(waiting) + "|"
	for sl: Dictionary in slots:
		k += "%d:%d," % [sl["color"], sl["ids"].size()]
	return k + "|" + str(pending.size())
