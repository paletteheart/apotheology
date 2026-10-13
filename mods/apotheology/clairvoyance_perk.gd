extends "res://main/entity/behaviors/level/perks/perk.gd"

@export var amount: int = 1

func activate() -> void:
	Engine.get_meta("apotheology").ajna += amount

func get_description() -> String:
	return base_description % amount

func is_available() -> bool:
	var apo: Node = Engine.get_meta("apotheology")
	return apo.is_progression_enabled() and not apo.is_ajna_maxed()
