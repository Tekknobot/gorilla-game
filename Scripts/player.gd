extends CharacterBody2D

signal attack_landed(kind: StringName, damage: int)

const FRAME_SIZE := Vector2(96.0, 96.0)
const WALK_SPEED := 125.0
const RUN_SPEED := 235.0
const GROUND_ACCEL := 1150.0
const AIR_ACCEL := 720.0
const FRICTION := 1500.0
const GRAVITY := 1550.0
const MAX_FALL_SPEED := 900.0
const JUMP_SPEED := -555.0
const JUMP_CUT_MULT := 0.48
const COYOTE_TIME := 0.12
const JUMP_BUFFER_TIME := 0.13

# Target gameplay timings. Sprite FPS is calculated from the actual number of
# frames in each strip, so longer replacement strips use every frame without
# making the move unexpectedly longer.
const LAND_TIME := 0.32
const ATTACK_1_TIME := 0.54
const ATTACK_2_TIME := 0.70

# Primary attack combo: the first strike is randomized between jab, hook,
# and uppercut. Additional quick presses continue through the three attacks
# in circular order. Frame rate is derived from each strip's frame count.
const JAB_TIME := 0.26
const HOOK_TIME := 0.32
const UPPERCUT_TIME := 0.40

const SLAM_TIME := 0.40
const ROLL_TIME := 0.50

const ROLL_SPEED := 360.0

# Combat feel tuning.
const PLAYER_HITSTUN := 0.20
const HITBOX_JAB := Vector2(58.0, 38.0)
const HITBOX_HOOK := Vector2(72.0, 52.0)
const HITBOX_UPPERCUT := Vector2(54.0, 78.0)
const HITBOX_ATTACK_2 := Vector2(78.0, 58.0)
const HITBOX_SLAM := Vector2(112.0, 46.0)

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var hitbox: Area2D = $AttackHitbox
@onready var hit_shape: CollisionShape2D = $AttackHitbox/CollisionShape2D
@onready var body_shape: CollisionShape2D = $CollisionShape2D

var state_name: StringName = &"IDLE"
var facing := 1.0
var coyote_timer := 0.0
var jump_buffer := 0.0
var land_timer := 0.0
var action_timer := 0.0
var action_duration := 0.0
var action_kind: StringName = &""

# Combo state. Extra rapid presses are buffered, so a fast triple-tap can
# execute a full three-hit sequence from whichever attack was chosen first.
var combo_step := -1
var combo_hits_done := 0
var combo_buffered_inputs := 0
var current_attack_damage := 1
var attack_box_offset := Vector2(48.0, 6.0)
var player_hitstun_timer := 0.0
var impact_tween: Tween

var roll_direction := 1.0
var was_on_floor := false
var hit_targets: Dictionary = {}
var dead := false
var spawn_position := Vector2.ZERO

func _ready() -> void:
	spawn_position = global_position
	_build_sprite_frames()
	hitbox.area_entered.connect(_on_attack_area_entered)
	_set_hitbox(false)
	_play(&"idle")

func _physics_process(delta: float) -> void:
	if Input.is_action_just_pressed("respawn"):
		_respawn()
		return

	if dead:
		velocity.x = move_toward(velocity.x, 0.0, FRICTION * delta)
		if not is_on_floor():
			velocity.y = min(velocity.y + GRAVITY * delta, MAX_FALL_SPEED)
		move_and_slide()
		return

	if Input.is_action_just_pressed("debug_death"):
		_start_death()
		return

	if player_hitstun_timer > 0.0:
		player_hitstun_timer = max(player_hitstun_timer - delta, 0.0)
		velocity.x = move_toward(velocity.x, 0.0, FRICTION * 0.45 * delta)
		if not is_on_floor():
			velocity.y = min(velocity.y + GRAVITY * delta, MAX_FALL_SPEED)
		move_and_slide()
		if player_hitstun_timer <= 0.0:
			if is_on_floor():
				state_name = &"IDLE"
				_play(&"idle")
			else:
				state_name = &"FALL"
				_play(&"fall")
		return

	was_on_floor = is_on_floor()
	coyote_timer = COYOTE_TIME if is_on_floor() else max(coyote_timer - delta, 0.0)
	jump_buffer = max(jump_buffer - delta, 0.0)
	land_timer = max(land_timer - delta, 0.0)

	if Input.is_action_just_pressed("jump"):
		jump_buffer = JUMP_BUFFER_TIME

	if action_kind != &"":
		_update_action(delta)
	else:
		_read_actions()
		if action_kind == &"":
			_update_locomotion(delta)

	if not is_on_floor() and action_kind != &"slam":
		velocity.y = min(velocity.y + GRAVITY * delta, MAX_FALL_SPEED)

	move_and_slide()

	if not was_on_floor and is_on_floor() and action_kind == &"":
		land_timer = LAND_TIME
		state_name = &"LAND"
		_play(&"land")

	_update_visual_state()

func _read_actions() -> void:
	if Input.is_action_just_pressed("roll") and is_on_floor():
		_start_action(&"roll")
		return
	if Input.is_action_just_pressed("slam"):
		_start_action(&"slam")
		return
	if Input.is_action_just_pressed("attack_secondary") and is_on_floor():
		_start_action(&"attack_2")
		return
	if Input.is_action_just_pressed("attack_primary") and is_on_floor():
		_start_combo()
		return

func _update_locomotion(delta: float) -> void:
	var axis := Input.get_axis("move_left", "move_right")
	if abs(axis) > 0.08:
		facing = sign(axis)
		sprite.flip_h = facing < 0.0

	var running := Input.is_action_pressed("run")
	var target_speed := axis * (RUN_SPEED if running else WALK_SPEED)
	var accel := GROUND_ACCEL if is_on_floor() else AIR_ACCEL

	if abs(axis) > 0.08:
		velocity.x = move_toward(velocity.x, target_speed, accel * delta)
	elif is_on_floor():
		velocity.x = move_toward(velocity.x, 0.0, FRICTION * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, AIR_ACCEL * 0.18 * delta)

	if jump_buffer > 0.0 and coyote_timer > 0.0:
		jump_buffer = 0.0
		coyote_timer = 0.0
		land_timer = 0.0
		velocity.y = JUMP_SPEED
		state_name = &"JUMP"
		_play(&"jump")

	if Input.is_action_just_released("jump") and velocity.y < -80.0:
		velocity.y *= JUMP_CUT_MULT

func _start_combo() -> void:
	# Plant the gorilla immediately when a combo begins.
	velocity.x = 0.0

	# Random start: 0 = jab, 1 = hook, 2 = uppercut.
	combo_step = randi_range(0, 2)
	combo_hits_done = 1
	combo_buffered_inputs = 0

	_start_combo_step(combo_step)

func _start_combo_step(step: int) -> void:
	combo_step = posmod(step, 3)

	match combo_step:
		0:
			_start_action(&"combo_jab")
		1:
			_start_action(&"combo_hook")
		2:
			_start_action(&"combo_uppercut")

func _is_combo_action(kind: StringName) -> bool:
	return kind == &"combo_jab" or kind == &"combo_hook" or kind == &"combo_uppercut"

func _start_action(kind: StringName) -> void:
	action_kind = kind
	action_timer = 0.0
	hit_targets.clear()
	land_timer = 0.0
	_set_hitbox(false)
	_configure_attack_hitbox(kind)

	if not _is_combo_action(kind):
		combo_step = -1
		combo_hits_done = 0
		combo_buffered_inputs = 0

	match kind:
		&"combo_jab":
			state_name = &"JAB"
			_play(&"combo_jab")
			action_duration = _animation_duration(&"combo_jab")
		&"combo_hook":
			state_name = &"HOOK"
			_play(&"combo_hook")
			action_duration = _animation_duration(&"combo_hook")
		&"combo_uppercut":
			state_name = &"UPPERCUT"
			_play(&"combo_uppercut")
			action_duration = _animation_duration(&"combo_uppercut")
		&"attack_1":
			state_name = &"ATTACK 1"
			_play(&"attack_1")
			action_duration = _animation_duration(&"attack_1")
		&"attack_2":
			state_name = &"ATTACK 2"
			_play(&"attack_2")
			action_duration = _animation_duration(&"attack_2")
		&"slam":
			state_name = &"SLAM"
			_play(&"slam")
			action_duration = _animation_duration(&"slam")
			if not is_on_floor():
				velocity.y = 690.0
		&"roll":
			state_name = &"ROLL"
			roll_direction = facing
			var axis := Input.get_axis("move_left", "move_right")
			if abs(axis) > 0.08:
				roll_direction = sign(axis)
				facing = roll_direction
				sprite.flip_h = facing < 0.0
			velocity.x = roll_direction * ROLL_SPEED
			sprite.rotation = 0.0
			_play(&"roll")
			action_duration = _animation_duration(&"roll")
		_:
			action_duration = 0.1

func _update_action(delta: float) -> void:
	action_timer += delta
	var p = clamp(action_timer / max(action_duration, 0.001), 0.0, 1.0)

	# Buffer additional primary-attack presses. A very fast triple-tap during
	# the jab can queue both the hook and uppercut.
	if _is_combo_action(action_kind) and Input.is_action_just_pressed("attack_primary"):
		var remaining_hits := 3 - combo_hits_done
		if remaining_hits > 0:
			combo_buffered_inputs = min(combo_buffered_inputs + 1, remaining_hits)

	match action_kind:
		&"combo_jab":
			_apply_attack_root_motion(p, 0.08, 0.34, 55.0, 2200.0, delta)
			_attack_window(p, 0.25, 0.58, 1)

		&"combo_hook":
			_apply_attack_root_motion(p, 0.10, 0.40, 82.0, 2100.0, delta)
			_attack_window(p, 0.30, 0.64, 1)

		&"combo_uppercut":
			_apply_attack_root_motion(p, 0.12, 0.43, 70.0, 2000.0, delta)
			_attack_window(p, 0.34, 0.72, 2)
		&"attack_1":
			_apply_attack_root_motion(p, 0.10, 0.36, 62.0, 2100.0, delta)
			_attack_window(p, 0.31, 0.58, 1)
		&"attack_2":
			_apply_attack_root_motion(p, 0.15, 0.50, 88.0, 1900.0, delta)
			_attack_window(p, 0.43, 0.72, 2)
		&"slam":
			if not is_on_floor():
				velocity.x = move_toward(velocity.x, 0.0, 1200.0 * delta)
				velocity.y = min(velocity.y + GRAVITY * 1.75 * delta, 1050.0)
			else:
				velocity.x = move_toward(velocity.x, 0.0, 2000.0 * delta)
			_attack_window(p, 0.40, 0.62, 3)
		&"roll":
			velocity.x = roll_direction * lerp(ROLL_SPEED, 145.0, p)
			# Roll sheet supplies the rotation visually; do not rotate the node.
			# sprite.rotation = roll_direction * TAU * p

	if action_timer >= action_duration:
		_finish_action()

func _apply_attack_root_motion(
	progress: float,
	move_start: float,
	move_finish: float,
	speed: float,
	accel: float,
	delta: float
) -> void:
	# Authored movement gives punches weight without returning full movement
	# control during the attack.
	if progress >= move_start and progress <= move_finish:
		velocity.x = move_toward(velocity.x, facing * speed, accel * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, accel * 1.25 * delta)


func _configure_attack_hitbox(kind: StringName) -> void:
	var size := Vector2(64.0, 58.0)
	attack_box_offset = Vector2(48.0, 6.0)

	match kind:
		&"combo_jab", &"attack_1":
			size = HITBOX_JAB
			attack_box_offset = Vector2(46.0, 2.0)
		&"combo_hook":
			size = HITBOX_HOOK
			attack_box_offset = Vector2(48.0, 4.0)
		&"combo_uppercut":
			size = HITBOX_UPPERCUT
			attack_box_offset = Vector2(36.0, -12.0)
		&"attack_2":
			size = HITBOX_ATTACK_2
			attack_box_offset = Vector2(50.0, 5.0)
		&"slam":
			size = HITBOX_SLAM
			attack_box_offset = Vector2(30.0, 28.0)

	var rect := hit_shape.shape as RectangleShape2D
	if rect != null:
		rect.size = size


func _attack_window(progress: float, start: float, finish: float, damage: int) -> void:
	var active := progress >= start and progress <= finish
	current_attack_damage = damage
	_set_hitbox(active)

	if active:
		hitbox.position = Vector2(facing * attack_box_offset.x, attack_box_offset.y)

		# Poll overlaps as well as listening for area_entered. This guarantees a
		# target can be hit once by jab, once by hook, and once by uppercut even
		# if it never physically leaves the hitbox between combo stages.
		for area in hitbox.get_overlapping_areas():
			_try_hit_area(area)

func _finish_action() -> void:
	_set_hitbox(false)
	sprite.rotation = 0.0

	# Seamlessly advance to the next buffered combo strike.
	# The order wraps: jab -> hook -> uppercut -> jab.
	if (
		_is_combo_action(action_kind)
		and combo_buffered_inputs > 0
		and combo_hits_done < 3
		and is_on_floor()
	):
		combo_buffered_inputs -= 1
		combo_hits_done += 1
		_start_combo_step(combo_step + 1)
		return

	if _is_combo_action(action_kind):
		combo_step = -1
		combo_hits_done = 0
		combo_buffered_inputs = 0

	action_kind = &""
	action_timer = 0.0
	action_duration = 0.0

	if is_on_floor():
		state_name = &"IDLE"
		_play(&"idle")
	else:
		state_name = &"FALL"
		_play(&"fall")

func _update_visual_state() -> void:
	if dead or action_kind != &"":
		return
	if land_timer > 0.0:
		return

	if not is_on_floor():
		if velocity.y < -70.0:
			state_name = &"JUMP"
			_play(&"jump")
		else:
			state_name = &"FALL"
			_play(&"fall")
		return

	var speed = abs(velocity.x)
	if speed < 12.0:
		state_name = &"IDLE"
		_play(&"idle")
	elif speed < 175.0:
		state_name = &"WALK"
		_play(&"walk")
	else:
		state_name = &"RUN"
		_play(&"run")

func _start_death() -> void:
	dead = true
	action_kind = &""
	combo_step = -1
	combo_hits_done = 0
	combo_buffered_inputs = 0
	_set_hitbox(false)
	sprite.rotation = 0.0
	state_name = &"DEATH"
	velocity.x = 0.0
	_play(&"death")

func _respawn() -> void:
	dead = false
	action_kind = &""
	combo_step = -1
	combo_hits_done = 0
	combo_buffered_inputs = 0
	global_position = spawn_position
	velocity = Vector2.ZERO
	sprite.rotation = 0.0
	sprite.flip_h = false
	facing = 1.0
	state_name = &"IDLE"
	_set_hitbox(false)
	_play(&"idle")


func receive_enemy_hit(_damage: int, attacker_position: Vector2) -> void:
	# Enemy hits interrupt attacks, apply a short input lock, knock the gorilla
	# away, and trigger the same global impact feedback used by player attacks.
	if dead or action_kind == &"roll":
		return

	_set_hitbox(false)
	action_kind = &""
	action_timer = 0.0
	action_duration = 0.0
	combo_step = -1
	combo_hits_done = 0
	combo_buffered_inputs = 0
	player_hitstun_timer = PLAYER_HITSTUN
	state_name = &"HURT"

	var direction = sign(global_position.x - attacker_position.x)
	if direction == 0.0:
		direction = -facing
	velocity.x = direction * 245.0
	velocity.y = -135.0

	var tween := create_tween()
	sprite.modulate = Color(1.0, 0.55, 0.55, 1.0)
	tween.tween_property(sprite, "modulate", Color.WHITE, 0.14)

	var scene := get_tree().current_scene
	if scene != null and scene.has_method("request_combat_impact"):
		scene.request_combat_impact(&"enemy_hit", global_position)


func _set_hitbox(enabled: bool) -> void:
	hit_shape.disabled = not enabled
	hitbox.monitoring = enabled

func _on_attack_area_entered(area: Area2D) -> void:
	_try_hit_area(area)

func _try_hit_area(area: Area2D) -> void:
	if action_kind == &"" or hit_targets.has(area):
		return

	if area.has_method("take_hit"):
		hit_targets[area] = true
		var combo_position := combo_hits_done if _is_combo_action(action_kind) else 0
		area.take_hit(
			current_attack_damage,
			global_position,
			action_kind,
			combo_position
		)
		attack_landed.emit(action_kind, current_attack_damage)
		_play_attack_impact(action_kind)

		var impact_position := area.global_position
		var scene := get_tree().current_scene
		if scene != null and scene.has_method("request_combat_impact"):
			scene.request_combat_impact(action_kind, impact_position)


func _play_attack_impact(kind: StringName) -> void:
	# A subtle one-frame squash/stretch reinforces contact without new artwork.
	if impact_tween != null and impact_tween.is_valid():
		impact_tween.kill()

	var impact_scale := Vector2(2.06, 1.94)
	match kind:
		&"combo_hook", &"attack_2":
			impact_scale = Vector2(2.10, 1.90)
		&"combo_uppercut":
			impact_scale = Vector2(1.95, 2.10)
		&"slam":
			impact_scale = Vector2(2.13, 1.87)

	sprite.scale = impact_scale
	impact_tween = create_tween()
	impact_tween.set_trans(Tween.TRANS_QUAD)
	impact_tween.set_ease(Tween.EASE_OUT)
	impact_tween.tween_property(sprite, "scale", Vector2(2.0, 2.0), 0.09)


func _play(animation: StringName) -> void:
	# Do not restart the same animation every physics tick. One-shots can play
	# through naturally and hold their final frame until the state changes.
	if sprite.animation != animation:
		sprite.play(animation)

func _build_sprite_frames() -> void:
	var frames := SpriteFrames.new()
	for name in frames.get_animation_names():
		frames.remove_animation(name)

	var idle := load("res://Sprites/Gorilla/Sheets/idle.png") as Texture2D
	var walk := load("res://Sprites/Gorilla/Sheets/walk.png") as Texture2D
	var run := load("res://Sprites/Gorilla/Sheets/run.png") as Texture2D
	var jump := load("res://Sprites/Gorilla/Sheets/jump.png") as Texture2D
	var fall := load("res://Sprites/Gorilla/Sheets/fall.png") as Texture2D
	var land := load("res://Sprites/Gorilla/Sheets/land.png") as Texture2D
	var attack := load("res://Sprites/Gorilla/Sheets/attack.png") as Texture2D
	var attack_2 := load("res://Sprites/Gorilla/Sheets/attack2.png") as Texture2D
	var jab := load("res://Sprites/Gorilla/Sheets/jab.png") as Texture2D
	var hook := load("res://Sprites/Gorilla/Sheets/hook.png") as Texture2D
	var uppercut := load("res://Sprites/Gorilla/Sheets/uppercut.png") as Texture2D
	var slam := load("res://Sprites/Gorilla/Sheets/slam.png") as Texture2D
	var roll := load("res://Sprites/Gorilla/Sheets/roll.png") as Texture2D
	var death := load("res://Sprites/Gorilla/Sheets/death.png") as Texture2D

	# Full-strip animations automatically use texture_width / 96 frames. This
	# is intentional: replacing a sheet with a longer strip no longer requires
	# editing a hard-coded frame-index list here.
	_add_strip_anim(frames, &"idle", idle, 8.0, true)
	_add_strip_anim(frames, &"walk", walk, 10.0, true)
	_add_strip_anim(frames, &"run", run, 14.0, true)
	_add_strip_anim(frames, &"jump", jump, 18.0, false)
	_add_strip_anim(frames, &"fall", fall, 10.0, false)
	_add_strip_anim_timed(frames, &"land", land, LAND_TIME, false)
	_add_strip_anim_timed(frames, &"attack_1", attack, ATTACK_1_TIME, false)
	_add_strip_anim_timed(frames, &"combo_jab", jab, JAB_TIME, false)
	_add_strip_anim_timed(frames, &"combo_hook", hook, HOOK_TIME, false)
	_add_strip_anim_timed(frames, &"combo_uppercut", uppercut, UPPERCUT_TIME, false)
	_add_strip_anim_timed(frames, &"slam", slam, SLAM_TIME, false)
	_add_strip_anim_timed(frames, &"roll", roll, ROLL_TIME, false)
	_add_strip_anim(frames, &"death", death, 9.0, false)
	_add_strip_anim_timed(
		frames,
		&"attack_2",
		attack_2,
		ATTACK_2_TIME,
		false
	)
	
	sprite.sprite_frames = frames

func _strip_frame_count(texture: Texture2D) -> int:
	if texture == null:
		return 0
	var cell_width := int(FRAME_SIZE.x)
	var count := int(texture.get_width() / cell_width)
	if texture.get_width() % cell_width != 0:
		push_warning("Sprite strip width %d is not divisible by %d; trailing pixels will be ignored." % [texture.get_width(), cell_width])
	return max(count, 1)

func _strip_order(texture: Texture2D) -> Array:
	var order: Array = []
	for index in range(_strip_frame_count(texture)):
		order.append(index)
	return order

func _atlas(texture: Texture2D, frame_index: int) -> AtlasTexture:
	var atlas := AtlasTexture.new()
	atlas.atlas = texture
	atlas.region = Rect2(Vector2(frame_index * int(FRAME_SIZE.x), 0), FRAME_SIZE)
	return atlas

func _add_strip_anim(frames: SpriteFrames, name: StringName, texture: Texture2D, fps: float, looped: bool) -> void:
	_add_anim(frames, name, texture, _strip_order(texture), fps, looped)

func _add_strip_anim_timed(frames: SpriteFrames, name: StringName, texture: Texture2D, duration: float, looped: bool) -> void:
	var count := _strip_frame_count(texture)
	var fps = float(count) / max(duration, 0.001)
	_add_anim(frames, name, texture, _strip_order(texture), fps, looped)

func _add_anim(frames: SpriteFrames, name: StringName, texture: Texture2D, order: Array, fps: float, looped: bool) -> void:
	frames.add_animation(name)
	frames.set_animation_speed(name, max(fps, 1.0))
	frames.set_animation_loop(name, looped)
	for index in order:
		frames.add_frame(name, _atlas(texture, int(index)))

func _animation_duration(name: StringName) -> float:
	var frames := sprite.sprite_frames
	if frames == null or not frames.has_animation(name):
		return 0.1
	var fps := frames.get_animation_speed(name)
	if fps <= 0.0:
		return 0.1
	return float(frames.get_frame_count(name)) / fps
