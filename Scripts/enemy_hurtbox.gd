extends Area2D

func take_hit(
	damage: int,
	attacker_position: Vector2,
	attack_kind: StringName = &"",
	combo_position: int = 0
) -> void:
	var enemy := get_parent()
	if enemy != null and enemy.has_method("take_hit"):
		enemy.take_hit(
			damage,
			attacker_position,
			attack_kind,
			combo_position
		)
