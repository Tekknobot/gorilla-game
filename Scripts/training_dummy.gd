extends Area2D

signal health_changed(current: int, maximum: int)
signal respawned(maximum: int)

@export var max_health := 8
var health := 8
var respawn_timer := 0.0
var base_position := Vector2.ZERO

@onready var body: Polygon2D = $Body
@onready var face: Polygon2D = $Face
@onready var label: Label = $Label

func _ready() -> void:
	health = max_health
	base_position = position
	health_changed.emit(health, max_health)

func _process(delta: float) -> void:
	if respawn_timer > 0.0:
		respawn_timer -= delta
		if respawn_timer <= 0.0:
			visible = true
			monitoring = true
			health = max_health
			position = base_position
			modulate = Color.WHITE
			health_changed.emit(health, max_health)
			respawned.emit(max_health)

func take_hit(damage: int, attacker_position: Vector2) -> void:
	if health <= 0:
		return
	health = max(health - damage, 0)
	var direction = sign(global_position.x - attacker_position.x)
	position.x += direction * 7.0
	modulate = Color(1.0, 0.58, 0.58, 1.0)
	var tween := create_tween()
	tween.tween_property(self, "modulate", Color.WHITE, 0.12)
	health_changed.emit(health, max_health)
	if health <= 0:
		monitoring = false
		var drop := create_tween()
		drop.set_parallel(true)
		drop.tween_property(self, "rotation", direction * 1.25, 0.22)
		drop.tween_property(self, "position:y", position.y + 28.0, 0.22)
		drop.set_parallel(false)
		drop.tween_callback(_hide_for_respawn)

func _hide_for_respawn() -> void:
	visible = false
	rotation = 0.0
	respawn_timer = 1.4
