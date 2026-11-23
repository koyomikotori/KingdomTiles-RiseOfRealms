class_name EndTurnReminder
extends RefCounted
## Unfinished business before the turn ends (GDD §34, M18g): what `items` finds is listed by
## EndTurnReminderWindow, each row jumping to where it is handled. Pure: reads the state only.

const PIECES := &"pieces"
const BUILDERS := &"builders"
const POINTS := &"points"
const RECRUIT := &"recruit"
const ARMIES := &"armies"


## [{key, text, officer (POINTS only)}], in the order shown.
static func items(state: KingdomState) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var pieces := state.hand.pieces.size()
	if pieces > 0:
		result.append({"key": PIECES, "text": "Còn %d mảnh đất chưa đặt (hết lượt sẽ mất)." % pieces})
	var free := state.builder_limit() - state.builders_busy()
	if free > 0:
		result.append({"key": BUILDERS, "text": "Còn %d đội thợ đang rảnh." % free})
	var officer := officer_with_points(state)
	if officer != null:
		result.append({"key": POINTS, "officer": officer,
				"text": "%s còn %d điểm chưa cộng." % [officer.name, officer.points]})
	if can_recruit(state):
		result.append({"key": RECRUIT, "text": "Còn chỗ cho %d đơn vị và đủ tiền tuyển lính." % (
				state.get_squad_capacity() - state.army.count_squads())})
	if state.realm.active:
		var waiting := state.realm.forces.filter(func(force: Realm.Force) -> bool: return not force.has_order()).size()
		if waiting > 0:
			result.append({"key": ARMIES, "text": "%d đạo quân đang chờ lệnh." % waiting})
	return result


## The first general or advisor with a level point they can still spend.
static func officer_with_points(state: KingdomState) -> Officer:
	for general in state.generals.generals:
		if state.generals.can_spend_point(general, &"might") or state.generals.can_spend_point(general, &"command"):
			return general
	for advisor in state.advisors.advisors:
		for stat in Advisors.STAT_IDS:
			if state.advisors.can_spend_point(advisor, stat):
				return advisor
	return null


## A free squad slot and at least one unit type that may be recruited now.
static func can_recruit(state: KingdomState) -> bool:
	var capacity := state.get_squad_capacity()
	if state.army.count_squads() >= capacity:
		return false
	for id: StringName in state.units:
		var unit: UnitData = state.units[id]
		if RecruitmentRules.check(state.board, state.stockpile, state.army, capacity, unit,
				state.recruit_cost(id)) == RecruitmentRules.Result.OK:
			return true
	return false
