class_name RaidSystem
extends RefCounted
## Random bandit raids (GDD §7.2): chance per turn, bandit army, battle and its consequences.

## Bandits wear brown rags in battle (GDD §13).
const BANDIT_COLOR := Color(0.5, 0.36, 0.24)


## Weight of a late unit (RaidData.late_units) once it has joined the bandits.
const LATE_UNIT_WEIGHT := 1.5


## Chance (0..1) that bandits raid at the start of `state.turn`: it grows every 10 turns (GDD §15).
## Watchtowers only help when their upkeep was paid at the end of the previous turn.
static func get_raid_chance(state: KingdomState, raid: RaidData) -> float:
	if state.turn < raid.first_turn:
		return 0.0
	var grown := raid.base_chance + raid.chance_per_ten_turns * floori(state.turn / 10.0)
	# The cap only limits the growth: a base chance above it stays as it is.
	var chance := maxf(raid.base_chance, minf(raid.max_chance, grown))
	if state.buildings_supplied:
		for building_id in state.buildings:
			var building := state.buildings[building_id]
			chance -= building.raid_chance_reduction * state.board.count_buildings(building_id)
	return maxf(0.0, chance)


static func create_bandit_side(raid: RaidData, enemy_units: Dictionary[StringName, UnitData],
		turn: int, rng: RandomNumberGenerator, scale: float = 1.0) -> BattleSide:
	var squad_count := raid.base_squads + floori(turn * raid.squads_per_turn)
	var ids: Array[StringName] = []
	var weights := PackedFloat32Array()
	for unit_id in raid.unit_weights:
		ids.append(unit_id)
		weights.append(raid.unit_weights[unit_id])
	for unit_id in raid.late_units:
		if turn >= raid.late_units[unit_id]:
			ids.append(unit_id)
			weights.append(LATE_UNIT_WEIGHT)
	var picked := {}
	for i in squad_count:
		var unit_id := ids[rng.rand_weighted(weights)]
		picked[unit_id] = picked.get(unit_id, 0) + 1
	var side := BattleSide.new("Quân cướp")
	side.color = BANDIT_COLOR
	for unit_id in enemy_units:  # enemy_units is in sort order
		for i in picked.get(unit_id, 0):
			side.add_unit(enemy_units[unit_id], maxi(1, roundi(enemy_units[unit_id].squad_size * scale)))
	return side


## The kingdom's whole army as a battle side, one battle unit per squad.
static func create_kingdom_side(state: KingdomState) -> BattleSide:
	var side := BattleSide.new(state.kingdom_name)
	side.color = state.player_color
	for squad in state.army.squads:
		if not squad.away:
			side.add_unit(state.units[squad.unit_id], squad.soldiers, squad)
	return side


## Fights the raid with nobody retreating. The bandits attack, the kingdom defends.
static func resolve(state: KingdomState, raid: RaidData, bandits: BattleSide, seed_value: int) -> Dictionary:
	var kingdom := create_kingdom_side(state)
	return apply_outcome(state, raid, BattleSimulator.simulate(bandits, kingdom, seed_value))


## Applies a finished raid battle to the kingdom (GDD §7.6):
## - kingdom wins: every squad keeps its survivors; reward per bandit squad;
## - kingdom loses: broken or wiped squads are lost, the others keep 50%; 30% of resources lost.
## Returns {"record", "won", "casualties", "scattered", "retreat_losses" (unit_id -> soldiers each),
##          "resources_lost", "reward"}.
static func apply_outcome(state: KingdomState, raid: RaidData, record: BattleRecord) -> Dictionary:
	var won := record.winner == BattleRecord.DEFENDER
	state.generals.survival = state.building_effect(&"commander_survival")
	var losses := BattleOutcome.apply_to_army(state.army, record, BattleRecord.DEFENDER, false,
			state.building_effect(&"retreat_keep"))
	var resources_lost: Dictionary[StringName, int] = {}
	var reward: Dictionary[StringName, int] = {}
	if won:
		for resource_id in raid.reward_per_squad:
			reward[resource_id] = raid.reward_per_squad[resource_id] * record.sides[BattleRecord.ATTACKER].units.size()
		state.stockpile.add(reward)
	else:
		for resource_id in state.stockpile.get_all():
			var amount := floori(state.stockpile.get_amount(resource_id) * raid.resource_loss_on_defeat
					* (1.0 - state.plunder_protection()))
			if amount > 0:
				resources_lost[resource_id] = amount
		state.stockpile.spend(resources_lost)
	return {"record": record, "won": won, "casualties": losses.casualties, "scattered": losses.scattered,
			"retreat_losses": losses.retreat_losses, "resources_lost": resources_lost, "reward": reward}
