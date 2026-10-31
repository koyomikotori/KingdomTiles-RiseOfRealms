class_name BattleSimulator
extends RefCounted
## Time-based auto-battle (GDD §7.6). Pure logic: no nodes, no animation.
## Call step() repeatedly (the battle screen does this every frame, more often when sped up),
## or simulate() to run a whole battle at once. retreat() ends the battle immediately.
##
## Timeline: military advisors try their stratagems on the first tick; guns fire one volley at GUN_TIME (artillery
## on every row; musketeers then march to the front row); archers fire at FIRST_ARROW_TIME and then every
## reload_time; melee lines clash at CONTACT_TIME with a one-off charge, then fight continuously.
## Spearmen shrug off part of a charge and hit cavalry harder (charge_resist); crossbows ignore part of
## the target's armor (armor_pierce) (GDD §8, M13).
## Casualties use attack / (attack + defense), so stats compare as ratios and never hit zero.
## Same seed + same armies (+ same retreat time) = same result.

const TICK := 0.1
const SNAPSHOT_INTERVAL := 0.5
const GUN_TIME := 0.5
const FIRST_ARROW_TIME := 1.5
const CONTACT_TIME := 3.0
const TIME_LIMIT := 120.0

# Each factor is multiplied by attack / (attack + defense), which is 0.5 when the stats are equal.
## Casualties caused per engaged soldier per second.
const MELEE_RATE := 0.035
## Casualties caused per soldier by the one-off charge.
const CHARGE_FACTOR := 0.12
## Casualties caused per archer per volley.
const ARROW_FACTOR := 0.15
## Casualties caused per gunner by the single gun volley.
const GUN_FACTOR := 0.4
## Morale lost each time a unit loses another 25% of its starting soldiers.
const MORALE_LOSS_PER_QUARTER := 3.0
## Each hit is scaled by a random factor in [1 - VARIANCE, 1 + VARIANCE].
const VARIANCE := 0.1

var record: BattleRecord
var time := 0.0
var finished := false

var _sides: Array[BattleSide] = []
var _rng := RandomNumberGenerator.new()
var _ticks := 0
## _hits[side][unit_index] = Array of [source Unit, casualties] collected during one tick.
var _hits: Array = []


func _init(attacker: BattleSide, defender: BattleSide, seed_value: int) -> void:
	_sides = [attacker, defender]
	_rng.seed = seed_value
	record = BattleRecord.new(attacker, defender)
	for side in _sides:
		for unit in side.units:
			unit.next_volley_at = FIRST_ARROW_TIME
	_snapshot()
	if attacker.alive_total() == 0 or defender.alive_total() == 0:
		var winner := BattleRecord.ATTACKER if defender.alive_total() == 0 else BattleRecord.DEFENDER
		_finish(winner, BattleRecord.EndReason.NO_ARMY)


## Runs a whole battle with nobody retreating.
static func simulate(attacker: BattleSide, defender: BattleSide, seed_value: int) -> BattleRecord:
	var simulator := BattleSimulator.new(attacker, defender, seed_value)
	while not simulator.finished:
		simulator.step()
	return simulator.record


## Advances the battle by one TICK.
func step() -> void:
	if finished:
		return
	_hits = [[], []]
	for s in 2:
		for unit in _sides[s].units:
			_hits[s].append([])
	if _ticks == 0:
		for s in 2:
			_use_stratagems(s)
	for s in 2:
		_fire_guns(s)
		_fire_arrows(s)
		_fight_melee(s)
	for s in 2:
		for i in _sides[s].units.size():
			_apply_hits(_sides[s].units[i], _hits[s][i])
	for s in 2:
		for i in _sides[s].units.size():
			_update_morale(s, i)
		_check_general(s)
	time += TICK
	_ticks += 1
	if _ticks % roundi(SNAPSHOT_INTERVAL / TICK) == 0:
		_snapshot()
	_check_end()


## The given side gives up: it loses, and its unbroken units escape (GDD §7.6).
func retreat(side: int) -> void:
	if finished:
		return
	record.retreated_side = side
	record.events.append({"time": time, "type": &"retreat", "side": side, "unit": -1})
	_finish(1 - side, BattleRecord.EndReason.RETREAT)


func is_melee_started() -> bool:
	return time >= CONTACT_TIME


## A ranged unit stops shooting once its row is the front line in melee.
func _is_in_melee(side: int, unit: BattleSide.Unit) -> bool:
	return is_melee_started() and unit.row == _sides[side].front_row()


## Each stratagem of the side's advisor works with Advisors.stratagem_chance (GDD §8, M11f).
## Only the ones that work are recorded (event "stratagem" with "stratagem" = its id).
func _use_stratagems(s: int) -> void:
	var side := _sides[s]
	for stratagem in side.stratagems:
		if _rng.randf() >= Advisors.stratagem_chance(side.strategy) + side.stratagem_bonus:
			continue
		var targets := _stratagem_targets(s, stratagem)
		if targets.is_empty():
			continue
		var points := side.strategy
		for unit in targets:
			var loss := stratagem.soldier_loss_base + stratagem.soldier_loss_per_point * points
			unit.soldiers = maxf(0.0, unit.soldiers * (1.0 - loss))
			unit.morale += stratagem.morale_base + stratagem.morale_per_point * points
			unit.attack_mult += stratagem.attack_base + stratagem.attack_per_point * points
			unit.defense_mult += stratagem.defense_base + stratagem.defense_per_point * points
			unit.range_mult = maxf(0.1, unit.range_mult + stratagem.range_base + stratagem.range_per_point * points)
		record.events.append({"time": time, "type": &"stratagem", "side": s, "unit": -1,
				"stratagem": stratagem.stratagem_id})


func _stratagem_targets(s: int, stratagem: StratagemData) -> Array[BattleSide.Unit]:
	var enemy := _sides[1 - s].active_units()
	var own := _sides[s].active_units()
	match stratagem.target:
		StratagemData.Target.ENEMY_LARGEST:
			var largest: Array[BattleSide.Unit] = []
			for unit in enemy:
				if largest.is_empty() or unit.alive() > largest[0].alive():
					largest = [unit]
			return largest
		StratagemData.Target.ENEMY_RANGED:
			return enemy.filter(func(u: BattleSide.Unit) -> bool: return u.data.is_ranged())
		StratagemData.Target.OWN_ALL:
			return own
		StratagemData.Target.OWN_FRONT:
			var front := _sides[s].front_row()
			return own.filter(func(u: BattleSide.Unit) -> bool: return u.row == front)
	return enemy


func _fire_guns(s: int) -> void:
	if time < GUN_TIME:
		return
	for i in _sides[s].units.size():
		var unit := _sides[s].units[i]
		if unit.is_active() and unit.data.attack_kind == UnitData.AttackKind.GUN and not unit.has_fired:
			unit.has_fired = true
			_ranged_attack(s, unit, GUN_FACTOR, unit.data.volley_all_rows)
			record.events.append({"time": time, "type": &"gun_volley", "side": s, "unit": i,
					"all_rows": unit.data.volley_all_rows})
			if unit.data.melee_after_volley:
				unit.row = UnitData.Row.FRONT


func _fire_arrows(s: int) -> void:
	for i in _sides[s].units.size():
		var unit := _sides[s].units[i]
		if not unit.is_active() or unit.data.attack_kind != UnitData.AttackKind.BOW:
			continue
		if time + 0.0001 < unit.next_volley_at or _is_in_melee(s, unit):
			continue
		unit.next_volley_at += unit.data.reload_time
		_ranged_attack(s, unit, ARROW_FACTOR, true)
		record.events.append({"time": time, "type": &"arrow_volley", "side": s, "unit": i})


## Arrows rain on every row; bullets hit the front row. Damage within a row is split by soldiers.
func _ranged_attack(s: int, source: BattleSide.Unit, factor: float, spread_over_rows: bool) -> void:
	var targets := _pick_targets(1 - s, spread_over_rows)
	for target_index in targets:
		var target := _sides[1 - s].units[target_index]
		var armor := target.data.armor * target.defense_mult * (1.0 - source.data.armor_pierce)
		var ratio := _ratio(source.range_attack(), armor)
		_hit(1 - s, target_index, source, source.alive() * source.data.damage_per_soldier * ratio * factor * targets[target_index])


## Every unit on the front line plus every melee unit behind it fights the enemy's front row.
func _fight_melee(s: int) -> void:
	if not is_melee_started():
		return
	var targets := _pick_targets(1 - s, false)
	if targets.is_empty():
		return
	for i in _sides[s].units.size():
		var unit := _sides[s].units[i]
		if not unit.is_active():
			continue
		if unit.data.is_ranged() and not _is_in_melee(s, unit) and not (unit.data.melee_after_volley and unit.has_fired):
			continue
		var charging := not unit.has_charged
		unit.has_charged = true
		if charging:
			record.events.append({"time": time, "type": &"charge", "side": s, "unit": i})
		for target_index in targets:
			var target := _sides[1 - s].units[target_index]
			var share: float = targets[target_index]
			var defense := target.melee_defense() * (1.0 - unit.defense_pierce)
			var attack := unit.melee_attack()
			if target.data.is_cavalry:
				attack *= 1.0 + unit.data.charge_resist
			var casualties := unit.alive() * _ratio(attack, defense) * MELEE_RATE * TICK
			if charging:
				casualties += unit.alive() * _ratio(unit.data.charge_attack * unit.charge_mult, defense) * CHARGE_FACTOR 						* (1.0 - target.data.charge_resist)
			_hit(1 - s, target_index, unit, casualties * unit.data.damage_per_soldier * share)


## Returns {unit_index: share}, shares summing to 1, over the enemy's active units.
func _pick_targets(side: int, all_rows: bool) -> Dictionary:
	var front := _sides[side].front_row()
	var rows := {}
	for i in _sides[side].units.size():
		var unit := _sides[side].units[i]
		if unit.is_active() and (all_rows or unit.row == front):
			if not rows.has(unit.row):
				rows[unit.row] = []
			rows[unit.row].append(i)
	var result := {}
	for row in rows:
		var row_alive := 0
		for i in rows[row]:
			row_alive += _sides[side].units[i].alive()
		for i in rows[row]:
			result[i] = float(_sides[side].units[i].alive()) / row_alive / rows.size()
	return result


func _ratio(attack: float, defense: float) -> float:
	var total := attack + defense
	return attack / total if total > 0.0 else 0.0


func _hit(side: int, unit_index: int, source: BattleSide.Unit, casualties: float) -> void:
	if casualties > 0.0:
		_hits[side][unit_index].append([source, casualties * _rng.randf_range(1.0 - VARIANCE, 1.0 + VARIANCE)])


## Casualties beyond the target's remaining soldiers are not credited as kills. A target with
## hit_points above 1 needs that many casualties per soldier.
func _apply_hits(target: BattleSide.Unit, unit_hits: Array) -> void:
	var total := 0.0
	for hit in unit_hits:
		total += hit[1]
	if total <= 0.0:
		return
	var killed := total / target.data.hit_points
	var effective := minf(1.0, target.soldiers / killed)
	for hit in unit_hits:
		hit[0].kills += hit[1] / target.data.hit_points * effective
	target.soldiers = maxf(0.0, target.soldiers - killed)


func _update_morale(s: int, i: int) -> void:
	var unit := _sides[s].units[i]
	if unit.broken:
		return
	var quarters_lost := floori(4.0 * unit.lost() / unit.start_soldiers)
	if quarters_lost > unit.morale_steps:
		unit.morale -= (quarters_lost - unit.morale_steps) * MORALE_LOSS_PER_QUARTER
		unit.morale_steps = quarters_lost
	if unit.alive() > 0 and unit.morale <= 0.0:
		unit.broken = true
		record.events.append({"time": time, "type": &"broken", "side": s, "unit": i})


## The commander falls once their bodyguard breaks or dies: every other unit of the side loses
## Generals.FALL_MORALE_LOSS morale (GDD §8, M11d).
func _check_general(s: int) -> void:
	var side := _sides[s]
	if side.general_fallen:
		return
	for i in side.units.size():
		var unit := side.units[i]
		if unit.is_general_guard and (unit.broken or unit.alive() == 0):
			side.general_fallen = true
			record.events.append({"time": time, "type": &"general_fallen", "side": s, "unit": i})
			for other in side.units:
				if other != unit and other.is_active():
					other.morale -= Generals.FALL_MORALE_LOSS
			return


func _check_end() -> void:
	var out := [_sides[0].active_units().is_empty(), _sides[1].active_units().is_empty()]
	if out[0] or out[1]:
		var winner: int
		if out[0] and out[1]:
			winner = _better_side()
		else:
			winner = BattleRecord.DEFENDER if out[0] else BattleRecord.ATTACKER
		_finish(winner, BattleRecord.EndReason.ALL_BROKEN)
	elif time >= TIME_LIMIT - 0.0001:
		# An attacker that has not won when time runs out has failed: the defender holds.
		_finish(BattleRecord.DEFENDER, BattleRecord.EndReason.TIME_LIMIT)


## Both sides broke at once: the higher fraction of soldiers left wins; ties go to the defender.
func _better_side() -> int:
	if _sides[0].fraction_alive() > _sides[1].fraction_alive():
		return BattleRecord.ATTACKER
	return BattleRecord.DEFENDER


func _finish(winner: int, reason: BattleRecord.EndReason) -> void:
	finished = true
	record.winner = winner
	record.end_reason = reason
	record.duration = time
	if record.snapshots.is_empty() or record.snapshots.back().time < time:
		_snapshot()


func _snapshot() -> void:
	var soldiers := [[], []]
	var morale := [[], []]
	for s in 2:
		for unit in _sides[s].units:
			soldiers[s].append(unit.alive())
			morale[s].append(unit.morale)
	record.snapshots.append({"time": time, "soldiers": soldiers, "morale": morale})
