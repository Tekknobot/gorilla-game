extends CharacterBody2D

signal health_changed(current: int, maximum: int)
signal respawned(maximum: int)

const FRAME_SIZE := Vector2(48.0, 48.0)
const GRAVITY := 1550.0
const MAX_FALL_SPEED := 900.0
const WALK_SPEED := 72.0
const GROUND_ACCEL := 650.0
const FRICTION := 900.0
const CHASE_RANGE := 390.0
const ATTACK_RANGE := 74.0

const ATTACK_TIME := 0.52
const HURT_TIME := 0.34
const DEATH_TIME := 0.78
const DEATH_HOLD_TIME := 0.55

const ATTACK_COOLDOWN := 0.70
const RESPAWN_TIME := 1.45
const KNOCKBACK_SPEED := 155.0
const DEATH_KNOCKBACK_MULT := 0.72

# Per-attack reactions. These values are intentionally different so the
# gorilla's attacks read as distinct strikes instead of one generic hit.
const JAB_STUN := 0.16
const HOOK_STUN := 0.24
const UPPERCUT_STUN := 0.38
const ATTACK_2_STUN := 0.30
const SLAM_STUN := 0.50

const HIT_FLASH_TIME := 0.10
const HIT_FLASH_COLOR := Color(1.0, 0.15, 0.15, 1.0)

@export var max_health := 8

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var body_shape: CollisionShape2D = $CollisionShape2D
@onready var hurtbox: Area2D = $Hurtbox
@onready var hurt_shape: CollisionShape2D = $Hurtbox/CollisionShape2D
@onready var attack_hitbox: Area2D = $AttackHitbox
@onready var attack_shape: CollisionShape2D = $AttackHitbox/CollisionShape2D

var target: Node2D
var health := 8
var facing := 1.0
var state_name: StringName = &"IDLE"
var action_timer := 0.0
var cooldown_timer := 0.0
var respawn_timer := 0.0
var spawn_position := Vector2.ZERO
var defeated := false
var attack_connected := false
var hurt_duration := HURT_TIME
var hurt_requires_ground := false

var hit_flash_tween: Tween

func _ready() -> void:
	spawn_position = global_position
	health = max_health

	_build_sprite_frames()

	attack_hitbox.body_entered.connect(_on_attack_body_entered)
	_set_attack_hitbox(false)

	_play(&"idle")
	health_changed.emit(health, max_health)


func set_target(new_target: Node2D) -> void:
	target = new_target


func _physics_process(delta: float) -> void:
	cooldown_timer = max(cooldown_timer - delta, 0.0)

	# Hidden enemy is waiting to respawn.
	if respawn_timer > 0.0:
		respawn_timer -= delta
		if respawn_timer <= 0.0:
			_respawn()
		return

	if not is_on_floor():
		velocity.y = min(velocity.y + GRAVITY * delta, MAX_FALL_SPEED)

	match state_name:
		&"HURT":
			_update_hurt(delta)
		&"ATTACK":
			_update_attack(delta)
		&"DEATH":
			_update_death(delta)
		_:
			_update_ai(delta)

	move_and_slide()


func _update_ai(delta: float) -> void:
	if defeated:
		return

	if not is_instance_valid(target):
		velocity.x = move_toward(velocity.x, 0.0, FRICTION * delta)
		state_name = &"IDLE"
		_play(&"idle")
		return

	var dx := target.global_position.x - global_position.x
	var distance = abs(dx)

	if distance > 2.0:
		facing = sign(dx)
		sprite.flip_h = facing < 0.0

	if distance <= ATTACK_RANGE and cooldown_timer <= 0.0 and is_on_floor():
		_start_attack()
		return

	if distance <= CHASE_RANGE and distance > ATTACK_RANGE * 0.82:
		state_name = &"WALK"
		velocity.x = move_toward(
			velocity.x,
			facing * WALK_SPEED,
			GROUND_ACCEL * delta
		)
		_play(&"walk")
	else:
		state_name = &"IDLE"
		velocity.x = move_toward(velocity.x, 0.0, FRICTION * delta)
		_play(&"idle")


func _start_attack() -> void:
	if defeated:
		return

	state_name = &"ATTACK"
	action_timer = 0.0
	attack_connected = false
	velocity.x = 0.0
	_play(&"attack", true)


func _update_attack(delta: float) -> void:
	action_timer += delta
	velocity.x = move_toward(velocity.x, 0.0, FRICTION * delta)

	var progress = clamp(action_timer / ATTACK_TIME, 0.0, 1.0)
	var active = progress >= 0.48 and progress <= 0.70

	_set_attack_hitbox(active)

	if active:
		attack_hitbox.position.x = facing * 37.0

		for body in attack_hitbox.get_overlapping_bodies():
			_try_hit_player(body)

	if action_timer >= ATTACK_TIME:
		_set_attack_hitbox(false)
		cooldown_timer = ATTACK_COOLDOWN
		state_name = &"IDLE"
		_play(&"idle")


func _update_hurt(delta: float) -> void:
	action_timer += delta

	# Knockback eases out while hitstun keeps AI and attacks locked.
	velocity.x = move_toward(
		velocity.x,
		0.0,
		FRICTION * 0.55 * delta
	)

	if action_timer < hurt_duration:
		return

	# Launching attacks keep the enemy stunned until they touch down, allowing
	# uppercuts and slams to read as real knockback rather than animation swaps.
	if hurt_requires_ground and not is_on_floor():
		return

	hurt_requires_ground = false
	state_name = &"IDLE"
	_play(&"idle")


func _update_death(delta: float) -> void:
	action_timer += delta

	# Let the lethal hit carry the enemy a short distance, then settle.
	velocity.x = move_toward(
		velocity.x,
		0.0,
		FRICTION * 0.42 * delta
	)

	# death is non-looping, so AnimatedSprite2D naturally holds its final frame.
	# Leave the body visible for a short beat before beginning the respawn delay.
	if action_timer >= DEATH_TIME + DEATH_HOLD_TIME:
		_hide_for_respawn()


func take_hit(
	damage: int,
	attacker_position: Vector2,
	attack_kind: StringName = &"",
	combo_position: int = 0
) -> void:
	if defeated or respawn_timer > 0.0:
		return

	health = max(health - damage, 0)
	health_changed.emit(health, max_health)

	_flash_hit()
	_set_attack_hitbox(false)

	var direction = sign(global_position.x - attacker_position.x)
	if direction == 0.0:
		direction = -facing

	if health <= 0:
		_start_death(direction)
		return

	_apply_hit_reaction(attack_kind, direction, combo_position)
	state_name = &"HURT"
	action_timer = 0.0
	_play(&"hurt", true)


func _apply_hit_reaction(
	attack_kind: StringName,
	direction: float,
	combo_position: int
) -> void:
	hurt_requires_ground = false
	hurt_duration = HURT_TIME

	match attack_kind:
		&"combo_jab", &"attack_1":
			hurt_duration = JAB_STUN
			velocity.x = direction * 95.0
			velocity.y = min(velocity.y, -25.0)

		&"combo_hook":
			hurt_duration = HOOK_STUN
			velocity.x = direction * 185.0
			velocity.y = -55.0

		&"combo_uppercut":
			if combo_position >= 3:
				# Finisher: true launcher.
				hurt_duration = UPPERCUT_STUN
				hurt_requires_ground = true
				velocity.x = direction * 125.0
				velocity.y = -330.0
			else:
				# Early random-start uppercut: readable pop without ejecting the
				# enemy from the rest of the three-hit string.
				hurt_duration = 0.22
				velocity.x = direction * 95.0
				velocity.y = -95.0

		&"attack_2":
			hurt_duration = ATTACK_2_STUN
			velocity.x = direction * 205.0
			velocity.y = -90.0

		&"slam":
			hurt_duration = SLAM_STUN
			hurt_requires_ground = true
			velocity.x = direction * 235.0
			velocity.y = -155.0

		_:
			hurt_duration = HURT_TIME
			velocity.x = direction * KNOCKBACK_SPEED


func _start_death(knockback_direction: float) -> void:
	if defeated:
		return

	defeated = true
	state_name = &"DEATH"
	action_timer = 0.0
	attack_connected = false

	# A lethal strike gets a slightly softer knockback so the death animation
	# remains readable instead of sliding too far across the arena.
	velocity.x = knockback_direction * KNOCKBACK_SPEED * DEATH_KNOCKBACK_MULT

	# The corpse keeps its CharacterBody collision while the death animation
	# plays, but it can no longer attack or receive more combat hits.
	_set_attack_hitbox(false)
	hurtbox.monitoring = false
	hurtbox.monitorable = false

	_play(&"death", true)


func _hide_for_respawn() -> void:
	visible = false
	velocity = Vector2.ZERO

	collision_layer = 0
	collision_mask = 0

	hurtbox.monitoring = false
	hurtbox.monitorable = false

	_set_attack_hitbox(false)

	respawn_timer = RESPAWN_TIME


func _respawn() -> void:
	global_position = spawn_position
	velocity = Vector2.ZERO

	health = max_health
	defeated = false

	visible = true
	collision_layer = 1
	collision_mask = 1

	hurtbox.monitoring = true
	hurtbox.monitorable = true

	cooldown_timer = 0.35
	action_timer = 0.0
	attack_connected = false
	hurt_duration = HURT_TIME
	hurt_requires_ground = false

	sprite.self_modulate = Color.WHITE

	state_name = &"IDLE"
	_play(&"idle", true)

	health_changed.emit(health, max_health)
	respawned.emit(max_health)
	
func _set_attack_hitbox(enabled: bool) -> void:
	attack_shape.disabled = not enabled
	attack_hitbox.monitoring = enabled


func _on_attack_body_entered(body: Node2D) -> void:
	_try_hit_player(body)


func _try_hit_player(body: Node2D) -> void:
	if defeated:
		return

	if attack_connected or state_name != &"ATTACK":
		return

	if body.has_method("receive_enemy_hit"):
		attack_connected = true
		body.receive_enemy_hit(1, global_position)

func _flash_hit() -> void:
	# Restart the flash cleanly if several hits land rapidly.
	if hit_flash_tween != null and hit_flash_tween.is_valid():
		hit_flash_tween.kill()

	sprite.self_modulate = HIT_FLASH_COLOR

	hit_flash_tween = create_tween()
	hit_flash_tween.set_trans(Tween.TRANS_QUAD)
	hit_flash_tween.set_ease(Tween.EASE_OUT)

	hit_flash_tween.tween_property(
		sprite,
		"self_modulate",
		Color.WHITE,
		HIT_FLASH_TIME
	)
	
func _play(animation: StringName, restart := false) -> void:
	if restart or sprite.animation != animation:
		sprite.play(animation)


func _build_sprite_frames() -> void:
	var frames := SpriteFrames.new()

	for name in frames.get_animation_names():
		frames.remove_animation(name)

	var idle := load(
		"res://Sprites/Humans/Sheets/dude_idle.png"
	) as Texture2D

	var walk := load(
		"res://Sprites/Humans/Sheets/dude_walk.png"
	) as Texture2D

	var attack := load(
		"res://Sprites/Humans/Sheets/dude_attack.png"
	) as Texture2D

	var hurt := load(
		"res://Sprites/Humans/Sheets/dude_hurt.png"
	) as Texture2D

	var death := load(
		"res://Sprites/Humans/Sheets/dude_death.png"
	) as Texture2D

	_add_strip_anim(
		frames,
		&"idle",
		idle,
		7.0,
		true
	)

	_add_strip_anim(
		frames,
		&"walk",
		walk,
		10.0,
		true
	)

	_add_strip_anim_timed(
		frames,
		&"attack",
		attack,
		ATTACK_TIME,
		false
	)

	_add_strip_anim_timed(
		frames,
		&"hurt",
		hurt,
		HURT_TIME,
		false
	)

	_add_strip_anim_timed(
		frames,
		&"death",
		death,
		DEATH_TIME,
		false
	)

	sprite.sprite_frames = frames


func _strip_frame_count(texture: Texture2D) -> int:
	if texture == null:
		return 0

	var cell_width := int(FRAME_SIZE.x)
	var count := int(texture.get_width() / cell_width)

	if texture.get_width() % cell_width != 0:
		push_warning(
			"Human sprite strip width %d is not divisible by %d; trailing pixels will be ignored."
			% [texture.get_width(), cell_width]
		)

	return max(count, 1)


func _strip_order(texture: Texture2D) -> Array:
	var order: Array = []

	for index in range(_strip_frame_count(texture)):
		order.append(index)

	return order


func _atlas(texture: Texture2D, frame_index: int) -> AtlasTexture:
	var atlas := AtlasTexture.new()
	atlas.atlas = texture

	atlas.region = Rect2(
		Vector2(
			frame_index * int(FRAME_SIZE.x),
			0
		),
		FRAME_SIZE
	)

	return atlas


func _add_strip_anim(
	frames: SpriteFrames,
	name: StringName,
	texture: Texture2D,
	fps: float,
	looped: bool
) -> void:
	_add_anim(
		frames,
		name,
		texture,
		_strip_order(texture),
		fps,
		looped
	)


func _add_strip_anim_timed(
	frames: SpriteFrames,
	name: StringName,
	texture: Texture2D,
	duration: float,
	looped: bool
) -> void:
	var count := _strip_frame_count(texture)
	var fps = float(count) / max(duration, 0.001)

	_add_anim(
		frames,
		name,
		texture,
		_strip_order(texture),
		fps,
		looped
	)


func _add_anim(
	frames: SpriteFrames,
	name: StringName,
	texture: Texture2D,
	order: Array,
	fps: float,
	looped: bool
) -> void:
	frames.add_animation(name)
	frames.set_animation_speed(name, max(fps, 1.0))
	frames.set_animation_loop(name, looped)

	for index in order:
		frames.add_frame(
			name,
			_atlas(texture, int(index))
		)
