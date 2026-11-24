class_name RealmVassals
extends RefCounted
## The vassals' side of the realm war (GDD §36, M18f-b2a), run by Realm.end_turn before the
## nations act. A vassal king rules a destroyed nation's land for us (the towns stay ours): it
## gathers a fixed treasury from the towns of its land we hold (as RealmWar on Normal, whatever
## the difficulty), raises armies (NationArmy of its nation, generals one star below the king),
## lets them rest in its towns, intercepts enemy armies about to strike its land, and attacks the
## enemy towns next to it when twice as strong (announced a turn ahead, fought at once like the
## nations' own fights); a town it takes becomes ours. Static.

## The full strength of a vassal's army and its general's stars below the king's.
const ARMY_SIZE := 280
const STARS_BELOW_KING := 1
## Vassal armies intercept an enemy army about to strike their land when this many times as strong.
const INTERCEPT_RATIO := 1.2
## Treasury income is RealmWar's at this difficulty multiplier (Normal).
const INCOME_FACTOR := 1.0


static func raise_army(realm: Realm, state: KingdomState, nation: Realm.Nation) -> NationArmy:
	var land := realm.region_towns(nation.region)
	if land.is_empty():
		return null
	var home := land[0]
	for town in land:
		if town.is_capital():
			home = town
	var army := NationArmy.new()
	army.id = realm.next_army_id
	realm.next_army_id += 1
	army.nation = nation.id
	army.general = state.generals.generate(clampi(nation.vassal.stars - STARS_BELOW_KING, 1, RealmWar.MAX_STARS))
	army.max_soldiers = ARMY_SIZE
	army.soldiers = ARMY_SIZE
	army.town = home.id
	realm.armies.append(army)
	return army


static func income(realm: Realm, nation: Realm.Nation) -> float:
	var total := 0.0
	for town in realm.region_towns(nation.region):
		total += RealmWar.CAPITAL_INCOME if town.is_capital() else RealmWar.TOWN_INCOME
	return total * INCOME_FACTOR


## The vassals' turn. Returns the news lines.
static func run_turn(realm: Realm, state: KingdomState) -> Array[String]:
	var news: Array[String] = []
	for nation in realm.vassals():
		var land := realm.region_towns(nation.region)
		if land.is_empty():
			continue
		var treasury: float = realm.treasury.get(nation.id, 0.0) + income(realm, nation)
		if treasury >= RealmWar.ARMY_COST and realm.armies_of(nation.id).size() < RealmWar.max_armies(land.size()):
			treasury -= RealmWar.ARMY_COST
			raise_army(realm, state, nation)
		realm.treasury[nation.id] = minf(treasury, RealmWar.MAX_TREASURY)
		for army in realm.armies_of(nation.id):
			if realm.towns[army.town].owner == Realm.PLAYER and army.soldiers < army.max_soldiers:
				army.soldiers = mini(army.max_soldiers, army.soldiers + ceili(army.max_soldiers * RealmWar.ARMY_REGEN))
		news.append_array(_intercept(realm, state, nation))
		news.append_array(_attack(realm, state, nation))
		_new_orders(realm, nation, state.turn)
	return news


## Enemy armies about to strike a town of the vassal's land (announced on an earlier turn) meet
## the vassal's armies standing next to them when those are INTERCEPT_RATIO as strong.
static func _intercept(realm: Realm, state: KingdomState, nation: Realm.Nation) -> Array[String]:
	var news: Array[String] = []
	for enemy in realm.armies.duplicate():
		if not realm.armies.has(enemy) or realm.is_ally(enemy) or not enemy.has_target() \
				or enemy.order_turn >= state.turn:
			continue
		var target := realm.towns[enemy.target]
		if target.owner != Realm.PLAYER or target.nation != nation.id:
			continue
		var group: Array = []
		var power := 0
		for army in realm.armies_of(nation.id):
			if not army.has_target() and RealmMap.are_neighbors(army.town, enemy.town):
				group.append(army)
				power += army.soldiers
		if group.is_empty() or power < enemy.soldiers * INTERCEPT_RATIO:
			continue
		var enemy_nation: Realm.Nation = realm.nations[enemy.nation]
		var record := _simulate(realm, RealmWar.army_side(realm, state, group, "Chư hầu %s" % nation.name),
				RealmWar.army_side(realm, state, [enemy], "Quân %s" % enemy_nation.name))
		RealmWar.spread_losses(realm, group, BattleOutcome.soldiers_lost(record, BattleRecord.ATTACKER))
		if record.winner == BattleRecord.ATTACKER:
			realm.remove_army(enemy)
			news.append("Chư hầu %s chặn đánh tan đạo quân %s định đánh trấn %s." % [nation.name, enemy_nation.name,
					target.name])
		else:
			RealmWar.spread_losses(realm, [enemy], BattleOutcome.soldiers_lost(record, BattleRecord.DEFENDER))
			news.append("Chư hầu %s chặn đánh quân %s nhưng thất bại." % [nation.name, enemy_nation.name])
	return news


## The attacks the vassal's armies announced on an earlier turn: fought at once against the town's
## garrison and armies; a town taken becomes ours (a capital destroys its nation).
static func _attack(realm: Realm, state: KingdomState, nation: Realm.Nation) -> Array[String]:
	var news: Array[String] = []
	var groups := {}
	for army in realm.armies_of(nation.id):
		if not army.has_target() or army.order_turn >= state.turn:
			continue
		var target := realm.towns[army.target]
		if target.owner == Realm.PLAYER or not RealmMap.are_neighbors(army.town, target.id):
			army.target = -1
			continue
		if not groups.has(target.id):
			groups[target.id] = []
		groups[target.id].append(army)
	for town_id in groups:
		var group: Array = groups[town_id]
		var town := realm.towns[town_id]
		var owner: Realm.Nation = realm.nations[town.owner]
		var defenders := BattleSide.new("%s (%s)" % [town.name, owner.name])
		defenders.color = owner.color
		var holders: Array = realm.armies_at(town_id)
		var soldiers := town.garrison
		for army: NationArmy in holders:
			soldiers += army.soldiers
		realm.add_nation_units(defenders, owner, soldiers, state)
		var guard := RealmWar.leader_of(holders)
		if guard != null:
			state.generals.lead_officer(defenders, guard.general)
		Realm.man_walls(defenders, town)
		var record := _simulate(realm, RealmWar.army_side(realm, state, group, "Chư hầu %s" % nation.name), defenders)
		for army: NationArmy in group:
			army.target = -1
		RealmWar.spread_losses(realm, group, BattleOutcome.soldiers_lost(record, BattleRecord.ATTACKER))
		if record.winner != BattleRecord.ATTACKER:
			realm.spread_town_losses(town, BattleOutcome.soldiers_lost(record, BattleRecord.DEFENDER))
			news.append("Chư hầu %s đánh trấn %s của %s nhưng thất bại." % [nation.name, town.name, owner.name])
			continue
		for army: NationArmy in holders:
			realm.remove_army(army)
		var old_owner := town.owner
		town.owner = Realm.PLAYER
		town.garrison = 0
		town.max_garrison = 0
		town.captured_turn = state.turn
		for army: NationArmy in group:
			if realm.armies.has(army):
				army.town = town_id
		if town.is_capital() and old_owner != Realm.REBELS and realm.nations[old_owner].capital() == town_id:
			var holdouts: Array[int] = []
			realm.destroy_nation(state, old_owner, holdouts)
			news.append("Chư hầu %s chiếm kinh đô %s: %s bị diệt, các trấn của họ về tay ta%s!" % [nation.name,
					town.name, owner.name, "" if holdouts.is_empty() else " (%d trấn còn tàn quân nổi loạn)" % holdouts.size()])
		else:
			news.append("Chư hầu %s chiếm trấn %s của %s cho ta." % [nation.name, town.name, owner.name])
	return news


## Free armies announce an attack on a neighboring enemy town they are RealmWar.NATION_RATIO as
## strong as, else, rested, move one road toward a town of the land on the border.
static func _new_orders(realm: Realm, nation: Realm.Nation, turn: int) -> void:
	for army in realm.armies_of(nation.id):
		if army.has_target():
			continue
		var best := -1
		var best_ratio := 0.0
		for id in RealmMap.neighbors(army.town):
			var town := realm.towns[id]
			if town.owner == Realm.PLAYER or id == Realm.HOME_CAPITAL:
				continue
			var power := 0.0
			for mate in realm.armies_at(army.town):
				if mate.nation == nation.id and (not mate.has_target() or mate.target == id):
					power += mate.soldiers
			var ratio := power / maxf(1.0, RealmWar.defense_of(realm, town))
			if ratio >= RealmWar.NATION_RATIO and ratio > best_ratio:
				best = id
				best_ratio = ratio
		if best >= 0:
			army.target = best
			army.order_turn = turn
		elif army.soldiers >= army.max_soldiers * RealmWar.REST_SHARE:
			var step := step_to_border(realm, nation, army.town)
			if step >= 0:
				army.town = step


static func _on_border(realm: Realm, town: int) -> bool:
	for id in RealmMap.neighbors(town):
		if realm.towns[id].owner != Realm.PLAYER:
			return true
	return false


## One road through the vassal's land toward its nearest town on the border; -1 when `from` is
## already on it or none is.
static func step_to_border(realm: Realm, nation: Realm.Nation, from: int) -> int:
	if _on_border(realm, from):
		return -1
	var came_from := {from: -1}
	var queue: Array[int] = [from]
	while not queue.is_empty():
		var town: int = queue.pop_front()
		if town != from and _on_border(realm, town):
			var step := town
			while came_from[step] != from:
				step = came_from[step]
			return step
		for next in RealmMap.neighbors(town):
			var candidate := realm.towns[next]
			if not came_from.has(next) and candidate.owner == Realm.PLAYER and candidate.nation == nation.id:
				came_from[next] = town
				queue.append(next)
	return -1


static func _simulate(realm: Realm, attackers: BattleSide, defenders: BattleSide) -> BattleRecord:
	var simulator := BattleSimulator.new(attackers, defenders, realm.rng.randi())
	while not simulator.finished:
		simulator.step()
	return simulator.record
