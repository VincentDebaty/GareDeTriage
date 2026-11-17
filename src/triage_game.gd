extends RefCounted
## Logique pure de la gare de triage. Aucune dépendance au rendu.
##
## Règles :
## - plusieurs voies d'arrivée ; seul le wagon de tête de chaque voie est accessible ;
## - des trains à quai qui attendent chacun un nombre donné de wagons d'une couleur ;
## - une voie d'attente de `buffer_size` places.
## Le choix du joueur : quel wagon de tête prendre (`take`). S'il est attendu par un
## train à quai, il y monte ; sinon il va sur la voie d'attente. Les wagons en attente
## montent automatiquement quand leur train arrive (`settle_step` / `settle`).
##
## Deux wagons attelés partent ensemble : le coup n'est possible que si chacun a une
## place (dans son train ou en attente).
## Un wagon « +1 » (BONUS) ne va dans aucun train : quand on le prend, il devient une
## place d'attente supplémentaire pour le reste du niveau.

const PLAYING := 0
const WON := 1
const LOST := 2
## Couleur réservée au wagon « +1 place d'attente ».
const BONUS := 9
## Destination d'un wagon « +1 » dans le résultat de `take`.
const TO_BONUS := -2

## Longueur par défaut d'un train quand le niveau ne la précise pas.
var train_size: int = 3
var buffer_size: int = 4
## Couleur de chaque wagon, indexée par identifiant.
var colors: PackedInt32Array = PackedInt32Array()
## 1 si le wagon est « mystère » (couleur masquée tant qu'il n'est pas en tête de voie).
## Purement informatif : la règle ne s'en sert pas, seul l'affichage le lit.
var hidden: PackedByteArray = PackedByteArray()
## 1 si le wagon est attelé à celui qui le suit sur sa voie.
var linked: PackedByteArray = PackedByteArray()
## Array[Array[int]] : l'index 0 de chaque voie est le wagon de tête.
var tracks: Array = []
var buffer: Array[int] = []
## Array[Dictionary] {color, size, ids} ; color = -1 pour un quai vide.
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
	linked = PackedByteArray()
	tracks.clear()
	var masks: Array = level.get("hidden", [])
	var links: Array = level.get("links", [])
	for t: int in level["tracks"].size():
		var track: Array = level["tracks"][t]
		var ids: Array[int] = []
		for k: int in track.size():
			ids.append(colors.size())
			colors.append(int(track[k]))
			hidden.append(1 if t < masks.size() and int(masks[t][k]) == 1 else 0)
			linked.append(1 if t < links.size() and int(links[t][k]) == 1 else 0)
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


## Quai dont le train attend encore un wagon de cette couleur (-1 s'il n'y en a pas).
## `added` : wagons déjà promis à chaque quai pendant le coup en cours.
func _slot_for(color: int, added: Dictionary = {}) -> int:
	for s: int in slots.size():
		if slots[s]["color"] == color and slots[s]["ids"].size() + int(added.get(s, 0)) < slots[s]["size"]:
			return s
	return -1


## Wagons qui partent ensemble si on prend la tête de cette voie.
func _group(track: int) -> Array[int]:
	var ids: Array[int] = []
	if tracks[track].is_empty():
		return ids
	ids.append(tracks[track][0])
	if linked[ids[0]] == 1 and tracks[track].size() > 1:
		ids.append(tracks[track][1])
	return ids


## Destination de chaque wagon du groupe : un quai, -1 pour la voie d'attente, ou
## TO_BONUS pour un wagon « +1 ». Renvoie un tableau vide si le coup est impossible.
func _plan(track: int) -> Array[int]:
	var plan: Array[int] = []
	var added: Dictionary = {}
	var waiting: int = buffer.size()
	var places: int = buffer_size
	for id: int in _group(track):
		var slot: int = -1
		if colors[id] == BONUS:
			# Toujours possible : il ne demande aucune place et en crée une.
			slot = TO_BONUS
			places += 1
		else:
			slot = _slot_for(colors[id], added)
			if slot >= 0:
				added[slot] = int(added.get(slot, 0)) + 1
			elif waiting < places:
				waiting += 1
			else:
				plan.clear()
				return plan
		plan.append(slot)
	return plan


func can_take(track: int) -> bool:
	return not _plan(track).is_empty()


## Prend le wagon de tête d'une voie (et celui qui lui est attelé). Renvoie {} si le coup
## est impossible, sinon {moves: [{id, slot}, ...]} avec slot = -1 pour la voie d'attente
## et TO_BONUS pour un wagon « +1 » (qui disparaît en ajoutant une place d'attente).
func take(track: int) -> Dictionary:
	var plan: Array[int] = _plan(track)
	if plan.is_empty():
		return {}
	var done: Array = []
	for slot: int in plan:
		var id: int = tracks[track].pop_front()
		if slot == TO_BONUS:
			buffer_size += 1
		elif slot >= 0:
			slots[slot]["ids"].append(id)
		else:
			buffer.append(id)
		done.append({"id": id, "slot": slot})
	peak_buffer = maxi(peak_buffer, buffer.size())
	moves += 1
	return {"moves": done}


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
## Gagné quand tous les trains sont partis et qu'il ne reste aucun wagon de couleur ;
## un wagon « +1 » resté sur une voie est simplement inutilisé.
func status() -> int:
	var done: bool = buffer.is_empty()
	for t: Array in tracks:
		for id: int in t:
			done = done and colors[id] == BONUS
	for sl: Dictionary in slots:
		done = done and sl["color"] == -1
	if done:
		return WON
	for t: int in tracks.size():
		if can_take(t):
			return PLAYING
	return LOST


# --- Jokers ------------------------------------------------------------------
# Chaque joker renvoie false s'il n'a rien à faire (il n'est alors pas dépensé).
# Appeler `settle` ensuite : un train complété part, les wagons en attente montent.

## Détache un wagon de ses voisins de voie avant de le déplacer.
func _detach(track: int, k: int) -> void:
	linked[tracks[track][k]] = 0
	if k > 0:
		linked[tracks[track][k - 1]] = 0


## Aimant : complète le train à quai auquel il manque le plus de wagons, en tirant ses
## wagons des voies (les plus proches de la sortie d'abord).
func joker_magnet() -> bool:
	var slot: int = -1
	var need: int = 0
	for s: int in slots.size():
		if slots[s]["color"] == -1:
			continue
		var missing: int = int(slots[s]["size"]) - slots[s]["ids"].size()
		if missing > need:
			need = missing
			slot = s
	if slot < 0:
		return false
	var moved: bool = false
	while slots[slot]["ids"].size() < int(slots[slot]["size"]):
		var best_t: int = -1
		var best_k: int = -1
		for t: int in tracks.size():
			for k: int in tracks[t].size():
				if colors[tracks[t][k]] == slots[slot]["color"]:
					if best_t < 0 or k < best_k:
						best_t = t
						best_k = k
					break
		if best_t < 0:
			break
		_detach(best_t, best_k)
		slots[slot]["ids"].append(tracks[best_t][best_k])
		tracks[best_t].remove_at(best_k)
		moved = true
	return moved


## Mélange : redistribue au hasard tous les wagons des voies (chaque voie garde sa
## longueur). Les attelages sont défaits.
func joker_shuffle(rng: RandomNumberGenerator) -> bool:
	var ids: Array[int] = []
	for t: Array in tracks:
		for id: int in t:
			ids.append(id)
	if ids.size() < 2:
		return false
	for i: int in range(ids.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var tmp: int = ids[i]
		ids[i] = ids[j]
		ids[j] = tmp
	var n: int = 0
	for t: Array in tracks:
		for k: int in t.size():
			t[k] = ids[n]
			linked[ids[n]] = 0
			n += 1
	return true


## Renvoi : les wagons en attente repartent au fond des voies (les plus courtes d'abord),
## la voie d'attente est vide.
func joker_send_back() -> bool:
	if buffer.is_empty():
		return false
	for id: int in buffer:
		var shortest: int = 0
		for t: int in tracks.size():
			if tracks[t].size() < tracks[shortest].size():
				shortest = t
		linked[id] = 0
		tracks[shortest].append(id)
	buffer.clear()
	return true


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
	g.linked = linked
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
	var k: String = str(buffer_size) + "/"
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
