class_name EventBattles
extends RefCounted
## Battles that an event answer leads to (GDD §21, M16e). EventSystem.resolve leaves
## {"kind", "clan_id", "event_id"} in EventSystem.pending_battle; the kingdom scene calls start()
## (a BattleSimulator to play, or null when it cannot be fought any more), plays it, then finish().
## - DUEL: the commander alone against the clan's general (the kingdom defends at its gate). The
##   loser dies; the winner's side keeps +morale, the loser's −DUEL_MORALE in their next battle
##   against each other.
## - BREAKOUT: the ambushed commander with DETACHMENT_MIN..MAX random squads against
##   BREAKOUT_ENEMY_SHARE × their soldiers of the clan. A lost breakout loses those squads and the
##   commander falls (Generals.after_battle: dead or wounded).
## - SURPRISE: a normal attack (KingdomState.finish_attack) on SURPRISE_SHARE of the clan's
##   soldiers, caught out with SURPRISE_MORALE.
## - RESCUE: the commander (if any) and a detachment attack bandits holding an official; winning
##   pays RESCUE_REWARD and pleases every clan, losing the official angers them.
## - BANDIT_DUEL: a general the player picked (battle.general) against the bandits' leader. Win:
##   the leader dies, raids are scarcer (BANDIT_WIN_RAID_FACTOR) and weaker (−DUEL_MORALE) for
##   BANDIT_WIN_TURNS turns. Loss: the general dies, −DUEL_MORALE in the next bandit battle.
## Stateless: everything goes through the KingdomState passed in.

const DUEL := &"duel"
const BANDIT_DUEL := &"bandit_duel"
const BREAKOUT := &"breakout"
const SURPRISE := &"surprise"
const RESCUE := &"rescue"
const KINDS: Array[StringName] = [DUEL, BREAKOUT, SURPRISE, RESCUE, BANDIT_DUEL]

const DETACHMENT_MIN := 3
const DETACHMENT_MAX := 5
const DUEL_MORALE := 2
## A duelist's attack is scaled by a roll in 1 ± DUEL_LUCK.
const DUEL_LUCK := 0.2
const BREAKOUT_ENEMY_SHARE := 1.2
const SURPRISE_SHARE := 0.5
const SURPRISE_MORALE := -2
const RESCUE_ENEMY_SHARE := 1.0
const RESCUE_MAX_UNITS := 6
const RESCUE_REWARD: Dictionary[StringName, int] = {&"food": 60, &"wood": 60, &"stone": 60, &"ore": 10}
const RESCUE_WIN_RELATION := 3
const RESCUE_LOSS_RELATION := -5
const BANDIT_WIN_TURNS := 10
const BANDIT_WIN_RAID_FACTOR := 0.5


## Which side the kingdom fights on.
static func player_side(kind: StringName) -> int:
	return BattleRecord.ATTACKER if kind in [SURPRISE, RESCUE] else BattleRecord.DEFENDER


static func title(state: KingdomState, battle: Dictionary) -> String:
	var clan := _clan_name(state, battle.clan_id)
	match battle.kind:
		DUEL:
			return "Tay đôi trước cổng thành với tướng %s!" % clan
		BREAKOUT:
			return "Phá vòng vây quân %s!" % clan
		SURPRISE:
			return "Đánh úp doanh trại %s!" % clan
		RESCUE:
			return "Cứu viện quan chức bị bắt!"
		BANDIT_DUEL:
			return "Tay đôi với thủ lĩnh đạo tặc!"
	return ""


## DETACHMENT_MIN..MAX random squads at home (fewer when there are fewer).
static func detachment(state: KingdomState, rng: RandomNumberGenerator) -> Array[Army.Squad]:
	var home: Array[Army.Squad] = []
	for squad in state.army.squads:
		if not squad.away:
			home.append(squad)
	var picked: Array[Army.Squad] = []
	for i in mini(rng.randi_range(DETACHMENT_MIN, DETACHMENT_MAX), home.size()):
		picked.append(home.pop_at(rng.randi_range(0, home.size() - 1)))
	return picked


## The battle's simulator, or null (nothing changes) when it cannot be fought any more: no
## commander, no squads at home, no enemy general. Stores the detachment in `battle.squads`.
static func start(state: KingdomState, battle: Dictionary, rng: RandomNumberGenerator) -> BattleSimulator:
	var clan_id: StringName = battle.clan_id
	match battle.kind:
		DUEL:
			var commander := state.generals.active_commander()
			state.clan_officers.ensure(clan_id, state.wars, state.difficulty)
			var rival := state.clan_officers.fielded_general(clan_id, state.wars, state.difficulty)
			if commander == null or rival == null:
				return null
			var clan := state.diplomacy.clans[clan_id].data
			var ours := Generals.duel_side(commander, state.kingdom_name, state.player_color, _luck(rng))
			var theirs := Generals.duel_side(rival, clan.display_name, clan.color, _luck(rng))
			return BattleSimulator.new(theirs, ours, rng.randi())
		BANDIT_DUEL:
			var general: General = battle.get("general")
			var leader := state.clan_officers.bandit_leader(state.turn)
			if general == null or not general in state.generals.generals or not general.is_ready() or leader == null:
				return null
			var ours := Generals.duel_side(general, state.kingdom_name, state.player_color, _luck(rng))
			var theirs := Generals.duel_side(leader, "Đạo tặc", RaidSystem.BANDIT_COLOR, _luck(rng))
			return BattleSimulator.new(theirs, ours, rng.randi())
		BREAKOUT:
			if state.generals.active_commander() == null:
				return null
			var kingdom := _detachment_side(state, battle, rng, true)
			if kingdom == null:
				return null
			var soldiers := roundi(kingdom.start_total() * BREAKOUT_ENEMY_SHARE)
			var ambushers := state.wars.create_clan_side(clan_id, clampi(soldiers, 1, maxi(1, state.wars.fronts[clan_id].strength)),
					state.units)
			state.morale_effects.apply(kingdom, ambushers, clan_id)
			return BattleSimulator.new(ambushers, kingdom, rng.randi())
		SURPRISE:
			if state.army.squads.all(func(squad: Army.Squad) -> bool: return squad.away):
				return null
			var soldiers := maxi(1, roundi(state.wars.fronts[clan_id].strength * SURPRISE_SHARE))
			return state.create_attack(clan_id, soldiers, SURPRISE_MORALE)
		RESCUE:
			var kingdom := _detachment_side(state, battle, rng, false)
			if kingdom == null:
				return null
			var bandits := _bandit_side(state, rng, roundi(kingdom.start_total() * RESCUE_ENEMY_SHARE))
			state.morale_effects.apply(kingdom, bandits, ClanOfficers.BANDITS)
			return BattleSimulator.new(kingdom, bandits, rng.randi())
	return null


## Applies the fought battle. Returns a result shaped like KingdomState.finish_attack's (report
## lines in "lines"); for SURPRISE it is finish_attack's own.
static func finish(state: KingdomState, battle: Dictionary, record: BattleRecord) -> Dictionary:
	var clan_id: StringName = battle.clan_id
	if battle.kind == SURPRISE:
		var result := state.finish_attack(clan_id, record)
		result["lines"] = [] as Array[String]
		return result
	var side := player_side(battle.kind)
	var won := record.winner == side
	var lines: Array[String] = []
	var result := {"record": record, "won": won, "clan_id": clan_id, "allies": {}, "helpers": {},
			"casualties": {}, "scattered": {}, "retreat_losses": {}}
	match battle.kind:
		DUEL:
			result["general"] = _finish_duel(state, clan_id, won, lines)
		BANDIT_DUEL:
			result["general"] = _finish_bandit_duel(state, battle.general, won, lines)
		BREAKOUT:
			state._record_battle(won)
			if not won:
				# A lost breakout always brings the commander down (dead or wounded).
				record.sides[side].general_fallen = true
			state.generals.survival = state.building_effect(&"commander_survival")
			result["general"] = state.generals.after_battle(record, side)
			result.merge(BattleOutcome.apply_to_army(state.army, record, side, not won,
					state.building_effect(&"retreat_keep")), true)
			var enemy_lost := BattleOutcome.soldiers_lost(record, 1 - side)
			state.wars.lose_soldiers(clan_id, enemy_lost)
			state.morale_effects.after_battle(clan_id)
			lines.append("Quân %s mất %d lính." % [_clan_name(state, clan_id), enemy_lost])
			lines.append("Tổng tướng đã thoát khỏi vòng vây." if won else "Các đơn vị theo tổng tướng đều đã mất.")
		RESCUE:
			state._record_battle(won)
			state.generals.survival = state.building_effect(&"commander_survival")
			result["general"] = state.generals.after_battle(record, side)
			result.merge(BattleOutcome.apply_to_army(state.army, record, side, false,
					state.building_effect(&"retreat_keep")), true)
			state.morale_effects.after_battle(ClanOfficers.BANDITS)
			var types := ResourceTypeData.load_all()
			if won:
				state.stockpile.add(RESCUE_REWARD)
				_relation_all(state, RESCUE_WIN_RELATION)
				lines.append("Quan chức được cứu về, dân chúng mang quà tạ ơn: %s." % UiFormat.amounts(RESCUE_REWARD, types))
				lines.append("Quan hệ với mọi gia tộc %+d." % RESCUE_WIN_RELATION)
			else:
				_relation_all(state, RESCUE_LOSS_RELATION)
				lines.append("Quan chức bị đạo tặc giết, các gia tộc chê trách.")
				lines.append("Quan hệ với mọi gia tộc %+d." % RESCUE_LOSS_RELATION)
	result["lines"] = lines
	return result


## The duel's loser dies; the other side's army takes heart for their next battle. Returns the
## commander's fate as Generals.after_battle does.
static func _finish_duel(state: KingdomState, clan_id: StringName, won: bool, lines: Array[String]) -> Dictionary:
	var commander := state.generals.commander
	var clan := _clan_name(state, clan_id)
	if won:
		var rival := state.clan_officers.assassinate(clan_id, &"general", true)
		state.morale_effects.add(MoraleEffects.ENEMY, -DUEL_MORALE, clan_id)
		var xp := Experience.general_battle_xp(1.0, true)
		var levels := commander.gain_xp(xp)
		state.generals.changed.emit()
		lines.append("Tướng %s của %s tử trận dưới tay tổng tướng %s!" % [rival, clan, commander.name])
		lines.append("Trận kế tiếp với %s: quân địch %+d nhuệ khí tối đa." % [clan, -DUEL_MORALE])
		return {"name": commander.name, "fate": &"none", "xp": xp, "levels": levels}
	state.generals.dismiss(commander)
	state.morale_effects.add(MoraleEffects.KINGDOM, -DUEL_MORALE, clan_id)
	lines.append("Trận kế tiếp với %s: quân ta %+d nhuệ khí tối đa." % [clan, -DUEL_MORALE])
	return {"name": commander.name, "fate": &"dead", "xp": 0, "levels": 0}


## The picked general against the bandits' leader: the loser dies.
static func _finish_bandit_duel(state: KingdomState, general: General, won: bool, lines: Array[String]) -> Dictionary:
	if won:
		var leader := state.clan_officers.assassinate(ClanOfficers.BANDITS, &"general", true)
		state.morale_effects.add(MoraleEffects.ENEMY, -DUEL_MORALE, ClanOfficers.BANDITS, BANDIT_WIN_TURNS)
		state.raid_pressure.add(BANDIT_WIN_RAID_FACTOR, BANDIT_WIN_TURNS)
		var xp := Experience.general_battle_xp(1.0, true)
		var levels := general.gain_xp(xp)
		state.generals.changed.emit()
		lines.append("Thủ lĩnh đạo tặc %s tử trận dưới tay tướng %s!" % [leader, general.name])
		lines.append(state.events.morale_line(state, -DUEL_MORALE, true, ClanOfficers.BANDITS, BANDIT_WIN_TURNS) + ".")
		lines.append(RaidPressure.describe(BANDIT_WIN_RAID_FACTOR, BANDIT_WIN_TURNS) + ".")
		return {"name": general.name, "fate": &"none", "xp": xp, "levels": levels, "title": "Tướng"}
	state.generals.dismiss(general)
	state.morale_effects.add(MoraleEffects.KINGDOM, -DUEL_MORALE, ClanOfficers.BANDITS)
	lines.append(state.events.morale_line(state, -DUEL_MORALE, false, ClanOfficers.BANDITS, 0) + ".")
	return {"name": general.name, "fate": &"dead", "xp": 0, "levels": 0, "title": "Tướng"}


## The detachment (stored in battle.squads) as a side, led by the commander when able; null when
## no squad is at home.
static func _detachment_side(state: KingdomState, battle: Dictionary, rng: RandomNumberGenerator,
		defending: bool) -> BattleSide:
	var squads := detachment(state, rng)
	if squads.is_empty():
		return null
	battle["squads"] = squads
	var side := BattleSide.new(state.kingdom_name)
	side.color = state.player_color
	for squad in squads:
		side.add_unit(state.units[squad.unit_id], squad.soldiers, squad)
	state.generals.lead(side, state.board, defending)
	return side


## Bandit units (the raid's kinds, sized by the difficulty) until about `soldiers` of them.
static func _bandit_side(state: KingdomState, rng: RandomNumberGenerator, soldiers: int) -> BattleSide:
	var side := BattleSide.new("Quân cướp")
	side.color = RaidSystem.BANDIT_COLOR
	var bandits := state.raid if state.raid != null else RaidData.load_bandits()
	var ids: Array[StringName] = []
	var weights := PackedFloat32Array()
	for unit_id in bandits.unit_weights:
		ids.append(unit_id)
		weights.append(bandits.unit_weights[unit_id])
	while side.start_total() < soldiers and side.units.size() < RESCUE_MAX_UNITS:
		var data: UnitData = state.enemy_units[ids[rng.rand_weighted(weights)]]
		side.add_unit(data, state.wars.squad_size(data))
	return side


static func _luck(rng: RandomNumberGenerator) -> float:
	return rng.randf_range(1.0 - DUEL_LUCK, 1.0 + DUEL_LUCK)


static func _relation_all(state: KingdomState, amount: int) -> void:
	for clan_id in state.diplomacy.clans:
		if not state.diplomacy.clans[clan_id].annexed:
			state.diplomacy.change_relation(clan_id, amount, Diplomacy.MEMORY_EVENT)


static func _clan_name(state: KingdomState, clan_id: StringName) -> String:
	return state.diplomacy.clans[clan_id].data.display_name if clan_id != &"" else ""
