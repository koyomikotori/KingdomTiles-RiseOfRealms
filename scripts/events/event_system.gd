class_name EventSystem
extends RefCounted
## Random events (GDD §9c): rolls 0–3 events at the start of a turn among those whose conditions
## hold, keeps them pending until the player answers, then applies the chosen answer. Owned by
## KingdomState; takes the state as an argument instead of holding it (no reference cycle).

## Chance of 0, 1, 2 and 3 events at the start of a turn.
const COUNT_CHANCES: Array[float] = [0.5, 0.3, 0.15, 0.05]
## M16b. A choice's success chance never goes past this.
const MAX_CHANCE := 0.95
## An officer tempted by an enemy leaves with this chance, less per star.
const DEFECT_CHANCE := 0.5
const DEFECT_PER_STAR := 0.05
## Stars of a captured officer (lowest, highest) by the clan's Wars.Tier: weak, medium, strong.
const PRISONER_STARS: Array[Vector2i] = [Vector2i(1, 2), Vector2i(2, 3), Vector2i(3, 4)]
## needs_bandit_activity: a raid beaten within this many turns counts.
const BANDIT_RECENT_TURNS := 3
## Peasant squads that bandits who give up can become.
const PEASANT_UNITS: Array[StringName] = [&"swordsman", &"spearman", &"archer"]

var events: Dictionary[StringName, EventData] = EventData.load_all()
## Events waiting for an answer, oldest first: {"event_id", "clan_id"}.
var pending: Array[Dictionary] = []
## event_id -> turn it last happened (for cooldowns).
var last_turn: Dictionary[StringName, int] = {}
## Turn the kingdom last beat a bandit raid (KingdomState.finish_raid).
var raid_won_turn := -100
## Turn the kingdom last annexed a clan (KingdomState.finish_attack).
var annexed_turn := -100
## An event's outcome (force_raid): bandits come at the start of the next turn (M16b).
var raid_forced := false
var _resource_types: Array[ResourceTypeData] = ResourceTypeData.load_all()


## Start of a turn: adds 0–3 events to `pending` and returns the new entries.
func roll(state: KingdomState, rng: RandomNumberGenerator) -> Array[Dictionary]:
	var added: Array[Dictionary] = []
	var count := rng.rand_weighted(PackedFloat32Array(COUNT_CHANCES))
	var candidates: Array[EventData] = []
	for event_id in events:
		if can_happen(state, events[event_id]):
			candidates.append(events[event_id])
	for i in count:
		if candidates.is_empty():
			break
		var weights := PackedFloat32Array()
		for event in candidates:
			weights.append(event.weight)
		var event: EventData = candidates.pop_at(rng.rand_weighted(weights))
		var clan_id := pick_clan(state, event, rng)
		if event.needs_clan and clan_id == &"":
			continue
		last_turn[event.event_id] = state.turn
		var entry := {"event_id": event.event_id, "clan_id": clan_id}
		pending.append(entry)
		added.append(entry)
	return added


## Whether the event's conditions hold right now (its clan is checked by pick_clan).
func can_happen(state: KingdomState, event: EventData) -> bool:
	if state.turn < event.min_turn or state.turn - last_turn.get(event.event_id, -1000) < event.cooldown:
		return false
	for resource_id in event.min_stock:
		if state.stockpile.get_amount(resource_id) < event.min_stock[resource_id]:
			return false
	for terrain_id in event.min_terrain:
		if state.board.count_owned_terrain(terrain_id) < event.min_terrain[terrain_id]:
			return false
	if event.required_building != &"" and state.board.count_buildings(event.required_building) == 0:
		return false
	if state.army.count_squads() < event.min_squads:
		return false
	if event.needs_free_squad_slot and state.army.count_squads() >= state.get_squad_capacity():
		return false
	if event.needs_wounded_squad and not _has_wounded_squad(state):
		return false
	if event.needs_raid_won_last_turn and raid_won_turn != state.turn - 1:
		return false
	if event.needs_annexed_last_turn and annexed_turn != state.turn - 1:
		return false
	if event.needs_general_slot and state.generals.generals.size() >= Generals.MAX_GENERALS:
		return false
	if event.needs_war and not state.wars.fronts.values().any(func(front: Wars.Front) -> bool: return front.at_war):
		return false
	if home_generals(state).size() < event.min_generals_home or home_officers(state).size() < event.min_officers_home:
		return false
	if event.needs_production and production_origins(state).is_empty():
		return false
	if event.needs_raids and state.raid == null:
		return false
	if event.needs_bandit_activity and not state.uprising.is_active() \
			and state.turn - raid_won_turn > BANDIT_RECENT_TURNS:
		return false
	return not event.needs_clan or not _matching_clans(state, event).is_empty()


## A clan matching the event's filters, or &"" (also for events about no clan).
func pick_clan(state: KingdomState, event: EventData, rng: RandomNumberGenerator) -> StringName:
	if not event.needs_clan:
		return &""
	var clans := _matching_clans(state, event)
	return clans[rng.randi_range(0, clans.size() - 1)] if not clans.is_empty() else &""


func _matching_clans(state: KingdomState, event: EventData) -> Array[StringName]:
	var result: Array[StringName] = []
	var clan_ids: Array[StringName] = []
	clan_ids.assign(state.diplomacy.clans.keys())
	clan_ids.sort()
	for clan_id in clan_ids:
		var clan := state.diplomacy.clans[clan_id]
		var tier := state.diplomacy.get_tier(clan_id)
		if clan.annexed or tier < event.clan_min_tier or tier > event.clan_max_tier:
			continue
		if event.clan_must_be_allied and not clan.is_allied():
			continue
		var at_war := state.wars.at_war_with(clan_id)
		if (at_war and not event.clan_may_be_at_war and not event.clan_must_be_at_war) \
				or (event.clan_must_be_at_war and not at_war):
			continue
		if event.clan_must_have_agent and not _agent_can_strike(state, clan_id):
			continue
		if event.clan_must_be_stronger and state.wars.fronts[clan_id].strength <= state.army.count_soldiers():
			continue
		result.append(clan_id)
	return result


## An agent is on a mission in the clan, which fields a general or an advisor.
func _agent_can_strike(state: KingdomState, clan_id: StringName) -> bool:
	if state.agents.agent_on(clan_id) == null:
		return false
	state.clan_officers.ensure(clan_id, state.wars, state.difficulty)
	var staff := state.clan_officers.staff(clan_id)
	return staff.general != null or staff.advisor != null


static func home_generals(state: KingdomState) -> Array[Officer]:
	var result: Array[Officer] = []
	for general in state.generals.generals:
		if not general.away:
			result.append(general)
	return result


## Generals and advisors at home (not on an expedition).
static func home_officers(state: KingdomState) -> Array[Officer]:
	var result := home_generals(state)
	for advisor in state.advisors.advisors:
		if not advisor.away:
			result.append(advisor)
	return result


## Origins of the finished production buildings at work (farm, lumber mill, mine).
static func production_origins(state: KingdomState) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for cell in state.board.get_all_cells():
		if cell.owned and cell.has_building() and cell.coord == cell.building_origin and not cell.is_idle():
			var building: BuildingData = state.buildings.get(cell.building_id)
			if building != null and building.field_resource != &"":
				result.append(cell.coord)
	return result


static func defect_chance(officer: Officer) -> float:
	return maxf(0.0, DEFECT_CHANCE - DEFECT_PER_STAR * officer.stars)


func _has_wounded_squad(state: KingdomState) -> bool:
	for squad in state.army.squads:
		if squad.soldiers < state.units[squad.unit_id].squad_size:
			return true
	return false


## The oldest unanswered event, or null.
func current_event() -> EventData:
	return events.get(pending[0].event_id) if not pending.is_empty() else null


func current_clan() -> StringName:
	return pending[0].clan_id if not pending.is_empty() else &""


## The event's text with its clan's name filled in.
func fill(state: KingdomState, text: String, clan_id: StringName) -> String:
	return text.replace("{clan}", state.diplomacy.clans[clan_id].data.display_name) if clan_id != &"" else text


func can_choose(state: KingdomState, choice: EventChoiceData, clan_id: StringName = &"") -> bool:
	return block_reason(state, choice, clan_id).is_empty()


## Why the choice cannot be taken now ("" when it can).
func block_reason(state: KingdomState, choice: EventChoiceData, clan_id: StringName = &"") -> String:
	if not state.stockpile.can_afford(choice.cost):
		return "Không đủ tài nguyên."
	if choice.needs_officer_slot and state.generals.generals.size() >= Generals.MAX_GENERALS \
			and state.advisors.is_full():
		return "Đã đủ tướng và mưu sĩ, không còn chỗ."
	if choice.target_officer != &"" and clan_id != &"":
		var staff := state.clan_officers.staff(clan_id)
		if (staff.general if choice.target_officer == &"general" else staff.advisor) == null:
			return "Họ không có %s." % ("tướng" if choice.target_officer == &"general" else "mưu sĩ")
	return ""


## The choice's chance of its first outcome (M16b), or -1 when its outcomes go by weight.
func choice_chance(state: KingdomState, choice: EventChoiceData, clan_id: StringName = &"") -> float:
	if choice.success_chance < 0.0:
		return -1.0
	var chance := choice.success_chance + choice.chance_per_police_level * state.police_level()
	var envoy := state.advisors.active(&"diplomacy")
	if envoy != null:
		chance += choice.chance_per_envoy_star * envoy.stars
	var agent := state.agents.agent_on(clan_id) if clan_id != &"" else null
	if agent != null:
		chance += choice.chance_per_agent_star * agent.stars
	return clampf(chance, 0.0, MAX_CHANCE)


## Answers the oldest pending event with choice `index`: pays its cost, rolls one outcome and
## applies it. Returns {"text": what happened, "changes": Array[String]} or {} when the choice
## cannot be afforded (nothing changes then).
func resolve(state: KingdomState, rng: RandomNumberGenerator, index: int) -> Dictionary:
	var event := current_event()
	var clan_id := current_clan()
	var choice := event.choices[index]
	if not can_choose(state, choice, clan_id):
		return {}
	pending.pop_front()
	var changes: Array[String] = []
	if not choice.cost.is_empty():
		state.stockpile.spend(choice.cost)
		changes.append("Đã trả: %s" % _amounts(choice.cost))
	if choice.outcomes.is_empty():
		return {"text": "", "changes": changes}
	var outcome: EventOutcomeData
	var chance := choice_chance(state, choice, clan_id)
	if chance >= 0.0 and choice.outcomes.size() >= 2:
		outcome = choice.outcomes[0 if rng.randf() < chance else 1]
	else:
		var weights := PackedFloat32Array()
		for entry in choice.outcomes:
			weights.append(entry.weight)
		outcome = choice.outcomes[rng.rand_weighted(weights)]
	_apply(state, outcome, clan_id, changes)
	_apply_war(state, rng, outcome, choice, clan_id, changes)
	return {"text": fill(state, outcome.text, clan_id), "changes": changes}


func _apply(state: KingdomState, outcome: EventOutcomeData, clan_id: StringName, changes: Array[String]) -> void:
	var gained: Dictionary[StringName, int] = {}
	var lost: Dictionary[StringName, int] = {}
	for resource_id in outcome.resources:
		var amount := outcome.resources[resource_id]
		if amount > 0:
			gained[resource_id] = amount
		elif amount < 0:
			lost[resource_id] = mini(-amount, state.stockpile.get_amount(resource_id))
	for resource_id in outcome.resource_loss:
		var amount := floori(state.stockpile.get_amount(resource_id) * outcome.resource_loss[resource_id])
		lost[resource_id] = lost.get(resource_id, 0) + amount
	state.stockpile.add(gained)
	state.stockpile.spend(lost)
	if not gained.is_empty():
		changes.append("Nhận: %s" % _amounts(gained))
	if lost.values().any(func(amount: int) -> bool: return amount > 0):
		changes.append("Mất: %s" % _amounts(lost))
	if clan_id != &"" and outcome.relation != 0:
		state.diplomacy.change_relation(clan_id, outcome.relation, Diplomacy.MEMORY_EVENT)
		changes.append("Quan hệ với %s %+d" % [_clan_name(state, clan_id), outcome.relation])
	if outcome.relation_all != 0:
		for other in state.diplomacy.clans:
			if not state.diplomacy.clans[other].annexed:
				state.diplomacy.change_relation(other, outcome.relation_all, Diplomacy.MEMORY_EVENT)
		changes.append("Quan hệ với mọi gia tộc %+d" % outcome.relation_all)
	if outcome.add_unit != &"" and outcome.add_soldiers > 0 and state.units.has(outcome.add_unit):
		var unit_name := state.units[outcome.add_unit].display_name
		if state.army.count_squads() < state.get_squad_capacity():
			state.army.add_squad(outcome.add_unit, outcome.add_soldiers)
			changes.append("Thêm 1 đơn vị %s (%d lính)" % [unit_name, outcome.add_soldiers])
		else:
			changes.append("Không còn chỗ cho thêm đơn vị %s" % unit_name)
	if outcome.army_loss > 0.0 and state.army.count_squads() > 0:
		var before := state.army.count_soldiers()
		for squad in state.army.squads.duplicate():
			state.army.set_soldiers(squad, floori(squad.soldiers * (1.0 - outcome.army_loss)))
		changes.append("Mất %d lính" % (before - state.army.count_soldiers()))
	if outcome.replenish > 0.0:
		var added := 0
		for squad in state.army.squads:
			var full := state.units[squad.unit_id].squad_size
			var gain := mini(ceili(full * outcome.replenish), full - squad.soldiers)
			if gain > 0:
				state.army.add_soldiers(squad, gain)
				added += gain
		if added > 0:
			changes.append("Bổ sung %d lính" % added)
	if outcome.extra_pieces > 0:
		state.hand.draw_extra(outcome.extra_pieces)
		changes.append("Thêm %d mảnh đất vào tay" % outcome.extra_pieces)
	if clan_id != &"" and outcome.clan_strength != 0:
		var front := state.wars.fronts[clan_id]
		front.strength = clampi(front.strength + outcome.clan_strength, 0, front.max_strength)
		changes.append("Quân %s %+d lính" % [_clan_name(state, clan_id), outcome.clan_strength])
	if clan_id != &"" and outcome.declare_war and state.wars.clan_declares_war(clan_id):
		changes.append("%s tuyên chiến với vương quốc!" % _clan_name(state, clan_id))
	if outcome.general_min_stars > 0:
		var stars := state.generals.rng.randi_range(outcome.general_min_stars, maxi(outcome.general_min_stars, outcome.general_max_stars))
		var general := state.generals.generate(stars)
		if state.generals.add(general):
			changes.append("Tướng %s %s gia nhập (Võ lực %d, Thống suất %d)" % [general.name, general.star_text(),
					general.might, general.command])
		else:
			changes.append("Không còn chỗ cho thêm tướng")
	if outcome.item_rarity >= 0:
		var item := state.equipment.create_random(outcome.item_rarity)
		var got := state.equipment.receive(item, state.stockpile)
		var refund: Dictionary[StringName, int] = got.refund
		changes.append("Nhận được %s (%s)%s" % [item.display_name, Item.RARITY_NAMES[item.rarity],
				", kho đầy nên đã phân rã lấy %s" % _amounts(refund) if not refund.is_empty() else ""])


## The M16b effects: officers leaving or joining, idle buildings, raids, peasants, assassinations.
func _apply_war(state: KingdomState, rng: RandomNumberGenerator, outcome: EventOutcomeData, choice: EventChoiceData,
		clan_id: StringName, changes: Array[String]) -> void:
	if outcome.general_leaves:
		var generals := home_generals(state)
		if not generals.is_empty():
			var general: Officer = generals[rng.randi_range(0, generals.size() - 1)]
			state.dismiss_officer(general)
			changes.append("Tướng %s đã bỏ đi" % general.name)
	if outcome.defection:
		var officers := home_officers(state)
		if not officers.is_empty():
			var officer: Officer = officers[rng.randi_range(0, officers.size() - 1)]
			if rng.randf() < defect_chance(officer):
				state.dismiss_officer(officer)
				changes.append("%s %s đã theo về phe địch" % ["Tướng" if officer is General else "Mưu sĩ", officer.name])
			else:
				changes.append("%s %s từ chối lời mời của địch" % ["Tướng" if officer is General else "Mưu sĩ", officer.name])
	if outcome.disable_max > 0:
		var origins := production_origins(state)
		var count := mini(rng.randi_range(outcome.disable_min, outcome.disable_max), origins.size())
		for i in count:
			var origin: Vector2i = origins.pop_at(rng.randi_range(0, origins.size() - 1))
			state.board.disable_building(origin, outcome.disable_turns)
		if count > 0:
			changes.append("%d công trình sản xuất bị bỏ hoang %d lượt" % [count, outcome.disable_turns])
	if outcome.force_raid and state.raid != null:
		raid_forced = true
		changes.append("Đạo tặc sẽ kéo đến ở lượt sau")
	if outcome.peasant_max > 0:
		for i in rng.randi_range(outcome.peasant_min, outcome.peasant_max):
			if state.army.count_squads() >= state.get_squad_capacity():
				changes.append("Không còn chỗ cho thêm đơn vị")
				break
			var unit_id: StringName = PEASANT_UNITS[rng.randi_range(0, PEASANT_UNITS.size() - 1)]
			state.army.add_squad(unit_id, state.units[unit_id].squad_size)
			changes.append("Thêm 1 đơn vị %s" % state.units[unit_id].display_name)
	if outcome.prisoner_joins and clan_id != &"":
		var stars_range := PRISONER_STARS[clampi(state.wars.tier(clan_id), 0, PRISONER_STARS.size() - 1)]
		var stars := rng.randi_range(stars_range.x, stars_range.y)
		var room_general := state.generals.generals.size() < Generals.MAX_GENERALS
		var as_general := room_general and (state.advisors.is_full() or rng.randf() < 0.5)
		if as_general:
			var general := state.generals.generate(stars)
			state.generals.add(general)
			changes.append("Tướng %s %s gia nhập" % [general.name, general.star_text()])
		elif not state.advisors.is_full():
			var advisor := state.advisors.generate(stars)
			state.advisors.add(advisor)
			changes.append("Mưu sĩ %s %s gia nhập" % [advisor.name, advisor.star_text()])
	if outcome.assassinate and clan_id != &"" and choice.target_officer != &"":
		var killed := rng.randf() < 0.5
		var target := state.clan_officers.assassinate(clan_id, choice.target_officer, killed)
		if target != "":
			changes.append("%s %s của %s %s" % ["Tướng" if choice.target_officer == &"general" else "Mưu sĩ", target,
					_clan_name(state, clan_id), "đã chết" if killed else "bị thương nặng"])
	if outcome.agent_exposed and clan_id != &"":
		var agent := state.agents.agent_on(clan_id)
		if agent != null:
			var killed := state.agents.expose(agent, state.diplomacy, rng.randf())
			changes.append("Đặc vụ %s bị lộ %s" % [agent.name, "và bị giết" if killed else "và phải trốn về"])
			changes.append("Quan hệ với %s %+d" % [_clan_name(state, clan_id), Agents.CAUGHT_RELATION])


func _amounts(amounts: Dictionary[StringName, int]) -> String:
	return UiFormat.amounts(amounts, _resource_types)


func _clan_name(state: KingdomState, clan_id: StringName) -> String:
	return state.diplomacy.clans[clan_id].data.display_name


# --- Save (GDD §10.1) ---------------------------------------------------------------------

func to_save() -> Dictionary:
	var turns := {}
	for event_id in last_turn:
		turns[String(event_id)] = last_turn[event_id]
	var waiting: Array = []
	for entry in pending:
		waiting.append({"event_id": String(entry.event_id), "clan_id": String(entry.clan_id)})
	return {"last_turn": turns, "pending": waiting, "raid_won_turn": raid_won_turn, "annexed_turn": annexed_turn,
			"raid_forced": raid_forced}


## Pending events that no longer exist in the data are dropped.
func load_save(data: Dictionary) -> void:
	last_turn.clear()
	for event_name: String in data.last_turn:
		last_turn[StringName(event_name)] = int(data.last_turn[event_name])
	pending.clear()
	for entry: Dictionary in data.pending:
		if events.has(StringName(entry.event_id)):
			pending.append({"event_id": StringName(entry.event_id), "clan_id": StringName(entry.clan_id)})
	raid_won_turn = int(data.raid_won_turn)
	annexed_turn = int(data.get("annexed_turn", -100))
	raid_forced = bool(data.get("raid_forced", false))
