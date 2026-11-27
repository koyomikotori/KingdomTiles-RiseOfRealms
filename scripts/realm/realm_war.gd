class_name RealmWar
extends RefCounted
## The AI nations' side of the realm war (GDD §35, M18f-b1), run by Realm.end_turn: every nation
## gathers a treasury from its towns, raises armies (NationArmy) at its capital, and each army
## either carries out the attack it announced last turn, announces a new one against a neighboring
## town it can take, rests, or marches toward the border. Attacks on the kingdom's towns wait in
## Realm.pending_attacks for the start of the next turn; fights between nations are simulated at
## once and only reported. Static: works on the realm and state passed in.

## Treasury points a turn per town (the capital more), times INCOME_BY_DIFFICULTY.
const TOWN_INCOME := 1.0
const CAPITAL_INCOME := 3.0
const INCOME_BY_DIFFICULTY: Array[float] = [0.7, 1.0, 1.3, 1.6]
## What a new army costs; the treasury never holds more than MAX_TREASURY. A nation keeps at most
## 1 + one army per TOWNS_PER_ARMY towns, never more than MAX_ARMIES (was one per 3 towns with no
## cap: on Hard / Legendary the big nations' armies lagged the game).
const TOWNS_PER_ARMY := 4
const MAX_ARMIES := 4
const ARMY_COST := 10.0
const MAX_TREASURY := 20.0
## An army's full strength and its general's stars by the nation's distance from the kingdom.
const ARMY_BY_DISTANCE: Array[int] = [0, 200, 280, 380]
const STARS_BY_DISTANCE: Array[int] = [0, 2, 3, 4]
const MAX_STARS := 6
## Share of its full strength an army regains a turn in a town of its nation.
const ARMY_REGEN := 0.1
## An army attacks a town of ours only with at least ATTACK_RATIO × its defense, another
## nation's only with NATION_RATIO × (the nations are wary of each other).
const ATTACK_RATIO := 1.5
const NATION_RATIO := 2.0
## How much more an army wants a town of the kingdom, by difficulty.
const PLAYER_WEIGHT: Array[float] = [0.5, 1.0, 2.0, 2.0]
## A capital is worth more.
const CAPITAL_WEIGHT := 1.2
## Below this share of its strength an army with nothing to attack stays to recover.
const REST_SHARE := 0.6
## Our allies' armies favor our enemies' towns this much, and intercept an army about to strike a
## town of ours next to them when this many times as strong (GDD §37).
const ALLY_FOCUS := 1.5
const ALLY_INTERCEPT_RATIO := 1.2


## Every nation still fighting on its own (not destroyed, not the rebels, not our vassal).
static func live_nations(realm: Realm) -> Array[Realm.Nation]:
	var result: Array[Realm.Nation] = []
	for nation: Realm.Nation in realm.nations.values():
		if not nation.destroyed and nation.id != Realm.REBELS and not nation.submitted:
			result.append(nation)
	return result


static func income(realm: Realm, nation_id: StringName, difficulty: int) -> float:
	var total := 0.0
	for town in realm.towns:
		if town.owner == nation_id:
			total += CAPITAL_INCOME if town.is_capital() else TOWN_INCOME
	return total * INCOME_BY_DIFFICULTY[clampi(difficulty, 0, INCOME_BY_DIFFICULTY.size() - 1)]


static func max_armies(towns_owned: int) -> int:
	return mini(MAX_ARMIES, 1 + towns_owned / TOWNS_PER_ARMY)


static func army_size(nation: Realm.Nation, scale: float) -> int:
	return roundi(ARMY_BY_DISTANCE[clampi(nation.distance(), 1, ARMY_BY_DISTANCE.size() - 1)] * scale)


static func general_stars(nation: Realm.Nation, difficulty: int) -> int:
	var stars := STARS_BY_DISTANCE[clampi(nation.distance(), 1, STARS_BY_DISTANCE.size() - 1)]
	if difficulty == Difficulty.Level.LEGENDARY:
		stars += 1
	return mini(stars, MAX_STARS)


## A new army of `nation` at full strength in its capital.
static func raise_army(realm: Realm, state: KingdomState, nation: Realm.Nation) -> NationArmy:
	var army := NationArmy.new()
	army.id = realm.next_army_id
	realm.next_army_id += 1
	army.nation = nation.id
	army.general = state.generals.generate(general_stars(nation, state.difficulty))
	army.max_soldiers = army_size(nation, state.wars.enemy_scale)
	army.soldiers = army.max_soldiers
	army.town = nation.capital()
	realm.armies.append(army)
	return army


## How hard `town` is to take: its garrison and the armies of its owner in it behind the walls,
## plus, for a town of the kingdom, our armies there and the militia.
static func defense_of(realm: Realm, town: Realm.Town) -> float:
	var soldiers := 0.0
	if town.owner == Realm.PLAYER:
		soldiers += realm.militia_soldiers(town) + realm.vassal_guard(town)
		for force in realm.forces_at(town.id):
			soldiers += force.soldiers()
		for army in realm.armies_at(town.id):
			soldiers += army.soldiers
	else:
		soldiers += town.garrison
		for army in realm.armies_at(town.id):
			soldiers += army.soldiers
	return soldiers * (1.0 + (Realm.CAPITAL_WALL_DEFENSE if town.is_capital() else Realm.WALL_DEFENSE))


## The nations' turn. Returns {"news": [String] (fights between nations), "threats": [{army, town}]
## (attacks on the kingdom's towns announced this turn)}.
static func run_turn(realm: Realm, state: KingdomState) -> Dictionary:
	var news: Array[String] = []
	var threats: Array[Dictionary] = []
	var turn := state.turn
	for nation in live_nations(realm):
		var treasury: float = realm.treasury.get(nation.id, 0.0) + income(realm, nation.id, state.difficulty)
		var owned := realm.count_owned(nation.id)
		if treasury >= ARMY_COST and realm.armies_of(nation.id).size() < max_armies(owned) \
				and realm.towns[nation.capital()].owner == nation.id:
			treasury -= ARMY_COST
			raise_army(realm, state, nation)
		realm.treasury[nation.id] = minf(treasury, MAX_TREASURY)
	for army in realm.armies:
		if realm.towns[army.town].owner == army.nation and army.soldiers < army.max_soldiers \
				and not realm.is_ally(army):
			army.soldiers = mini(army.max_soldiers, army.soldiers + ceili(army.max_soldiers * ARMY_REGEN))
	news.append_array(ally_intercepts(realm, state))
	# Attacks announced on an earlier turn, grouped by nation and town.
	var groups := {}
	for army in realm.armies:
		if not army.has_target() or army.order_turn >= turn or realm.is_ally(army):
			continue
		var target := realm.towns[army.target]
		if not RealmMap.are_neighbors(army.town, target.id) or target.owner == army.nation \
				or target.id == Realm.HOME_CAPITAL or not realm.diplomacy.at_war(army.nation, target.owner):
			army.target = -1
			continue
		var key := "%s:%d" % [army.nation, target.id]
		if not groups.has(key):
			groups[key] = []
		groups[key].append(army)
	for key in groups:
		var group: Array = groups[key]
		var target: Realm.Town = realm.towns[group[0].target]
		if target.owner == Realm.PLAYER:
			realm.pending_attacks.append({"town": target.id,
					"armies": group.map(func(army: NationArmy) -> int: return army.id)})
		else:
			news.append(fight(realm, state, group, target))
	# New orders for the armies left free.
	var busy := {}
	for entry in realm.pending_attacks:
		for id in entry.armies:
			busy[int(id)] = true
	for army in realm.armies.duplicate():
		if busy.has(army.id) or army.has_target() or not realm.armies.has(army) or realm.is_ally(army):
			continue
		var target := pick_target(realm, state, army)
		if target >= 0:
			army.target = target
			army.order_turn = turn
			if realm.towns[target].owner == Realm.PLAYER:
				threats.append({"army": army.id, "town": target})
		elif army.soldiers >= army.max_soldiers * REST_SHARE:
			var step := step_to_border(realm, army)
			if step >= 0:
				army.town = step
	return {"news": news, "threats": threats}


## Our allies' armies meet the enemy armies about to strike a town of ours (announced on an earlier
## turn) when they stand next to them, are at war with them and ALLY_INTERCEPT_RATIO as strong.
## Returns the news lines.
static func ally_intercepts(realm: Realm, state: KingdomState) -> Array[String]:
	var news: Array[String] = []
	var allies := realm.diplomacy.allies_of_player(realm)
	if allies.is_empty():
		return news
	for enemy in realm.armies.duplicate():
		if not realm.armies.has(enemy) or realm.is_ally(enemy) or not enemy.has_target() \
				or enemy.order_turn >= state.turn or realm.towns[enemy.target].owner != Realm.PLAYER:
			continue
		for ally_id in allies:
			if not realm.diplomacy.at_war(ally_id, enemy.nation):
				continue
			var group: Array = []
			var power := 0
			for army in realm.armies_of(ally_id):
				if not army.has_target() and RealmMap.are_neighbors(army.town, enemy.town):
					group.append(army)
					power += army.soldiers
			if group.is_empty() or power < enemy.soldiers * ALLY_INTERCEPT_RATIO:
				continue
			var ally: Realm.Nation = realm.nations[ally_id]
			var enemy_nation: Realm.Nation = realm.nations[enemy.nation]
			var record := RealmVassals._simulate(realm, army_side(realm, state, group, "Quân %s" % ally.name),
					army_side(realm, state, [enemy], "Quân %s" % enemy_nation.name))
			spread_losses(realm, group, BattleOutcome.soldiers_lost(record, BattleRecord.ATTACKER))
			var town_name := realm.towns[enemy.target].name
			if record.winner == BattleRecord.ATTACKER:
				realm.remove_army(enemy)
				realm.diplomacy.add_memory(Realm.PLAYER, ally_id, RealmDiplomacy.FIGHT_TOGETHER)
				news.append("Đồng minh %s chặn đánh tan đạo quân %s định đánh trấn %s." % [ally.name, enemy_nation.name,
						town_name])
			else:
				spread_losses(realm, [enemy], BattleOutcome.soldiers_lost(record, BattleRecord.DEFENDER))
				news.append("Đồng minh %s chặn đánh quân %s nhưng thất bại." % [ally.name, enemy_nation.name])
			break
	return news


## The neighboring town `army` most wants and can take (ATTACK_RATIO), or -1.
static func pick_target(realm: Realm, state: KingdomState, army: NationArmy) -> int:
	var best := -1
	var best_score := 0.0
	for id in RealmMap.neighbors(army.town):
		var town := realm.towns[id]
		if town.owner == army.nation or id == Realm.HOME_CAPITAL or not realm.diplomacy.at_war(army.nation, town.owner):
			continue
		var power := 0.0
		for mate in realm.armies_at(army.town):
			if mate.nation == army.nation and (not mate.has_target() or mate.target == id):
				power += mate.soldiers
		var ratio := power / maxf(1.0, defense_of(realm, town))
		if ratio < (ATTACK_RATIO if town.owner == Realm.PLAYER else NATION_RATIO):
			continue
		var score := ratio
		if town.owner == Realm.PLAYER:
			score *= PLAYER_WEIGHT[clampi(state.difficulty, 0, PLAYER_WEIGHT.size() - 1)]
		if town.is_capital():
			score *= CAPITAL_WEIGHT
		# Our allies go first for our enemies (GDD §37).
		if realm.diplomacy.allied(Realm.PLAYER, army.nation) and town.owner != Realm.REBELS \
				and realm.diplomacy.at_war(Realm.PLAYER, town.owner):
			score *= ALLY_FOCUS
		if score > best_score:
			best = id
			best_score = score
	return best


## One road toward the nearest town of another owner, through the nation's own towns; -1 when the
## army already stands on the border (or has nowhere to go).
static func step_to_border(realm: Realm, army: NationArmy) -> int:
	var came_from := {army.town: -1}
	var queue: Array[int] = [army.town]
	while not queue.is_empty():
		var town: int = queue.pop_front()
		if realm.towns[town].owner != army.nation:
			if came_from[town] == army.town or town == army.town:
				return -1
			var step := town
			while came_from[step] != army.town:
				step = came_from[step]
			return step if realm.towns[step].owner == army.nation else -1
		for next in RealmMap.neighbors(town):
			if not came_from.has(next):
				came_from[next] = town
				queue.append(next)
	return -1


## A battle side for the armies of one nation together, led by the best general among them.
static func army_side(realm: Realm, state: KingdomState, group: Array, title: String) -> BattleSide:
	var nation: Realm.Nation = realm.nations[group[0].nation]
	var side := BattleSide.new(title)
	side.color = nation.color
	var soldiers := 0
	for army: NationArmy in group:
		soldiers += army.soldiers
	realm.add_nation_units(side, nation, soldiers, state)
	var leader := leader_of(group)
	if leader != null and leader.general != null:
		state.generals.lead_officer(side, leader.general)
	return side


static func leader_of(group: Array) -> NationArmy:
	var best: NationArmy = null
	for army: NationArmy in group:
		if army.general != null and (best == null or army.general.stars > best.general.stars):
			best = army
	return best


## Takes `lost` soldiers from the armies of `group` in proportion; armies with none left are gone.
static func spread_losses(realm: Realm, group: Array, lost: int) -> void:
	var total := 0
	for army: NationArmy in group:
		total += army.soldiers
	if total <= 0:
		return
	for army: NationArmy in group:
		army.soldiers = maxi(0, army.soldiers - roundi(float(lost) * army.soldiers / total))
		if army.soldiers <= 0:
			realm.remove_army(army)


## A fight between two nations at `town`, simulated at once: the armies of `group` against its
## garrison and its owner's armies there. Returns the news line.
static func fight(realm: Realm, state: KingdomState, group: Array, town: Realm.Town) -> String:
	var attacker: Realm.Nation = realm.nations[group[0].nation]
	var owner: Realm.Nation = realm.nations[town.owner]
	var attackers := army_side(realm, state, group, "Quân %s" % attacker.name)
	var defenders_armies: Array = realm.armies_at(town.id)
	var defenders := BattleSide.new("%s (%s)" % [town.name, owner.name])
	defenders.color = owner.color
	var soldiers := town.garrison
	for army: NationArmy in defenders_armies:
		soldiers += army.soldiers
	realm.add_nation_units(defenders, owner, soldiers, state)
	var guard := leader_of(defenders_armies)
	if guard != null:
		state.generals.lead_officer(defenders, guard.general)
	realm.man_walls(defenders, town)
	var simulator := BattleSimulator.new(attackers, defenders, realm.rng.randi())
	while not simulator.finished:
		simulator.step()
	var record := simulator.record
	for army: NationArmy in group:
		army.target = -1
	spread_losses(realm, group, BattleOutcome.soldiers_lost(record, BattleRecord.ATTACKER))
	var defender_lost := BattleOutcome.soldiers_lost(record, BattleRecord.DEFENDER)
	if record.winner != BattleRecord.ATTACKER:
		realm.spread_town_losses(town, defender_lost)
		return "%s đánh trấn %s của %s nhưng thất bại." % [attacker.name, town.name, owner.name]
	for army: NationArmy in defenders_armies:
		realm.remove_army(army)
	realm.diplomacy.note_capture(attacker.id, town.owner, state.turn)
	town.owner = attacker.id
	town.max_garrison = Realm.garrison_for(town.id, state.wars.enemy_scale)
	town.garrison = 0
	for army: NationArmy in group:
		if realm.armies.has(army):
			army.town = town.id
	if town.is_capital() and owner.id != Realm.REBELS and owner.capital() == town.id:
		fall(realm, owner, attacker.id)
		return "%s chiếm kinh đô %s: %s bị diệt!" % [attacker.name, town.name, owner.name]
	return "%s chiếm trấn %s của %s." % [attacker.name, town.name, owner.name]


## `nation` is destroyed by another nation: its towns go to `winner`, its armies break up.
static func fall(realm: Realm, nation: Realm.Nation, winner: StringName) -> void:
	nation.destroyed = true
	realm.diplomacy.remove(nation.id)
	realm.treasury.erase(nation.id)
	for town in realm.towns:
		if town.owner == nation.id:
			town.owner = winner
	for army in realm.armies_of(nation.id):
		realm.remove_army(army)
