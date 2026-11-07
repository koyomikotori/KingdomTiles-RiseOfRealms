class_name Stockpile
extends RefCounted
## Resources the kingdom currently holds. Amounts never go below zero.

signal changed

var _amounts: Dictionary[StringName, int] = {}


func get_amount(resource_id: StringName) -> int:
	return _amounts.get(resource_id, 0)


## Copy of every held amount.
func get_all() -> Dictionary[StringName, int]:
	return _amounts.duplicate()


func add(amounts: Dictionary[StringName, int]) -> void:
	for resource_id in amounts:
		assert(amounts[resource_id] >= 0, "Use spend() to remove resources")
		_amounts[resource_id] = get_amount(resource_id) + amounts[resource_id]
	changed.emit()


func can_afford(cost: Dictionary[StringName, int]) -> bool:
	for resource_id in cost:
		if get_amount(resource_id) < cost[resource_id]:
			return false
	return true


## Returns false and changes nothing when the cost cannot be paid in full.
func spend(cost: Dictionary[StringName, int]) -> bool:
	if not can_afford(cost):
		return false
	for resource_id in cost:
		_amounts[resource_id] = _amounts.get(resource_id, 0) - cost[resource_id]
	changed.emit()
	return true


func to_save() -> Dictionary:
	var result := {}
	for resource_id in _amounts:
		result[String(resource_id)] = _amounts[resource_id]
	return result


func load_save(data: Dictionary) -> void:
	_amounts.clear()
	for resource_name: String in data:
		_amounts[StringName(resource_name)] = int(data[resource_name])
	changed.emit()
