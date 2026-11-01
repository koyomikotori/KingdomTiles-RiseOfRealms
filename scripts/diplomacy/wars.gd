class_name Wars
extends RefCounted
## War and peace between the kingdom and the clans (GDD §9.6, campaign rules §15): declarations,
## clan armies that regrow and grow stronger over time, invasions, peace talks and annexation.
## Only clans bordering the kingdom's territory on the campaign map (Diplomacy.borders) go to war
## with it. Pure logic, owned by KingdomState.

signal changed

enum DeclareResult { OK, ANNEXED, NOT_NEIGHBOR, ALREADY_AT_WAR, TRUCE }
enum AttackResult { OK, ANNEXED, NOT_AT_WAR, ALREADY_ATTACKED, NO_ARMY }
enum PeaceResult { OK, DECLINED, NOT_AT_WAR, ASKED_THIS_TURN, CANNOT_AFFORD }

## Relation the target drops to (at most) when the player declares war.
const DECLARE_RELATION := -60
const DECLARE_RELATION_DROP := 40
## Every other clan's relation change when the player declares war.
const DECLARE_OTHERS_PENALTY := -5
## Instead of DECLARE_OTHERS_PENALTY for the target's friends (ClanData.friends).
const DECLARE_FRIEND_PENALTY := -15
## Added to every other clan's change when the player breaks a treaty by declaring war (GDD §9.7).
const BETRAY_ALLY_PENALTY := -20
const BREAK_PACT_PENALTY := -20
## Chance per turn that a hostile neighbour declares war, by personality:
## PEACEFUL, AGGRESSIVE, MERCHANT, ISOLATED.
const AI_DECLARE_CHANCE: Array[float] = [0.02, 0.15, 0.05, 0.05]
## Same, for clans that are only Tense: only aggressive clans go to war that early.
const AI_DECLARE_CHANCE_TENSE: Array[float] = [0.0, 0.05, 0.0, 0.0]
## Share of its (current) maximum a clan's army regrows every turn.
const STRENGTH_REGEN_SHARE := 0.1
## Every clan's maximum grows by this share of its starting strength per turn, up to MAX_GROWTH more.
const GROWTH_PER_TURN := 0.01
const MAX_GROWTH := 1.0
const INVASION_CHANCE := 0.25
const INVASION_COOLDOWN := 3
## Share of its current soldiers a clan sends to invade.
const INVASION_SHARE := 0.6
## Owned cells lost on the clan's edge when an invasion wins.
const LAND_LOST_PER_DEFEAT := 6
## Share of each resource the invaders carry off when they win (bandits take 30%).
const INVASION_RESOURCE_LOSS := 0.4
## Loot per enemy soldier lost when the player's attack wins.
const LOOT_PER_SOLDIER: Dictionary[StringName, int] = {&"food": 1, &"wood": 1, &"stone": 1}
## Share of each resource paid when the player's attack fails.
const ATTACK_DEFEAT_COMPENSATION := 0.25
## A clan whose army falls below this share of its maximum surrenders and is annexed.
const ANNEX_THRESHOLD := 0.15
## Rows/columns of wild land the kingdom board gains for every CLANS_PER_EXPANSION annexations,
## on the sides in EXPANSION_ORDER (clockwise from the top) whatever the clans' direction,
## EXPANSION_LIMIT times at most (2 rounds: 12×12 → 20×20, after 16 annexations).
const ANNEX_EXPANSION := 2
const CLANS_PER_EXPANSION := 2
const EXPANSION_ORDER: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
const EXPANSION_LIMIT := 8
const PEACE_BASE_CHANCE := 0.1
const PEACE_LOSSES_WEIGHT := 0.8
const PEACE_TRIBUTE_PER_POINT := 100.0
const PEACE_MAX_CHANCE := 0.95
const PEACE_MIN_RELATION := -30
const TRUCE_TURNS := 10


## The kingdom's standing with one clan.
class Front:
	extends RefCounted
	var clan_id: StringName
	var at_war := false
	var annexed := false
	var strength: int
	var max_strength: int
	var truce_turns := 0
	var turns_since_invasion := 0
	var attacked_this_turn := false
	var peace_offered_this_turn := false

	func losses_share() -> float:
		return 1.0 - float(strength) / max_strength if max_strength > 0 else 1.0


var fronts: Dictionary[StringName, Front] = {}
## Soldiers per clan unit and in each clan's army against the standard squad (Difficulty, M14h).
var enemy_scale := 1.0

## How strong a clan is now (GDD §15 M14h), from its strength without the difficulty's scale:
## weak below MEDIUM_FROM, strong from STRONG_FROM. Clan officers follow it (ClanOfficers).
enum Tier { WEAK, MEDIUM, STRONG }
const MEDIUM_FROM := 150
const STRONG_FROM := 400
var _diplomacy: Diplomacy


func _init(diplomacy: Diplomacy) -> void:
	_diplomacy = diplomacy
	for clan_id in diplomacy.clans:
		var data := diplomacy.clans[clan_id].data
		var front := Front.new()
		front.clan_id = clan_id
		front.strength = data.military_strength
		front.max_strength = data.military_strength
		fronts[clan_id] = front


func at_war_with(clan_id: StringName) -> bool:
	return fronts[clan_id].at_war


## Next to the kingdom's territory on the campaign map (and not annexed).
func is_neighbor(clan_id: StringName) -> bool:
	return _diplomacy.borders(clan_id)


## The clan's maximum strength on `turn`: its starting strength, GROWTH_PER_TURN more every turn.
func max_strength_at(clan_id: StringName, turn: int) -> int:
	var base := _diplomacy.clans[clan_id].data.military_strength * enemy_scale
	return roundi(base * (1.0 + minf(MAX_GROWTH, GROWTH_PER_TURN * maxi(0, turn - 1))))


## A new game's difficulty: every clan starts at its scaled strength.
func set_enemy_scale(scale: float, turn: int = 1) -> void:
	enemy_scale = scale
	for clan_id in fronts:
		fronts[clan_id].max_strength = max_strength_at(clan_id, turn)
		fronts[clan_id].strength = fronts[clan_id].max_strength


func tier(clan_id: StringName) -> Tier:
	var strength := fronts[clan_id].strength / maxf(0.01, enemy_scale)
	if strength >= STRONG_FROM:
		return Tier.STRONG
	return Tier.MEDIUM if strength >= MEDIUM_FROM else Tier.WEAK


## Soldiers in one full clan or bandit unit of `unit` at this difficulty.
func squad_size(unit: UnitData) -> int:
	return maxi(1, roundi(unit.squad_size * enemy_scale))


func count_annexed() -> int:
	var total := 0
	for front in fronts.values():
		total += 1 if front.annexed else 0
	return total


# --- Declaring war ------------------------------------------------------------------------

func check_declare(clan_id: StringName) -> DeclareResult:
	var front := fronts[clan_id]
	if front.annexed:
		return DeclareResult.ANNEXED
	if not is_neighbor(clan_id):
		return DeclareResult.NOT_NEIGHBOR
	if front.at_war:
		return DeclareResult.ALREADY_AT_WAR
	if front.truce_turns > 0:
		return DeclareResult.TRUCE
	return DeclareResult.OK


## The player declares war: the target turns hostile and every other clan trusts the kingdom less,
## its friends most. Breaking an alliance or a non-aggression pact costs extra with everyone.
func declare_war(clan_id: StringName) -> DeclareResult:
	var result := check_declare(clan_id)
	if result != DeclareResult.OK:
		return result
	var clan := _diplomacy.clans[clan_id]
	_diplomacy.change_relation(clan_id, mini(clan.relation - DECLARE_RELATION_DROP, DECLARE_RELATION) - clan.relation,
			Diplomacy.MEMORY_WAR)
	for other in _diplomacy.clans:
		if other != clan_id:
			_diplomacy.change_relation(other, declare_penalty(clan_id, other), Diplomacy.MEMORY_AGGRESSION)
	_start_war(clan_id)
	return DeclareResult.OK


## Relation change for `other` if the player declared war on `clan_id` now.
func declare_penalty(clan_id: StringName, other: StringName) -> int:
	var clan := _diplomacy.clans[clan_id]
	var penalty := DECLARE_FRIEND_PENALTY if clan.data.friends.has(other) else DECLARE_OTHERS_PENALTY
	if clan.is_allied():
		penalty += BETRAY_ALLY_PENALTY
	if clan.has_pact():
		penalty += BREAK_PACT_PENALTY
	return penalty


func _start_war(clan_id: StringName) -> void:
	var front := fronts[clan_id]
	front.at_war = true
	front.turns_since_invasion = 0
	_diplomacy.clans[clan_id].alliance_turns = 0
	_diplomacy.clans[clan_id].pact_turns = 0
	_diplomacy.remove_agreement(clan_id)
	changed.emit()


## The clan declares war on the kingdom on its own (an event); false when it cannot right now
## (also never during a non-aggression pact).
func clan_declares_war(clan_id: StringName) -> bool:
	if check_declare(clan_id) != DeclareResult.OK or _diplomacy.clans[clan_id].has_pact():
		return false
	_start_war(clan_id)
	return true


## Regrowth share taken off a clan by the kingdom's agents (Agents.sabotage_on, GDD §8 M14e);
## unset in tests that build Wars alone.
var sabotage: Callable

## End of turn (`turn` is the turn that ends): armies grow stronger and regrow, truces count
## down, wars keep relations hostile, and hostile neighbours may declare war. Returns the clans
## that declared war this turn.
func end_turn(rng: RandomNumberGenerator, turn: int = 1) -> Array[StringName]:
	var declared: Array[StringName] = []
	for clan_id in fronts:
		var front := fronts[clan_id]
		if front.annexed:
			continue
		front.max_strength = max_strength_at(clan_id, turn + 1)
		var regen := maxf(0.0, STRENGTH_REGEN_SHARE - (sabotage.call(clan_id) if sabotage.is_valid() else 0.0))
		front.strength = mini(front.max_strength, front.strength + ceili(front.max_strength * regen))
		front.truce_turns = maxi(0, front.truce_turns - 1)
		front.turns_since_invasion += 1
		front.attacked_this_turn = false
		front.peace_offered_this_turn = false
		var clan := _diplomacy.clans[clan_id]
		if front.at_war:
			if clan.relation > DECLARE_RELATION:
				_diplomacy.change_relation(clan_id, DECLARE_RELATION - clan.relation, Diplomacy.MEMORY_WAR)
		elif check_declare(clan_id) == DeclareResult.OK and _declare_chance(clan_id) > 0.0 \
				and rng.randf() < _declare_chance(clan_id):
			_start_war(clan_id)
			declared.append(clan_id)
	changed.emit()
	return declared


## Chance this turn that the clan declares war on its own (0 unless Tense or Hostile, and never
## during a non-aggression pact).
func _declare_chance(clan_id: StringName) -> float:
	if _diplomacy.clans[clan_id].has_pact():
		return 0.0
	var personality := _diplomacy.clans[clan_id].data.personality
	match _diplomacy.get_tier(clan_id):
		Diplomacy.Tier.HOSTILE:
			return AI_DECLARE_CHANCE[personality]
		Diplomacy.Tier.TENSE:
			return AI_DECLARE_CHANCE_TENSE[personality]
	return 0.0


# --- Battles ------------------------------------------------------------------------------

## The clan (if any) that invades at the start of this turn; resets its invasion cooldown.
func pick_invader(rng: RandomNumberGenerator) -> StringName:
	var ids := fronts.keys()
	ids.sort()
	for clan_id: StringName in ids:
		var front := fronts[clan_id]
		if front.at_war and is_neighbor(clan_id) and front.strength > 0 \
				and front.turns_since_invasion >= INVASION_COOLDOWN and rng.randf() < INVASION_CHANCE:
			front.turns_since_invasion = 0
			return clan_id
	return &""


func invasion_size(clan_id: StringName) -> int:
	return roundi(fronts[clan_id].strength * INVASION_SHARE)


## The clan's soldiers as battle units, split by its army_units weights into squads.
func create_clan_side(clan_id: StringName, soldiers: int, units: Dictionary[StringName, UnitData]) -> BattleSide:
	var side := BattleSide.new(_diplomacy.clans[clan_id].data.display_name)
	side.color = _diplomacy.clans[clan_id].data.color
	add_clan_units(side, clan_id, soldiers, units)
	return side


## Adds `soldiers` of the clan to `side`. `lent` marks them as sent to help another army
## (BattleSide.Unit.ally), so their losses come out of this clan's strength.
func add_clan_units(side: BattleSide, clan_id: StringName, soldiers: int, units: Dictionary[StringName, UnitData],
		lent: bool = false) -> void:
	var data := _diplomacy.clans[clan_id].data
	var total_weight := 0.0
	for unit_id in data.army_units:
		total_weight += data.army_units[unit_id]
	if total_weight <= 0.0:
		return
	var remaining := soldiers
	var ids := data.army_units.keys()
	for i in ids.size():
		var unit: UnitData = units.get(ids[i])
		if unit == null:
			continue
		var share := remaining if i == ids.size() - 1 else roundi(soldiers * data.army_units[ids[i]] / total_weight)
		share = mini(share, remaining)
		remaining -= share
		while share > 0:
			var squad := mini(share, squad_size(unit))
			side.add_unit(unit, squad, null, data if lent else null)
			share -= squad


func lose_soldiers(clan_id: StringName, amount: int) -> void:
	var front := fronts[clan_id]
	front.strength = maxi(0, front.strength - amount)
	changed.emit()


## `has_army`: whether the kingdom has at least one squad.
func check_attack(clan_id: StringName, has_army: bool) -> AttackResult:
	var front := fronts[clan_id]
	if front.annexed:
		return AttackResult.ANNEXED
	if not front.at_war:
		return AttackResult.NOT_AT_WAR
	if front.attacked_this_turn:
		return AttackResult.ALREADY_ATTACKED
	if not has_army:
		return AttackResult.NO_ARMY
	return AttackResult.OK


func mark_attacked(clan_id: StringName) -> void:
	fronts[clan_id].attacked_this_turn = true
	changed.emit()


# --- Annexation ---------------------------------------------------------------------------

func should_annex(clan_id: StringName) -> bool:
	var front := fronts[clan_id]
	return front.at_war and front.strength < front.max_strength * ANNEX_THRESHOLD


## The clan surrenders and joins the kingdom; the clans around its square now border the kingdom.
## Returns the board side to add land to (EXPANSION_ORDER, clockwise from the top) on every
## CLANS_PER_EXPANSION-th annexation, otherwise (and once the board has grown EXPANSION_LIMIT
## times) Vector2i.ZERO.
func annex(clan_id: StringName) -> Vector2i:
	var front := fronts[clan_id]
	front.annexed = true
	front.at_war = false
	_diplomacy.clans[clan_id].annexed = true
	_diplomacy.clans[clan_id].alliance_turns = 0
	_diplomacy.remove_agreement(clan_id)
	changed.emit()
	var annexed := count_annexed()
	if annexed % CLANS_PER_EXPANSION != 0:
		return Vector2i.ZERO
	return expansion_side(annexed / CLANS_PER_EXPANSION - 1)


## Annexations still needed before the board next grows (0 once it has grown EXPANSION_LIMIT times).
func annexations_to_expand() -> int:
	var annexed := count_annexed()
	if annexed / CLANS_PER_EXPANSION >= EXPANSION_LIMIT:
		return 0
	return CLANS_PER_EXPANSION - annexed % CLANS_PER_EXPANSION


## The board side the `index`-th expansion (0-based) adds land to, or ZERO past EXPANSION_LIMIT.
static func expansion_side(index: int) -> Vector2i:
	if index >= EXPANSION_LIMIT:
		return Vector2i.ZERO
	return EXPANSION_ORDER[index % EXPANSION_ORDER.size()]


# --- Peace --------------------------------------------------------------------------------

func peace_chance(clan_id: StringName, tribute: Dictionary[StringName, int]) -> float:
	var front := fronts[clan_id]
	var chance := PEACE_BASE_CHANCE + PEACE_LOSSES_WEIGHT * front.losses_share() \
			+ _diplomacy.clans[clan_id].relation / 200.0 + _diplomacy.value_of(tribute) / PEACE_TRIBUTE_PER_POINT \
			+ _diplomacy.envoy * Diplomacy.ENVOY_CHANCE
	return clampf(chance, 0.0, PEACE_MAX_CHANCE)


func check_peace(stockpile: Stockpile, clan_id: StringName, tribute: Dictionary[StringName, int]) -> PeaceResult:
	var front := fronts[clan_id]
	if not front.at_war:
		return PeaceResult.NOT_AT_WAR
	if front.peace_offered_this_turn:
		return PeaceResult.ASKED_THIS_TURN
	if not stockpile.can_afford(tribute):
		return PeaceResult.CANNOT_AFFORD
	return PeaceResult.OK


## Offers peace (with optional tribute, paid only if accepted). Accepting ends the war, lifts the
## relation to at least Tense and starts a truce. One offer per clan per turn.
func propose_peace(rng: RandomNumberGenerator, stockpile: Stockpile, clan_id: StringName,
		tribute: Dictionary[StringName, int]) -> PeaceResult:
	var result := check_peace(stockpile, clan_id, tribute)
	if result != PeaceResult.OK:
		return result
	var front := fronts[clan_id]
	front.peace_offered_this_turn = true
	if rng.randf() >= peace_chance(clan_id, tribute):
		changed.emit()
		return PeaceResult.DECLINED
	stockpile.spend(tribute)
	front.at_war = false
	front.truce_turns = TRUCE_TURNS
	var relation := _diplomacy.clans[clan_id].relation
	if relation < PEACE_MIN_RELATION:
		_diplomacy.change_relation(clan_id, PEACE_MIN_RELATION - relation, Diplomacy.MEMORY_WAR)
	changed.emit()
	return PeaceResult.OK


static func describe_declare(result: DeclareResult) -> String:
	match result:
		DeclareResult.OK:
			return "Đã tuyên chiến!"
		DeclareResult.ANNEXED:
			return "Gia tộc này đã bị sáp nhập."
		DeclareResult.NOT_NEIGHBOR:
			return "Không giáp biên, chưa thể gây chiến."
		DeclareResult.ALREADY_AT_WAR:
			return "Đang chiến tranh."
		DeclareResult.TRUCE:
			return "Đang trong thời gian đình chiến."
	return ""


static func describe_attack(result: AttackResult) -> String:
	match result:
		AttackResult.OK:
			return "Sẵn sàng tấn công."
		AttackResult.ANNEXED:
			return "Gia tộc này đã bị sáp nhập."
		AttackResult.NOT_AT_WAR:
			return "Phải tuyên chiến trước khi tấn công."
		AttackResult.ALREADY_ATTACKED:
			return "Lượt này đã tấn công họ rồi."
		AttackResult.NO_ARMY:
			return "Bạn không có quân để tấn công."
	return ""


static func describe_peace(result: PeaceResult) -> String:
	match result:
		PeaceResult.OK:
			return "Họ chấp nhận nghị hòa! Đình chiến %d lượt." % TRUCE_TURNS
		PeaceResult.DECLINED:
			return "Họ từ chối nghị hòa. Hãy thử lại vào lượt sau."
		PeaceResult.NOT_AT_WAR:
			return "Không có chiến tranh."
		PeaceResult.ASKED_THIS_TURN:
			return "Lượt này đã đề nghị hòa rồi."
		PeaceResult.CANNOT_AFFORD:
			return "Không đủ tài nguyên để bồi thường."
	return ""


# --- Save (GDD §10.1) ---------------------------------------------------------------------

## Front fields written as they are (ints and bools). max_strength comes from the clan data and
## the turn (max_strength_at) so rebalancing applies to old saves.
const SAVED_FRONT_FIELDS: Array[StringName] = [&"at_war", &"annexed", &"strength", &"truce_turns",
		&"turns_since_invasion", &"attacked_this_turn", &"peace_offered_this_turn"]


func to_save() -> Dictionary:
	var result := {}
	for clan_id in fronts:
		var entry := {}
		for field in SAVED_FRONT_FIELDS:
			entry[String(field)] = fronts[clan_id].get(field)
		result[String(clan_id)] = entry
	return result


func load_save(data: Dictionary, turn: int = 1) -> void:
	for clan_id in fronts:
		fronts[clan_id].max_strength = max_strength_at(clan_id, turn)
	for clan_name: String in data:
		var front: Front = fronts.get(StringName(clan_name))
		if front == null:
			continue
		var entry: Dictionary = data[clan_name]
		for field in SAVED_FRONT_FIELDS:
			if entry.has(String(field)):
				front.set(field, Diplomacy._plain(entry[String(field)], front.get(field)))
		front.strength = mini(front.strength, front.max_strength)
	changed.emit()
