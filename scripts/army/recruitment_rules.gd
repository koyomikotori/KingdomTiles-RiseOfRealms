class_name RecruitmentRules
extends RefCounted
## Decides whether a squad may be recruited, and recruits it (paying its cost).

enum Result { OK, NEEDS_BUILDING, NEEDS_TERRAIN, ARMY_FULL, CANNOT_AFFORD }


## `capacity` is the most squads the kingdom may have (KingdomState.get_squad_capacity()); `cost`
## replaces the unit's recruit_cost when given (KingdomState.recruit_cost, M18d).
static func check(board: BoardData, stockpile: Stockpile, army: Army, capacity: int, unit: UnitData,
		cost: Dictionary[StringName, int] = {}) -> Result:
	if not missing_buildings(board, unit).is_empty():
		return Result.NEEDS_BUILDING
	for terrain_id in unit.required_terrain:
		if board.count_owned_terrain(terrain_id) < unit.required_terrain[terrain_id]:
			return Result.NEEDS_TERRAIN
	if army.count_squads() >= capacity:
		return Result.ARMY_FULL
	if not stockpile.can_afford(unit.recruit_cost if cost.is_empty() else cost):
		return Result.CANNOT_AFFORD
	return Result.OK


## The unit's required_buildings the kingdom lacks: building_id -> level needed.
static func missing_buildings(board: BoardData, unit: UnitData) -> Dictionary[StringName, int]:
	var missing: Dictionary[StringName, int] = {}
	for building_id in unit.required_buildings:
		if board.highest_building_level(building_id) < unit.required_buildings[building_id]:
			missing[building_id] = unit.required_buildings[building_id]
	return missing


## "Doanh trại cấp 3, Chuồng ngựa chiến cấp 2": the buildings in `levels` (building_id -> level).
static func describe_buildings(levels: Dictionary[StringName, int], buildings: Dictionary[StringName, BuildingData]) -> String:
	var parts: Array[String] = []
	for building_id in levels:
		var building: BuildingData = buildings.get(building_id)
		var name := building.display_name if building != null else String(building_id)
		parts.append(name if building == null or not building.is_upgradable() else "%s cấp %d" % [name, levels[building_id]])
	return ", ".join(parts)


## Recruits only when check() is OK; otherwise nothing changes and nothing is paid.
static func apply(board: BoardData, stockpile: Stockpile, army: Army, capacity: int, unit: UnitData,
		cost: Dictionary[StringName, int] = {}) -> Result:
	var result := check(board, stockpile, army, capacity, unit, cost)
	if result != Result.OK:
		return result
	stockpile.spend(unit.recruit_cost if cost.is_empty() else cost)
	army.add_squad(unit.unit_id, unit.squad_size)
	return Result.OK


## Player-facing reason. Needs the data dictionaries to name the missing building / terrain.
## NEEDS_BUILDING names every building the unit needs (not only the missing ones).
static func describe(result: Result, unit: UnitData, buildings: Dictionary[StringName, BuildingData],
		terrains: Dictionary[StringName, TerrainData]) -> String:
	match result:
		Result.OK:
			return "Có thể tuyển."
		Result.NEEDS_BUILDING:
			return "Cần %s." % describe_buildings(unit.required_buildings, buildings)
		Result.NEEDS_TERRAIN:
			var parts: Array[String] = []
			for terrain_id in unit.required_terrain:
				var terrain: TerrainData = terrains.get(terrain_id)
				parts.append("%d ô %s" % [unit.required_terrain[terrain_id],
						terrain.display_name if terrain != null else String(terrain_id)])
			return "Cần lãnh thổ có ít nhất %s." % ", ".join(parts)
		Result.ARMY_FULL:
			return "Đã đủ số đơn vị tối đa. Xây thêm doanh trại hoặc giải tán bớt đơn vị."
		Result.CANNOT_AFFORD:
			return "Không đủ tài nguyên."
	return ""
