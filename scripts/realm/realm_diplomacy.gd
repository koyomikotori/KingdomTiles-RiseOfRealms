class_name RealmDiplomacy
extends RefCounted
## Diplomacy between the kingdom and the nations, and between the nations (GDD §37, M18f-b2b).
## Owned by Realm (`diplomacy`); takes the realm and state as arguments.
##
## Every pair of parties (Realm.PLAYER and each nation still standing) has a pact (Pact) and a
## relation −100 … 100: a `base` that drifts DRIFT a turn toward the sum of the lasting factors
## (factors()), plus a `memory` of events that fades MEMORY_FADE a turn. Only parties at war fight
## (sieges, attacks, interceptions); the rebels are at war with everyone.
##
## The kingdom starts at war with every nation. At the start the strongest nation forms a bloc
## against us with its nearest neighbors (BLOC_SIZE by difficulty): bloc members are allied, go to
## war and make peace with us together, and leave the bloc when wariness of a strong member drags
## their relation below BLOC_LEAVE. Peace and alliances are asked through an envoy advisor, who is
## away until the turn ends.

enum Pact { WAR, PEACE, NEUTRAL, NAP, ALLIANCE }
enum Result { OK, NOT_LIVE, AT_WAR, NOT_AT_WAR, REFUSED_RECENTLY, NO_ADVISOR, ADVISOR_BUSY, TOO_LOW, IN_BLOC,
		ENEMY_OF_ALLY, ALREADY, TOO_SOON, CANNOT_AFFORD }

const PACT_NAMES: Array[String] = ["Chiến tranh", "Hòa ước", "Trung lập", "Bất tương xâm", "Liên minh"]

## Relation: drift toward the factors a turn, events fade a turn.
const DRIFT := 3.0
const MEMORY_FADE := 2.0
## Lasting factors by pact.
const PACT_FACTOR: Array[int] = [-40, 10, 0, 20, 40]
const COMMON_ENEMY := 15
const COMMON_ENEMY_MAX := 30
## Wariness of a party holding more towns than the parties' average.
const WARY_PER_TOWN := 10.0
const WARY_MAX := 40
## Events.
const FIGHT_TOGETHER := 5.0
const VISIT_BASE := 5.0
const VISIT_COOLDOWN := 5
const ATTACK_FRIEND := -15.0
const BREAK_VICTIM := -30.0
const BREAK_OTHERS := -10.0
## Treaties (turns) and asking again.
const PEACE_TURNS := 15
const NAP_TURNS := 15
const ALLIANCE_TURNS := 20
const RENEW_WINDOW := 5
const REFUSE_WAIT := 3
const NAP_MIN := 20
const ALLIANCE_MIN := 60
## Bloc against us by difficulty (members; 0 = none, capped by the nations standing).
const BLOC_SIZE: Array[int] = [0, 2, 3, 99]
const BLOC_LEAVE := 20
## Wars: a neutral nation declares on us at HATE or (below 0) when STRONGER × our strength; two
## nations at AI_HATE or (below BLOC_LEAVE) STRONGER × the other's strength. A truce after a
## peace ends with a relation at AI_HATE or below breaks into war again.
const HATE := -60
const AI_HATE := -20
const STRONGER := 2.0
## Two nations at war AI_PEACE_AFTER turns without taking a town make peace AI_PEACE_CHANCE a turn.
const AI_PEACE_AFTER := 10
const AI_PEACE_CHANCE := 0.1
## Asking for peace.
const PEACE_BASE := 0.1
const PEACE_PER_TOWN := 0.15
const PEACE_STRENGTH := 0.2
const PEACE_STRENGTH_MIN := -0.2
const PEACE_STRENGTH_MAX := 0.4
const PEACE_PER_WAR_TURN := 0.01
const PEACE_WAR_TURNS_MAX := 0.2
const PEACE_PER_DIPLOMACY := 0.02
const PEACE_GOODS_STEP := 100
const PEACE_PER_GOODS_STEP := 0.05
const PEACE_GOODS_MAX := 0.3
const PEACE_RETURN_TOWN := 0.35
const PEACE_MAX := 0.9
## Asking for an alliance.
const ALLIANCE_BASE := 0.3
const ALLIANCE_PER_RELATION := 1.0 / 80.0
const ALLIANCE_PER_DIPLOMACY := 0.02
const ALLIANCE_MAX := 0.95
## Goods sent with a peace offer: shares of the value in food, wood and stone.
const GOODS_SHARES: Dictionary[StringName, float] = {&"food": 0.3, &"wood": 0.3, &"stone": 0.4}
const GOODS_VALUES: Dictionary[StringName, int] = {&"food": 1, &"wood": 1, &"stone": 2}


class Pair:
	extends RefCounted
	var pact := Pact.WAR
	## Turns left of a peace / non-aggression / alliance; 0 never ends (a bloc's alliance).
	var turns := 0
	var base := 0.0
	var memory := 0.0
	var war_since := 0
	var last_capture := -100
	## The kingdom may ask again from this turn (after a refusal).
	var asked_after := 0
	var visit_turn := -100

	func relation() -> int:
		return clampi(roundi(base + memory), -100, 100)

	func to_save() -> Dictionary:
		return {"pact": pact, "turns": turns, "base": base, "memory": memory, "war_since": war_since,
				"capture": last_capture, "asked": asked_after, "visit": visit_turn}

	static func from_save(data: Dictionary) -> Pair:
		var pair := Pair.new()
		pair.pact = int(data.get("pact", Pact.WAR)) as Pact
		pair.turns = int(data.get("turns", 0))
		pair.base = float(data.get("base", 0.0))
		pair.memory = float(data.get("memory", 0.0))
		pair.war_since = int(data.get("war_since", 0))
		pair.last_capture = int(data.get("capture", -100))
		pair.asked_after = int(data.get("asked", 0))
		pair.visit_turn = int(data.get("visit", -100))
		return pair


var pairs: Dictionary = {}  # "a|b" (sorted) -> Pair
var bloc: Array[StringName] = []
## Advisors away as envoys until the turn ends.
var envoys: Array[Advisor] = []


static func key(a: StringName, b: StringName) -> String:
	return "%s|%s" % [a, b] if String(a) < String(b) else "%s|%s" % [b, a]


func pair(a: StringName, b: StringName) -> Pair:
	var k := key(a, b)
	if not pairs.has(k):
		pairs[k] = Pair.new()
	return pairs[k]


## The kingdom and every nation still standing.
static func parties(realm: Realm) -> Array[StringName]:
	var result: Array[StringName] = [Realm.PLAYER]
	for nation in RealmWar.live_nations(realm):
		result.append(nation.id)
	return result


func pact(a: StringName, b: StringName) -> Pact:
	return pair(a, b).pact


## Whether `a` and `b` fight each other (the rebels fight everyone).
func at_war(a: StringName, b: StringName) -> bool:
	if a == b:
		return false
	if a == Realm.REBELS or b == Realm.REBELS:
		return true
	return pair(a, b).pact == Pact.WAR


func relation(a: StringName, b: StringName) -> int:
	return pair(a, b).relation()


func allied(a: StringName, b: StringName) -> bool:
	return a != b and a != Realm.REBELS and b != Realm.REBELS and pair(a, b).pact == Pact.ALLIANCE


## The nations allied with the kingdom (not the bloc against it).
func allies_of_player(realm: Realm) -> Array[StringName]:
	var result: Array[StringName] = []
	for id in parties(realm):
		if id != Realm.PLAYER and allied(Realm.PLAYER, id):
			result.append(id)
	return result


func in_bloc(id: StringName) -> bool:
	return bloc.has(id)


# --- Start ---------------------------------------------------------------------------------

## War with everyone, the bloc formed by difficulty, every relation at its factors.
func start(realm: Realm, state: KingdomState) -> void:
	pairs.clear()
	envoys.clear()
	bloc = form_bloc(realm, state, state.difficulty)
	var ids := parties(realm)
	for i in ids.size():
		for j in range(i + 1, ids.size()):
			var p := pair(ids[i], ids[j])
			p.war_since = state.turn
			if bloc.has(ids[i]) and bloc.has(ids[j]):
				p.pact = Pact.ALLIANCE
				p.turns = 0
	for i in ids.size():
		for j in range(i + 1, ids.size()):
			pair(ids[i], ids[j]).base = target(realm, state, ids[i], ids[j])


## The strongest nation (on a tie the nearest to us) and its nearest neighbors.
static func form_bloc(realm: Realm, state: KingdomState, difficulty: int) -> Array[StringName]:
	var size := mini(BLOC_SIZE[clampi(difficulty, 0, BLOC_SIZE.size() - 1)], RealmWar.live_nations(realm).size())
	var result: Array[StringName] = []
	if size < 2:
		return result
	var leader: Realm.Nation = null
	for nation in RealmWar.live_nations(realm):
		if leader == null or power(realm, state, nation.id) > power(realm, state, leader.id) \
				or (power(realm, state, nation.id) == power(realm, state, leader.id) and nation.distance() < leader.distance()):
			leader = nation
	result.append(leader.id)
	var others := RealmWar.live_nations(realm).filter(func(n: Realm.Nation) -> bool: return n != leader)
	var leader_cell := RealmMap.region_cell(leader.region)
	others.sort_custom(func(a: Realm.Nation, b: Realm.Nation) -> bool:
		var da := _cells(leader_cell, RealmMap.region_cell(a.region))
		var db := _cells(leader_cell, RealmMap.region_cell(b.region))
		return da < db or (da == db and a.distance() < b.distance()))
	for nation: Realm.Nation in others.slice(0, size - 1):
		result.append(nation.id)
	return result


static func _cells(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)


# --- Strength and relation ---------------------------------------------------------------

## Soldiers a party has: the kingdom's whole army and its vassals' armies; a nation's armies and
## garrisons.
static func power(realm: Realm, state: KingdomState, id: StringName) -> int:
	var total := 0
	if id == Realm.PLAYER:
		for squad in state.army.squads:
			total += squad.soldiers
		for nation in realm.vassals():
			for army in realm.armies_of(nation.id):
				total += army.soldiers
		return total
	for army in realm.armies_of(id):
		total += army.soldiers
	for town in realm.towns:
		if town.owner == id:
			total += town.garrison
	return total


## Whether a town of `a` borders a town of `b`.
static func borders(realm: Realm, a: StringName, b: StringName) -> bool:
	for town in realm.towns:
		if town.owner != a:
			continue
		for id in RealmMap.neighbors(town.id):
			if realm.towns[id].owner == b:
				return true
	return false


static func name_of(realm: Realm, id: StringName) -> String:
	if id == Realm.PLAYER:
		return "ta"
	return realm.nations[id].name if realm.nations.has(id) else String(id)


## The lasting factors of the relation between `a` and `b`: [{"text", "value"}].
func factors(realm: Realm, state: KingdomState, a: StringName, b: StringName) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var p := pair(a, b)
	var pact_text := PACT_NAMES[p.pact]
	if p.pact == Pact.ALLIANCE and p.turns == 0:
		pact_text = "Cùng khối"
	if PACT_FACTOR[p.pact] != 0:
		result.append({"text": pact_text, "value": PACT_FACTOR[p.pact]})
	var ids := parties(realm)
	var common := 0
	for c in ids:
		if c != a and c != b and at_war(a, c) and at_war(b, c):
			common += COMMON_ENEMY
	if common > 0:
		result.append({"text": "Kẻ thù chung", "value": mini(common, COMMON_ENEMY_MAX)})
	var average := 0.0
	for id in ids:
		average += realm.count_owned(id)
	average /= maxf(1.0, ids.size())
	var bigger := a if realm.count_owned(a) >= realm.count_owned(b) else b
	var wary := mini(WARY_MAX, roundi(WARY_PER_TOWN * maxf(0.0, realm.count_owned(bigger) - average)))
	if wary > 0:
		var who := "vương quốc ta" if bigger == Realm.PLAYER else name_of(realm, bigger)
		result.append({"text": "E dè %s lớn mạnh" % who, "value": -wary})
	return result


func target(realm: Realm, state: KingdomState, a: StringName, b: StringName) -> float:
	var total := 0
	for factor in factors(realm, state, a, b):
		total += int(factor.value)
	return float(total)


static func tier_name(value: int) -> String:
	var tier := 0
	for threshold in Diplomacy.TIER_THRESHOLDS:
		if value >= threshold:
			tier += 1
	return Diplomacy.TIER_NAMES[tier]


## A short status of the pact between the kingdom and `nation_id` ("Hòa ước 12", "Khối chống ta" …).
func status_text(nation_id: StringName) -> String:
	var p := pair(Realm.PLAYER, nation_id)
	if p.pact == Pact.WAR:
		return "Khối chống ta" if bloc.has(nation_id) else "Chiến tranh"
	if p.pact == Pact.NEUTRAL:
		return PACT_NAMES[p.pact]
	return "%s %d" % [PACT_NAMES[p.pact], p.turns]


func add_memory(a: StringName, b: StringName, amount: float) -> void:
	if a == b or a == Realm.REBELS or b == Realm.REBELS:
		return
	pair(a, b).memory += amount


# --- Changing pacts ------------------------------------------------------------------------

## Sets the pact between `a` and `b`; ending a war calls off every attack between them.
func set_pact(realm: Realm, state: KingdomState, a: StringName, b: StringName, new_pact: Pact, turns: int = 0) -> void:
	var p := pair(a, b)
	var was_war := p.pact == Pact.WAR
	p.pact = new_pact
	p.turns = turns
	if new_pact == Pact.WAR and not was_war:
		p.war_since = state.turn
	if new_pact != Pact.WAR:
		_call_off(realm, a, b)
		_call_off(realm, b, a)


## Orders of `a` against `b` are cancelled.
func _call_off(realm: Realm, a: StringName, b: StringName) -> void:
	for army in realm.armies:
		var side := Realm.PLAYER if realm.is_ally(army) else army.nation
		if side == a and army.has_target() and realm.towns[army.target].owner == b:
			army.target = -1
	if a == Realm.PLAYER:
		for force in realm.forces:
			if force.order == Realm.SIEGE and force.target >= 0 and realm.towns[force.target].owner == b:
				realm.cancel_order(force)
			elif force.order == Realm.INTERCEPT:
				var army := realm.army_by_id(force.army)
				if army == null or army.nation == b:
					realm.cancel_order(force)
	if b == Realm.PLAYER:
		var kept: Array[Dictionary] = []
		for entry in realm.pending_attacks:
			var armies := realm.attack_armies(entry)
			if armies.is_empty() or armies[0].nation != a:
				kept.append(entry)
		realm.pending_attacks = kept


## `by` declares war on `on`. Breaking a treaty angers the other side and everyone else; a bloc
## goes to war with us together.
func declare_war(realm: Realm, state: KingdomState, by: StringName, on: StringName) -> Array[StringName]:
	var at_war_with: Array[StringName] = []
	var p := pair(by, on)
	if p.pact == Pact.WAR:
		return at_war_with
	if p.pact in [Pact.PEACE, Pact.NAP, Pact.ALLIANCE]:
		add_memory(by, on, BREAK_VICTIM)
		for id in parties(realm):
			if id != by and id != on:
				add_memory(by, id, BREAK_OTHERS)
	set_pact(realm, state, by, on, Pact.WAR)
	at_war_with.append(on)
	# A bloc nation at war with us brings the whole bloc.
	for side in [by, on]:
		var other: StringName = on if side == by else by
		if other == Realm.PLAYER and bloc.has(side):
			for member in bloc:
				if member != side and not at_war(member, Realm.PLAYER):
					set_pact(realm, state, member, Realm.PLAYER, Pact.WAR)
					at_war_with.append(member)
	return at_war_with


## A town of `owner` was taken by `by` (AI peace waits for a quiet war).
func note_capture(by: StringName, owner: StringName, turn: int) -> void:
	if by == owner or by == Realm.REBELS or owner == Realm.REBELS:
		return
	pair(by, owner).last_capture = turn


## We attacked a town of `owner`: its bloc mates take it badly.
func note_player_attack(realm: Realm, owner: StringName) -> void:
	if owner == Realm.REBELS or owner == Realm.PLAYER:
		return
	for id in parties(realm):
		if id != Realm.PLAYER and id != owner and allied(id, owner):
			add_memory(Realm.PLAYER, id, ATTACK_FRIEND)


## A nation is gone (destroyed or, later, submitted): it leaves the bloc.
func remove(nation_id: StringName) -> void:
	bloc.erase(nation_id)
	if bloc.size() < 2:
		bloc.clear()


# --- Turns ---------------------------------------------------------------------------------

## End of a turn: envoys come home, treaties tick, relations drift, the bloc may break, nations
## declare war or make peace. Returns the news lines.
func end_turn(realm: Realm, state: KingdomState) -> Array[String]:
	var news: Array[String] = []
	for advisor in envoys:
		Realm._set_away(advisor, false)
	envoys.clear()
	for id in bloc.duplicate():
		if not realm.nations.has(id) or realm.nations[id].destroyed:
			remove(id)
	var ids := parties(realm)
	var targets := {}
	for i in ids.size():
		for j in range(i + 1, ids.size()):
			targets[key(ids[i], ids[j])] = target(realm, state, ids[i], ids[j])
	for i in ids.size():
		for j in range(i + 1, ids.size()):
			var a := ids[i]
			var b := ids[j]
			var p := pair(a, b)
			p.base = move_toward(p.base, targets[key(a, b)], DRIFT)
			p.memory = move_toward(p.memory, 0.0, MEMORY_FADE)
			if p.pact in [Pact.PEACE, Pact.NAP, Pact.ALLIANCE] and p.turns > 0:
				p.turns -= 1
				if p.turns == 0:
					news.append_array(_expire(realm, state, a, b))
			if p.pact == Pact.ALLIANCE and p.turns > 0 and p.relation() < NAP_MIN:
				set_pact(realm, state, a, b, Pact.NEUTRAL)
				news.append("Liên minh giữa %s và %s tan vì quan hệ sa sút." % [name_of(realm, a), name_of(realm, b)])
	news.append_array(_bloc_breakup(realm, state))
	news.append_array(_declarations(realm, state))
	news.append_array(_ai_peace(realm, state))
	return news


func _expire(realm: Realm, state: KingdomState, a: StringName, b: StringName) -> Array[String]:
	var p := pair(a, b)
	var old := p.pact
	var involves_us := a == Realm.PLAYER or b == Realm.PLAYER
	var other := b if a == Realm.PLAYER else a
	if old == Pact.PEACE and p.relation() <= AI_HATE:
		# Neutral first: the war that follows breaks no treaty (but brings a bloc along).
		set_pact(realm, state, a, b, Pact.NEUTRAL)
		declare_war(realm, state, a, b)
		if involves_us:
			return ["Hòa ước với %s hết hạn: họ tuyên chiến lại!" % name_of(realm, other)]
		return ["Hòa ước giữa %s và %s hết hạn: chiến tranh lại nổ ra." % [name_of(realm, a), name_of(realm, b)]]
	set_pact(realm, state, a, b, Pact.NEUTRAL)
	if not involves_us:
		return []
	return ["%s với %s hết hạn, nay trung lập." % [PACT_NAMES[old], name_of(realm, other)]]


## Bloc mates whose relation fell below BLOC_LEAVE: the weaker leaves.
func _bloc_breakup(realm: Realm, state: KingdomState) -> Array[String]:
	var news: Array[String] = []
	var changed := true
	while changed and bloc.size() >= 2:
		changed = false
		for i in bloc.size():
			for j in range(i + 1, bloc.size()):
				if relation(bloc[i], bloc[j]) >= BLOC_LEAVE:
					continue
				var a := bloc[i]
				var b := bloc[j]
				var leaving := a if power(realm, state, a) < power(realm, state, b) else b
				var stronger := b if leaving == a else a
				for member in bloc:
					if member != leaving and pair(leaving, member).pact == Pact.ALLIANCE:
						set_pact(realm, state, leaving, member, Pact.NEUTRAL)
				bloc.erase(leaving)
				news.append("%s nghi kỵ %s lớn mạnh, rời khối liên minh chống ta." % [name_of(realm, leaving),
						name_of(realm, stronger)])
				if bloc.size() < 2:
					bloc.clear()
					news.append("Khối liên minh chống ta tan rã.")
				changed = true
				break
			if changed:
				break
	return news


## Neutral parties that hate each other or see the other weak go to war.
func _declarations(realm: Realm, state: KingdomState) -> Array[String]:
	var news: Array[String] = []
	var ids := parties(realm)
	for i in ids.size():
		for j in range(i + 1, ids.size()):
			var a := ids[i]
			var b := ids[j]
			var p := pair(a, b)
			if p.pact != Pact.NEUTRAL:
				continue
			var rel := p.relation()
			if a == Realm.PLAYER or b == Realm.PLAYER:
				var nation := b if a == Realm.PLAYER else a
				var strong := power(realm, state, nation) >= STRONGER * power(realm, state, Realm.PLAYER) \
						and borders(realm, nation, Realm.PLAYER)
				if rel <= HATE or (rel < 0 and strong):
					var joined := declare_war(realm, state, nation, Realm.PLAYER)
					news.append("%s tuyên chiến với ta!%s" % [name_of(realm, nation),
							"" if joined.size() <= 1 else " Cả khối liên minh theo họ."])
				continue
			if not borders(realm, a, b):
				continue
			var by := a if power(realm, state, a) >= power(realm, state, b) else b
			var on := b if by == a else a
			if rel <= AI_HATE or (rel < BLOC_LEAVE and power(realm, state, by) >= STRONGER * power(realm, state, on)):
				declare_war(realm, state, by, on)
				news.append("%s tuyên chiến với %s." % [name_of(realm, by), name_of(realm, on)])
	return news


## Long quiet wars between nations may end in peace.
func _ai_peace(realm: Realm, state: KingdomState) -> Array[String]:
	var news: Array[String] = []
	var ids := parties(realm)
	for i in ids.size():
		for j in range(i + 1, ids.size()):
			var a := ids[i]
			var b := ids[j]
			if a == Realm.PLAYER or b == Realm.PLAYER:
				continue
			var p := pair(a, b)
			if p.pact != Pact.WAR or state.turn - p.war_since < AI_PEACE_AFTER \
					or state.turn - p.last_capture < AI_PEACE_AFTER:
				continue
			if realm.rng.randf() < AI_PEACE_CHANCE:
				set_pact(realm, state, a, b, Pact.PEACE, PEACE_TURNS)
				news.append("%s và %s ký hòa ước." % [name_of(realm, a), name_of(realm, b)])
	return news


# --- The kingdom's diplomacy ---------------------------------------------------------------

func _live(realm: Realm, nation_id: StringName) -> bool:
	return realm.nations.has(nation_id) and nation_id != Realm.REBELS and not realm.nations[nation_id].destroyed


func _check_envoy(advisor: Advisor, state: KingdomState) -> Result:
	if advisor == null or not state.advisors.advisors.has(advisor):
		return Result.NO_ADVISOR
	if not advisor.is_ready():
		return Result.ADVISOR_BUSY
	return Result.OK


func _send(advisor: Advisor, nation_name: String) -> void:
	Realm._set_away(advisor, true, "đi sứ %s" % nation_name)
	envoys.append(advisor)


## The nations a peace with `nation_id` covers: its whole bloc when it is in one.
func peace_party(realm: Realm, nation_id: StringName) -> Array[StringName]:
	if not bloc.has(nation_id):
		return [nation_id]
	var result: Array[StringName] = []
	for member in bloc:
		if at_war(member, Realm.PLAYER):
			result.append(member)
	return result


## Towns of `nation_id`'s land we hold (the peace offer may hand one back).
static func held_towns(realm: Realm, nation_id: StringName) -> Array[Realm.Town]:
	var result: Array[Realm.Town] = []
	for town in realm.towns:
		if town.nation == nation_id and town.owner == Realm.PLAYER:
			result.append(town)
	return result


## The town a peace offer would hand back: a held town of theirs with none of our armies, not a
## capital when possible; -1 when none.
static func town_to_return(realm: Realm, nation_id: StringName) -> int:
	var best := -1
	for town in held_towns(realm, nation_id):
		if not realm.forces_at(town.id).is_empty():
			continue
		if best < 0 or (realm.towns[best].is_capital() and not town.is_capital()):
			best = town.id
	return best


## Food / wood / stone worth `value` (GOODS_SHARES).
static func goods_for(value: int) -> Dictionary[StringName, int]:
	var result: Dictionary[StringName, int] = {}
	if value <= 0:
		return result
	for resource_id in GOODS_SHARES:
		result[resource_id] = roundi(value * GOODS_SHARES[resource_id] / GOODS_VALUES[resource_id])
	return result


func check_peace(realm: Realm, state: KingdomState, nation_id: StringName, advisor: Advisor, goods_value: int = 0) -> Result:
	if not _live(realm, nation_id):
		return Result.NOT_LIVE
	if not at_war(Realm.PLAYER, nation_id):
		return Result.NOT_AT_WAR
	if state.turn < pair(Realm.PLAYER, nation_id).asked_after:
		return Result.REFUSED_RECENTLY
	if goods_value > 0 and not state.stockpile.can_afford(goods_for(goods_value)):
		return Result.CANNOT_AFFORD
	return _check_envoy(advisor, state)


## The chance one nation accepts peace.
func _peace_chance_of(realm: Realm, state: KingdomState, nation_id: StringName, diplomacy_points: int) -> float:
	var p := pair(Realm.PLAYER, nation_id)
	var chance := PEACE_BASE + PEACE_PER_TOWN * held_towns(realm, nation_id).size()
	var ratio := float(power(realm, state, Realm.PLAYER)) / maxf(1.0, power(realm, state, nation_id))
	chance += clampf(PEACE_STRENGTH * (ratio - 1.0), PEACE_STRENGTH_MIN, PEACE_STRENGTH_MAX)
	chance += minf(PEACE_WAR_TURNS_MAX, PEACE_PER_WAR_TURN * (state.turn - p.war_since))
	chance += PEACE_PER_DIPLOMACY * diplomacy_points
	chance += p.relation() / 400.0
	return chance


## The chance the peace offer is accepted (by every nation it covers): 0 … PEACE_MAX.
func peace_chance(realm: Realm, state: KingdomState, nation_id: StringName, advisor: Advisor, goods_value: int = 0,
		return_town: bool = false) -> float:
	var points := advisor.stat_for(&"diplomacy") if advisor != null else 0
	var chance := 1.0
	for member in peace_party(realm, nation_id):
		chance = minf(chance, _peace_chance_of(realm, state, member, points))
	chance += minf(PEACE_GOODS_MAX, PEACE_PER_GOODS_STEP * floori(float(goods_value) / PEACE_GOODS_STEP))
	if return_town and town_to_return(realm, nation_id) >= 0:
		chance += PEACE_RETURN_TOWN
	return clampf(chance, 0.0, PEACE_MAX)


## Sends `advisor` to ask `nation_id` (and its bloc) for peace. Returns {"result", "accepted",
## "chance", "nations": [ids], "returned": town id or -1}.
func ask_peace(realm: Realm, state: KingdomState, nation_id: StringName, advisor: Advisor, goods_value: int = 0,
		return_town: bool = false) -> Dictionary:
	var result := check_peace(realm, state, nation_id, advisor, goods_value)
	if result != Result.OK:
		return {"result": result, "accepted": false}
	var chance := peace_chance(realm, state, nation_id, advisor, goods_value, return_town)
	var members := peace_party(realm, nation_id)
	_send(advisor, name_of(realm, nation_id))
	if realm.rng.randf() >= chance:
		for member in members:
			pair(Realm.PLAYER, member).asked_after = state.turn + REFUSE_WAIT
		return {"result": result, "accepted": false, "chance": chance, "nations": members, "returned": -1}
	if goods_value > 0:
		state.stockpile.spend(goods_for(goods_value))
	var returned := town_to_return(realm, nation_id) if return_town else -1
	if returned >= 0:
		realm._lose_town(state, realm.towns[returned], 0, false, nation_id)
		realm.towns[returned].garrison = realm.towns[returned].max_garrison / 2
	for member in members:
		set_pact(realm, state, Realm.PLAYER, member, Pact.PEACE, PEACE_TURNS)
	return {"result": result, "accepted": true, "chance": chance, "nations": members, "returned": returned}


func check_nap(realm: Realm, state: KingdomState, nation_id: StringName) -> Result:
	if not _live(realm, nation_id):
		return Result.NOT_LIVE
	var p := pair(Realm.PLAYER, nation_id)
	if p.pact == Pact.WAR:
		return Result.AT_WAR
	if p.pact == Pact.ALLIANCE or (p.pact == Pact.NAP and p.turns > RENEW_WINDOW):
		return Result.ALREADY
	if p.relation() < NAP_MIN:
		return Result.TOO_LOW
	return Result.OK


## A non-aggression pact (always accepted), or a renewal in its last turns.
func sign_nap(realm: Realm, state: KingdomState, nation_id: StringName) -> Result:
	var result := check_nap(realm, state, nation_id)
	if result == Result.OK:
		var p := pair(Realm.PLAYER, nation_id)
		set_pact(realm, state, Realm.PLAYER, nation_id, Pact.NAP, (p.turns if p.pact == Pact.NAP else 0) + NAP_TURNS)
	return result


func check_alliance(realm: Realm, state: KingdomState, nation_id: StringName, advisor: Advisor) -> Result:
	if not _live(realm, nation_id):
		return Result.NOT_LIVE
	var p := pair(Realm.PLAYER, nation_id)
	if p.pact == Pact.WAR:
		return Result.AT_WAR
	if bloc.has(nation_id):
		return Result.IN_BLOC
	if p.pact == Pact.ALLIANCE and p.turns > RENEW_WINDOW:
		return Result.ALREADY
	if p.relation() < ALLIANCE_MIN:
		return Result.TOO_LOW
	for ally in allies_of_player(realm):
		if ally != nation_id and at_war(ally, nation_id):
			return Result.ENEMY_OF_ALLY
	if state.turn < p.asked_after:
		return Result.REFUSED_RECENTLY
	return _check_envoy(advisor, state)


func alliance_chance(realm: Realm, nation_id: StringName, advisor: Advisor) -> float:
	var points := advisor.stat_for(&"diplomacy") if advisor != null else 0
	return clampf(ALLIANCE_BASE + (relation(Realm.PLAYER, nation_id) - ALLIANCE_MIN) * ALLIANCE_PER_RELATION
			+ ALLIANCE_PER_DIPLOMACY * points, 0.0, ALLIANCE_MAX)


## The nations an alliance with `nation_id` takes us to war with (its enemies), and the ones it
## takes them to war with (ours).
func alliance_wars(realm: Realm, nation_id: StringName) -> Dictionary:
	var ours: Array[StringName] = []
	var theirs: Array[StringName] = []
	for id in parties(realm):
		if id == Realm.PLAYER or id == nation_id:
			continue
		if at_war(nation_id, id) and not at_war(Realm.PLAYER, id):
			ours.append(id)
		if at_war(Realm.PLAYER, id) and not at_war(nation_id, id):
			theirs.append(id)
	return {"ours": ours, "theirs": theirs}


## Asks for an alliance (or its renewal). Returns {"result", "accepted", "chance", "wars"}.
func ask_alliance(realm: Realm, state: KingdomState, nation_id: StringName, advisor: Advisor) -> Dictionary:
	var result := check_alliance(realm, state, nation_id, advisor)
	if result != Result.OK:
		return {"result": result, "accepted": false}
	var chance := alliance_chance(realm, nation_id, advisor)
	var p := pair(Realm.PLAYER, nation_id)
	_send(advisor, name_of(realm, nation_id))
	if realm.rng.randf() >= chance:
		p.asked_after = state.turn + REFUSE_WAIT
		return {"result": result, "accepted": false, "chance": chance}
	var renewal := p.pact == Pact.ALLIANCE
	var wars := alliance_wars(realm, nation_id)
	set_pact(realm, state, Realm.PLAYER, nation_id, Pact.ALLIANCE, (p.turns if renewal else 0) + ALLIANCE_TURNS)
	if not renewal:
		for id: StringName in wars.ours:
			set_pact(realm, state, Realm.PLAYER, id, Pact.WAR)
		for id: StringName in wars.theirs:
			set_pact(realm, state, nation_id, id, Pact.WAR)
	return {"result": result, "accepted": true, "chance": chance, "wars": wars}


func check_visit(realm: Realm, state: KingdomState, nation_id: StringName, advisor: Advisor) -> Result:
	if not _live(realm, nation_id):
		return Result.NOT_LIVE
	if state.turn - pair(Realm.PLAYER, nation_id).visit_turn < VISIT_COOLDOWN:
		return Result.TOO_SOON
	return _check_envoy(advisor, state)


static func visit_gain(advisor: Advisor) -> float:
	return VISIT_BASE + (advisor.stat_for(&"diplomacy") if advisor != null else 0) / 2.0


## An envoy's courtesy visit: the relation rises at once (fading like any event).
func visit(realm: Realm, state: KingdomState, nation_id: StringName, advisor: Advisor) -> Result:
	var result := check_visit(realm, state, nation_id, advisor)
	if result == Result.OK:
		var p := pair(Realm.PLAYER, nation_id)
		p.memory += visit_gain(advisor)
		p.visit_turn = state.turn
		_send(advisor, name_of(realm, nation_id))
	return result


func check_declare(realm: Realm, nation_id: StringName) -> Result:
	if not _live(realm, nation_id):
		return Result.NOT_LIVE
	if at_war(Realm.PLAYER, nation_id):
		return Result.AT_WAR
	return Result.OK


## Breaks a treaty when there is one (BREAK_VICTIM / BREAK_OTHERS). Returns the nations now at war.
func player_declares(realm: Realm, state: KingdomState, nation_id: StringName) -> Array[StringName]:
	if check_declare(realm, nation_id) != Result.OK:
		return []
	return declare_war(realm, state, Realm.PLAYER, nation_id)


## Leaving an alliance is breaking a treaty; the nation becomes neutral.
func cancel_alliance(realm: Realm, state: KingdomState, nation_id: StringName) -> Result:
	if not allied(Realm.PLAYER, nation_id) or bloc.has(nation_id):
		return Result.NOT_LIVE
	add_memory(Realm.PLAYER, nation_id, BREAK_VICTIM)
	for id in parties(realm):
		if id != Realm.PLAYER and id != nation_id:
			add_memory(Realm.PLAYER, id, BREAK_OTHERS)
	set_pact(realm, state, Realm.PLAYER, nation_id, Pact.NEUTRAL)
	return Result.OK


static func describe(result: Result) -> String:
	match result:
		Result.NOT_LIVE:
			return "Nước này không còn."
		Result.AT_WAR:
			return "Đang chiến tranh: phải cầu hòa trước."
		Result.NOT_AT_WAR:
			return "Không chiến tranh với nước này."
		Result.REFUSED_RECENTLY:
			return "Họ vừa từ chối; đợi vài lượt rồi hỏi lại."
		Result.NO_ADVISOR:
			return "Chọn một mưu sĩ đi sứ."
		Result.ADVISOR_BUSY:
			return "Mưu sĩ này đang bận hoặc bị thương."
		Result.TOO_LOW:
			return "Quan hệ chưa đủ."
		Result.IN_BLOC:
			return "Họ ở khối liên minh chống ta."
		Result.ENEMY_OF_ALLY:
			return "Họ đang chiến tranh với đồng minh của ta."
		Result.ALREADY:
			return "Đã có hiệp ước này (gia hạn được trong %d lượt cuối)." % RENEW_WINDOW
		Result.TOO_SOON:
			return "Vừa thăm hỏi gần đây; %d lượt mới thăm lại được." % VISIT_COOLDOWN
		Result.CANNOT_AFFORD:
			return "Không đủ hàng kèm theo."
	return ""


# --- Save ----------------------------------------------------------------------------------

func to_save(state: KingdomState) -> Dictionary:
	var pair_saves := {}
	for k in pairs:
		pair_saves[k] = pairs[k].to_save()
	return {"pairs": pair_saves, "bloc": bloc.map(func(id: StringName) -> String: return String(id)),
			"envoys": envoys.map(func(advisor: Advisor) -> int: return state.advisors.advisors.find(advisor))}


func load_save(data: Dictionary, state: KingdomState) -> void:
	pairs.clear()
	bloc.clear()
	envoys.clear()
	var pair_saves: Dictionary = data.get("pairs", {})
	for k: String in pair_saves:
		pairs[k] = Pair.from_save(pair_saves[k])
	for id in data.get("bloc", []):
		bloc.append(StringName(id))
	for index in data.get("envoys", []):
		if int(index) >= 0 and int(index) < state.advisors.advisors.size():
			envoys.append(state.advisors.advisors[int(index)])
