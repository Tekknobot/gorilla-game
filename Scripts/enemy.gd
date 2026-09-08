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

# Palette-swap targets. Each color represents the main/light tone for that
# source ramp; the shader preserves the original pixel-art shading beneath it.
const SKIN_TONES = [
	Color8(242, 190, 160), # fair
	Color8(224, 165, 127), # light warm
	Color8(219, 153, 120), # original
	Color8(184, 120, 82),  # medium warm
	Color8(145, 88, 58),   # brown
	Color8(103, 61, 45),   # deep brown
	Color8(72, 43, 34),    # dark
]

const TOP_COLORS = [
	Color8(58, 78, 67),    # original field green
	Color8(48, 61, 85),    # navy
	Color8(88, 51, 57),    # burgundy
	Color8(104, 65, 48),   # rust
	Color8(44, 78, 82),    # teal
	Color8(73, 81, 52),    # olive
	Color8(66, 69, 73),    # charcoal
	Color8(54, 78, 105),   # faded blue
]

const PANTS_COLORS = [
	Color8(148, 132, 100), # original khaki
	Color8(82, 92, 112),   # denim
	Color8(86, 88, 91),    # charcoal
	Color8(116, 89, 67),   # brown
	Color8(104, 108, 73),  # olive
	Color8(158, 139, 103), # sand
	Color8(72, 78, 94),    # dark blue-grey
	Color8(105, 73, 69),   # muted maroon
]

@export var max_health := 8

@export_category("Lifecycle")
@export var auto_respawn := true

@export_category("Appearance")
@export var randomize_palette_on_spawn := true
@export var randomize_palette_on_respawn := true
@export_range(-1, 6, 1) var skin_variant := -1
@export_range(-1, 7, 1) var top_variant := -1
@export_range(-1, 7, 1) var pants_variant := -1
@export_range(0.0, 1.0, 0.05) var palette_strength := 1.0

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
var entering_arena := false
var has_attack_slot := false
var hurt_duration := HURT_TIME
var hurt_requires_ground := false

var hit_flash_tween: Tween
var palette_material: ShaderMaterial
var current_skin_variant := 2
var current_top_variant := 0
var current_pants_variant := 0

func _ready() -> void:
	spawn_position = global_position
	health = max_health
	add_to_group("human_enemies")

	_build_sprite_frames()
	_setup_palette_material()

	if randomize_palette_on_spawn:
		reroll_palette()
	else:
		_apply_selected_palette()

	attack_hitbox.body_entered.connect(_on_attack_body_entered)
	_set_attack_hitbox(false)

	_play(&"idle")
	health_changed.emit(health, max_health)


func set_target(new_target: Node2D) -> void:
	target = new_target


func begin_offscreen_entry() -> void:
	entering_arena = true
	cooldown_timer = randf_range(0.45, 1.0)


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

	if entering_arena:
		if distance > CHASE_RANGE * 0.72:
			facing = sign(dx)
			sprite.flip_h = facing < 0.0
			state_name = &"WALK"
			velocity.x = move_toward(
				velocity.x,
				facing * WALK_SPEED * 1.18,
				GROUND_ACCEL * delta
			)
			_play(&"walk")
			return

		entering_arena = false
		cooldown_timer = max(cooldown_timer, randf_range(0.20, 0.55))

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

	var scene = get_parent()
	if scene != null and scene.has_method("request_enemy_attack"):
		if not scene.request_enemy_attack(self):
			cooldown_timer = randf_range(0.12, 0.30)
			velocity.x = move_toward(velocity.x, 0.0, FRICTION * 0.08)
			return
		has_attack_slot = true

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
		_release_attack_slot()
		cooldown_timer = ATTACK_COOLDOWN + randf_range(0.0, 0.24)
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
		if auto_respawn:
			_hide_for_respawn()
		else:
			_release_attack_slot()
			queue_free()


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
	_release_attack_slot()

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
	_release_attack_slot()
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
	_release_attack_slot()
	visible = false
	velocity = Vector2.ZERO

	collision_layer = 0
	collision_mask = 0

	hurtbox.monitoring = false
	hurtbox.monitorable = false

	_set_attack_hitbox(false)

	respawn_timer = RESPAWN_TIME


func _respawn() -> void:
	_release_attack_slot()
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

	if randomize_palette_on_respawn:
		reroll_palette()

	state_name = &"IDLE"
	_play(&"idle", true)

	health_changed.emit(health, max_health)
	respawned.emit(max_health)
	
func _release_attack_slot() -> void:
	if not has_attack_slot:
		return

	var scene = get_parent()
	if scene != null and scene.has_method("release_enemy_attack"):
		scene.release_enemy_attack(self)

	has_attack_slot = false


func _setup_palette_material() -> void:
	# ShaderMaterial subresources are shared by default. Duplicate it so every
	# enemy instance can have its own palette without recoloring every enemy.
	if sprite.material is ShaderMaterial:
		palette_material = (sprite.material as ShaderMaterial).duplicate() as ShaderMaterial
		sprite.material = palette_material
		palette_material.set_shader_parameter("palette_strength", palette_strength)


func reroll_palette() -> void:
	if palette_material == null:
		_setup_palette_material()

	if skin_variant >= 0:
		current_skin_variant = skin_variant
	else:
		current_skin_variant = randi_range(0, SKIN_TONES.size() - 1)

	if top_variant >= 0:
		current_top_variant = top_variant
	else:
		current_top_variant = randi_range(0, TOP_COLORS.size() - 1)

	if pants_variant >= 0:
		current_pants_variant = pants_variant
	else:
		current_pants_variant = randi_range(0, PANTS_COLORS.size() - 1)

	_apply_palette(
		current_skin_variant,
		current_top_variant,
		current_pants_variant
	)


func _apply_selected_palette() -> void:
	current_skin_variant = 2
	current_top_variant = 0
	current_pants_variant = 0

	if skin_variant >= 0:
		current_skin_variant = skin_variant
	if top_variant >= 0:
		current_top_variant = top_variant
	if pants_variant >= 0:
		current_pants_variant = pants_variant

	_apply_palette(
		current_skin_variant,
		current_top_variant,
		current_pants_variant
	)


func _apply_palette(skin_index: int, top_index: int, pants_index: int) -> void:
	if palette_material == null:
		return

	skin_index = clampi(skin_index, 0, SKIN_TONES.size() - 1)
	top_index = clampi(top_index, 0, TOP_COLORS.size() - 1)
	pants_index = clampi(pants_index, 0, PANTS_COLORS.size() - 1)

	var skin: Color = SKIN_TONES[skin_index]
	var top: Color = TOP_COLORS[top_index]
	var pants: Color = PANTS_COLORS[pants_index]

	# Vector3 is intentional: the shader expects raw sRGB values so the pixel
	# palette math remains deterministic instead of receiving color-space hints.
	palette_material.set_shader_parameter(
		"skin_target",
		Vector3(skin.r, skin.g, skin.b)
	)
	palette_material.set_shader_parameter(
		"top_target",
		Vector3(top.r, top.g, top.b)
	)
	palette_material.set_shader_parameter(
		"pants_target",
		Vector3(pants.r, pants.g, pants.b)
	)
	palette_material.set_shader_parameter("palette_strength", palette_strength)


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
	
func _exit_tree() -> void:
	_release_attack_slot()


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
