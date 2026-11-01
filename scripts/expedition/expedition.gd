class_name Expedition
extends RefCounted
## An expedition against the uprising (GDD §15, M14i): up to one general, one advisor and
## MAX_SQUADS squads march through the zone's stages, one stage at the end of each turn
## (KingdomState.end_turn → run_stage). A stage is `ambushes` battles in a row, plus a rebel
## general at its end with a chance that grows with each stage; squads that break or die in any
## battle are gone, the survivors are healed to full at the end of the stage. Losing a battle ends
## the expedition: every squad is lost, the general may die (Generals.death_chance), the advisor
## may be wounded. Rewards (XP per battle won, resources and an item per stage cleared) are handed
## over when the expedition ends, won or lost. While away, officers and squads take no part in the
## kingdom's battles, posts or replenishment (Officer.away, Army.Squad.away).
## M16e: with a general along, each stage has DUEL_CHANCE that a rebel general challenges them
## before the first ambush. With `accept_duels` (chosen when sending) they fight alone (the record
## goes first in the stage's battles) and the loser dies: a win costs the rebels DUEL_MORALE in the
## next stage, a loss costs the team as much. Refused, the team has DECLINE_MORALE in that stage.

const MAX_SQUADS := 10
const STAGES_BY_CASTLE: Array[int] = [1, 1, 2, 2, 3, 4]
const AMBUSHES_BY_CASTLE: Array[int] = [1, 1, 2, 2, 3, 3]
const MAX_ENEMY_UNITS := 5
## The rebel general at a stage's end: BOSS_CHANCE + BOSS_PER_STAGE × stage + BOSS_PER_CLEARED ×
## zones cleared before, at most MAX_BOSS_CHANCE.
const BOSS_CHANCE := 0.15
const BOSS_PER_STAGE := 0.2
const BOSS_PER_CLEARED := 0.05
const MAX_BOSS_CHANCE := 0.9
const MAX_BOSS_STARS := 5
## Rewards: XP for each battle won, basic resources × (stage + 1) × the zone's size factor, and an
## item per stage cleared with better odds in later stages (Item.Rarity order).
const WIN_OFFICER_XP := 30
const WIN_SQUAD_XP := 20
const STAGE_RESOURCES := 40
const REWARD_RESOURCES: Array[StringName] = [&"food", &"wood", &"stone"]
const STAGE_ITEM_ODDS: Array = [[50, 35, 13, 2, 0], [35, 35, 22, 7, 1], [20, 35, 30, 12, 3], [10, 30, 35, 20, 5]]
const REBEL_NAME := "Quân nổi loạn"
## Limit-break scrolls for clearing the zone (M16c): one per SCROLL_STAGES stages, at least one.
const SCROLL_STAGES := 2
const DUEL_CHANCE := 0.25
const DUEL_MORALE := 2
const DECLINE_MORALE := -1

var general: General
var advisor: Advisor
var squads: Array[Army.Squad] = []
var stages := 1
var ambushes := 1
## The next stage to fight (0-based); == stages once every stage is cleared.
var stage := 0
var wins := 0
var failed := false
## Zones cleared before this one (Uprising.cleared) and its size factor when the expedition left.
var cleared_before := 0
var size_factor := 1.0
var resources: Dictionary[StringName, int] = {}
var items: Array[Item] = []
## One line per stage fought, for the progress window.
var log: Array[String] = []
## Whether the general takes up a rebel general's challenge (M16e).
var accept_duels := true
## Starting morale changes for the next stage, left by a duel.
var team_morale_next := 0
var rebel_morale_next := 0


func is_over() -> bool:
	return failed or stage >= stages


static func scrolls_for(stage_count: int) -> int:
	return maxi(1, ceili(stage_count / float(SCROLL_STAGES)))


static func stages_for(castle_level: int) -> int:
	return STAGES_BY_CASTLE[clampi(castle_level, 1, STAGES_BY_CASTLE.size()) - 1]


static func ambushes_for(castle_level: int) -> int:
	return AMBUSHES_BY_CASTLE[clampi(castle_level, 1, AMBUSHES_BY_CASTLE.size()) - 1]


static func boss_chance(stage_index: int, cleared: int) -> float:
	return minf(MAX_BOSS_CHANCE, BOSS_CHANCE + BOSS_PER_STAGE * stage_index + BOSS_PER_CLEARED * cleared)


## Bandit units in each ambush of `stage_index` (1..MAX_ENEMY_UNITS, before the random ±1).
static func enemy_units_for(stage_index: int, cleared: int, size: float) -> int:
	return clampi(1 + stage_index + cleared / 2 + roundi((size - 1.0) * 2.0), 1, MAX_ENEMY_UNITS)


## The bandits' experience level in `stage_index` (0..2, as Experience squad levels).
static func enemy_level_for(stage_index: int, cleared: int) -> int:
	return clampi(stage_index + cleared / 2, 0, 2)


## Resources a cleared stage gives.
func stage_resources(stage_index: int) -> Dictionary[StringName, int]:
	var result: Dictionary[StringName, int] = {}
	for resource_id in REWARD_RESOURCES:
		result[resource_id] = roundi(STAGE_RESOURCES * (stage_index + 1) * size_factor)
	return result


## Fights the next stage. Returns {"stage": int, "battles": Array[BattleRecord], "boss": String
## ("" without one), "won": bool, "lost_squads": Array[StringName] (unit ids gone), "finished":
## bool, "general_fate": &"none" | &"dead" | &"wounded", "advisor_fate"}.
func run_stage(state: KingdomState, rng: RandomNumberGenerator) -> Dictionary:
	var battles: Array[BattleRecord] = []
	var lost: Array[StringName] = []
	var boss_name := ""
	var won := true
	var team_morale := team_morale_next
	var rebel_morale := rebel_morale_next
	team_morale_next = 0
	rebel_morale_next = 0
	var duel := {}
	var fallen: General = null
	if general != null and rng.randf() < DUEL_CHANCE:
		var rebel := state.rebels.generate(mini(MAX_BOSS_STARS, 1 + stage + cleared_before / 3))
		rebel.trait_id = &""
		duel = {"rebel": rebel.name, "accepted": accept_duels, "won": false, "index": -1}
		if accept_duels:
			var ours := Generals.duel_side(general, "Đạo thảo phạt", state.player_color, _luck(rng))
			var theirs := Generals.duel_side(rebel, REBEL_NAME, RaidSystem.BANDIT_COLOR, _luck(rng))
			var record := BattleSimulator.simulate(ours, theirs, rng.randi())
			battles.append(record)
			duel.index = 0
			duel.won = record.winner == BattleRecord.ATTACKER
			if duel.won:
				rebel_morale_next = -DUEL_MORALE
				general.gain_xp(Experience.general_battle_xp(1.0, true))
			else:
				team_morale_next = -DUEL_MORALE
				fallen = general
				general = null
		else:
			team_morale += DECLINE_MORALE
	var fights := ambushes + (1 if rng.randf() < boss_chance(stage, cleared_before) else 0)
	for i in fights:
		var is_boss := i == ambushes
		var team := _team_side(state)
		var enemy := _enemy_side(state, rng, is_boss)
		_change_morale(team, team_morale)
		_change_morale(enemy, rebel_morale)
		if is_boss:
			boss_name = enemy.general_name
		var record := BattleSimulator.simulate(team, enemy, rng.randi())
		battles.append(record)
		won = record.winner == BattleRecord.ATTACKER
		lost.append_array(_apply_losses(state, record, won))
		if not won:
			break
		wins += 1
	var result := {"stage": stage, "stages": stages, "battles": battles, "boss": boss_name, "won": won,
			"lost_squads": lost, "general_fate": &"none", "advisor_fate": &"none", "duel": duel,
			"team_morale": team_morale, "rebel_morale": rebel_morale}
	if fallen != null:
		result.general_fate = &"dead"
		result["fallen"] = fallen
	if won:
		for squad in squads:
			squad.soldiers = state.units[squad.unit_id].squad_size
		Economy.add_into(resources, stage_resources(stage))
		var item := state.equipment.create_random(state.equipment.roll(STAGE_ITEM_ODDS[mini(stage, STAGE_ITEM_ODDS.size() - 1)]))
		if item != null:
			items.append(item)
		log.append("Ải %d: thắng %d trận%s%s." % [stage + 1, battles.size() - (1 if duel.get("index", -1) >= 0 else 0),
				", hạ tướng nổi loạn %s" % boss_name if boss_name != "" else "", _duel_log(duel)])
		stage += 1
	else:
		failed = true
		log.append("Ải %d: thua ở trận %d%s." % [stage + 1, battles.size() - (1 if duel.get("index", -1) >= 0 else 0),
				_duel_log(duel)])
		if general != null and battles.back().sides[BattleRecord.ATTACKER].general_fallen:
			if rng.randf() < Generals.death_chance(general, state.building_effect(&"commander_survival")):
				result.general_fate = &"dead"
			else:
				general.wounded_turns = Generals.WOUND_TURNS
				result.general_fate = &"wounded"
		if advisor != null and rng.randf() < Advisors.WOUND_CHANCE:
			advisor.wounded_turns = Advisors.WOUND_TURNS
			result.advisor_fate = &"wounded"
	result["finished"] = is_over()
	return result


static func _duel_log(duel: Dictionary) -> String:
	if duel.is_empty():
		return ""
	if not duel.accepted:
		return ", không nhận lời thách đấu của %s" % duel.rebel
	return ", %s tay đôi với %s" % ["thắng" if duel.won else "thua", duel.rebel]


static func _luck(rng: RandomNumberGenerator) -> float:
	return rng.randf_range(1.0 - EventBattles.DUEL_LUCK, 1.0 + EventBattles.DUEL_LUCK)


## Changes the starting morale of the side's units (a duel's after-effect, M16e).
static func _change_morale(side: BattleSide, amount: int) -> void:
	if amount == 0:
		return
	for unit in side.units:
		unit.morale = maxf(MoraleEffects.MIN_MORALE, unit.morale + amount)


## The expedition's own army as the attacker: squads as they are, led by its general and advisor.
func _team_side(state: KingdomState) -> BattleSide:
	var side := BattleSide.new("Đạo thảo phạt")
	side.color = state.player_color
	for squad in squads:
		side.add_unit(state.units[squad.unit_id], squad.soldiers, squad)
	state.bless_army(side)
	if general != null:
		state.generals.lead_officer(side, general)
	if advisor != null:
		state.advisors.assist_officer(side, advisor, advisor.stat_for(&"military"), 0.0)
	return side


## An ambush: 1..MAX_ENEMY_UNITS bandit units sized by the difficulty and seasoned by the stage;
## the boss fight adds a unit and a rebel general.
func _enemy_side(state: KingdomState, rng: RandomNumberGenerator, is_boss: bool) -> BattleSide:
	var side := BattleSide.new(REBEL_NAME)
	side.color = RaidSystem.BANDIT_COLOR
	var count := clampi(enemy_units_for(stage, cleared_before, size_factor) + rng.randi_range(-1, 1), 1, MAX_ENEMY_UNITS)
	if is_boss:
		count = mini(MAX_ENEMY_UNITS, count + 1)
	var ids: Array[StringName] = []
	var weights := PackedFloat32Array()
	# The bandits' units, even when raids are turned off (state.raid null).
	var bandits := state.raid if state.raid != null else RaidData.load_bandits()
	for unit_id in bandits.unit_weights:
		ids.append(unit_id)
		weights.append(bandits.unit_weights[unit_id])
	for unit_id in bandits.late_units:
		if state.turn >= bandits.late_units[unit_id]:
			ids.append(unit_id)
			weights.append(RaidSystem.LATE_UNIT_WEIGHT)
	var level := enemy_level_for(stage, cleared_before)
	for i in count:
		var data: UnitData = state.enemy_units[ids[rng.rand_weighted(weights)]]
		side.add_unit(data, state.wars.squad_size(data))
		var unit: BattleSide.Unit = side.units.back()
		var bonus := level * Experience.SQUAD_LEVEL_BONUS
		unit.level = level
		unit.attack_bonus = bonus
		unit.defense_bonus = bonus
		unit.range_bonus = bonus if data.is_ranged() else 0
		unit.morale += bonus
	if is_boss:
		var rebel := state.rebels.generate(mini(MAX_BOSS_STARS, 1 + stage + cleared_before / 3))
		rebel.trait_id = &""
		state.rebels.lead_officer(side, rebel)
	return side


## Squads that broke or died are gone (from the army too); the rest keep their survivors. A lost
## battle loses every squad. Returns the unit ids lost.
func _apply_losses(state: KingdomState, record: BattleRecord, won: bool) -> Array[StringName]:
	var lost: Array[StringName] = []
	for unit in record.sides[BattleRecord.ATTACKER].units:
		var squad := unit.squad
		if squad == null or not squads.has(squad):
			continue
		if not won or unit.broken or unit.alive() == 0:
			lost.append(squad.unit_id)
			squads.erase(squad)
			state.army.remove_squad(squad)
		else:
			squad.soldiers = unit.alive()
	return lost


## Hands over the rewards (XP for every battle won, resources, items, scrolls once every stage
## is cleared) and brings everyone home.
## Returns {"resources", "items": Array[Item], "xp_officer", "xp_squad", "refund", "scrolls"}.
func finish(state: KingdomState) -> Dictionary:
	var officer_xp := WIN_OFFICER_XP * wins
	var squad_xp := WIN_SQUAD_XP * wins
	for officer: Officer in [general, advisor]:
		if officer != null:
			officer.away = false
			officer.gain_xp(officer_xp)
	for squad in squads:
		squad.away = false
		state.army.add_xp(squad, squad_xp)
	state.stockpile.add(resources)
	var scrolls := 0 if failed else scrolls_for(stages)
	state.scrolls += scrolls
	var refund: Dictionary[StringName, int] = {}
	for item in items:
		Economy.add_into(refund, state.equipment.receive(item, state.stockpile).refund)
	state.generals.changed.emit()
	state.advisors.changed.emit()
	state.army.changed.emit()
	return {"resources": resources, "items": items, "xp_officer": officer_xp, "xp_squad": squad_xp, "refund": refund,
			"scrolls": scrolls}


# --- Save (GDD §10.1) ---------------------------------------------------------------------

func to_save(state: KingdomState) -> Dictionary:
	var item_saves: Array = items.map(func(item: Item) -> Dictionary: return item.to_save())
	return {"general": state.generals.generals.find(general), "advisor": state.advisors.advisors.find(advisor),
			"squads": squads.map(func(s: Army.Squad) -> int: return state.army.squads.find(s)),
			"stages": stages, "ambushes": ambushes, "stage": stage, "wins": wins, "failed": failed,
			"cleared_before": cleared_before, "size_factor": size_factor, "resources": resources.duplicate(),
			"items": item_saves, "log": log.duplicate(), "accept_duels": accept_duels,
			"team_morale_next": team_morale_next, "rebel_morale_next": rebel_morale_next}


static func from_save(data: Dictionary, state: KingdomState) -> Expedition:
	var expedition := Expedition.new()
	var general_index := int(data.get("general", -1))
	if general_index >= 0 and general_index < state.generals.generals.size():
		expedition.general = state.generals.generals[general_index]
	var advisor_index := int(data.get("advisor", -1))
	if advisor_index >= 0 and advisor_index < state.advisors.advisors.size():
		expedition.advisor = state.advisors.advisors[advisor_index]
	for index in data.get("squads", []):
		if int(index) >= 0 and int(index) < state.army.squads.size():
			expedition.squads.append(state.army.squads[int(index)])
	expedition.stages = int(data.get("stages", 1))
	expedition.ambushes = int(data.get("ambushes", 1))
	expedition.stage = int(data.get("stage", 0))
	expedition.wins = int(data.get("wins", 0))
	expedition.failed = bool(data.get("failed", false))
	expedition.cleared_before = int(data.get("cleared_before", 0))
	expedition.size_factor = float(data.get("size_factor", 1.0))
	for resource_id: String in data.get("resources", {}):
		expedition.resources[StringName(resource_id)] = int(data.resources[resource_id])
	for entry: Dictionary in data.get("items", []):
		expedition.items.append(Item.from_save(entry))
	expedition.log.assign(data.get("log", []))
	expedition.accept_duels = bool(data.get("accept_duels", true))
	expedition.team_morale_next = int(data.get("team_morale_next", 0))
	expedition.rebel_morale_next = int(data.get("rebel_morale_next", 0))
	return expedition
