class_name AttackCatalog
extends RefCounted

const LIGHT_PATH: String = "res://core/combat/data/attacks/light.tres"
const HEAVY_PATH: String = "res://core/combat/data/attacks/heavy.tres"
const SPECIAL_PATH: String = "res://core/combat/data/attacks/special.tres"


static func get_attack(attack_id: StringName) -> AttackData:
	var resource_path: String = ""
	match attack_id:
		&"light":
			resource_path = LIGHT_PATH
		&"heavy":
			resource_path = HEAVY_PATH
		&"special":
			resource_path = SPECIAL_PATH
		_:
			push_warning("AttackCatalog: unknown attack id '%s'" % String(attack_id))
			return null

	var template := load(resource_path) as AttackData
	if template == null:
		push_error("AttackCatalog: failed to load %s" % resource_path)
		return null
	return template.duplicate(true) as AttackData


static func get_all_attacks() -> Array[AttackData]:
	var result: Array[AttackData] = []
	for attack_id in [&"light", &"heavy", &"special"]:
		var attack := get_attack(attack_id)
		if attack != null:
			result.append(attack)
	return result


static func contains(attack_id: StringName) -> bool:
	return attack_id == &"light" or attack_id == &"heavy" or attack_id == &"special"
