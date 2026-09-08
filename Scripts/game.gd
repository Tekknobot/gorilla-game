extends Node2D

@onready var player = $Player
@onready var state_label: Label = $HUD/StateLabel
@onready var camera: Camera2D = $Camera2D
@onready var combo_label: Label = $HUD/ComboLabel
@onready var enemy_label: Label = $HUD/DummyLabel

const ENEMY_SCENE := preload("res://Scenes/enemy.tscn")
const IMPACT_BURST_SCRIPT := preload("res://Scripts/impact_burst.gd")
const SFX_LIGHT := preload("res://Audio/impact_light.wav")
const SFX_HEAVY := preload("res://Audio/impact_heavy.wav")
const SFX_SLAM := preload("res://Audio/impact_slam.wav")
const SFX_ENEMY := preload("res://Audio/enemy_hit.wav")

const ENEMY_FLOOR_Y := 472.0
const OFFSCREEN_LEFT_X := -88.0
const OFFSCREEN_RIGHT_X := 1240.0
const INITIAL_LEFT_SLOTS := [80.0, 155.0, 225.0]
const INITIAL_RIGHT_SLOTS := [590.0, 770.0, 950.0, 1080.0]

@export_category("Enemy Spawning")
@export_range(0, 12, 1) var initial_enemy_count := 6
@export_range(1, 20, 1) var max_active_enemies := 10
@export var enable_reinforcements := true
@export_range(1, 4, 1) var enemies_per_reinforcement := 2
@export_range(1.0, 12.0, 0.25) var reinforcement_min_delay := 3.5
@export_range(1.0, 15.0, 0.25) var reinforcement_max_delay := 5.5
@export_range(0.0, 5.0, 0.1) var first_reinforcement_delay := 2.25

@export_category("Brawler Crowd Rules")
@export_range(1, 4, 1) var max_simultaneous_attackers := 2

var enemies: Array[Node] = []
var tracked_enemy: Node
var active_attackers: Dictionary = {}
var reinforcement_timer := 0.0
var reinforcement_wave_index := 0

var hit_stop_serial := 0
var shake_strength := 0.0
var shake_end_msec := 0
var combo_hit_count := 0
var last_combo_hit_msec := 0
var combo_hide_msec := 0

func _ready() -> void:
	_configure_input()
	_spawn_initial_enemies()
	reinforcement_timer = first_reinforcement_delay

	if is_instance_valid(player) and player.has_signal("attack_landed"):
		player.attack_landed.connect(_on_player_attack_landed)

	_update_enemy_hud()


func _process(delta: float) -> void:
	if is_instance_valid(player):
		var pad_name := "Keyboard"
		var pads := Input.get_connected_joypads()
		if not pads.is_empty():
			pad_name = Input.get_joy_name(pads[0])

		state_label.text = "STATE  %s\nSPEED  %3d\nPAD    %s" % [
			player.state_name,
			int(abs(player.velocity.x)),
			pad_name
		]

	_update_camera_shake()
	_update_combo_counter()
	_update_enemy_spawning(delta)
	_cleanup_attack_slots()
	_update_enemy_hud()

	if Input.is_action_just_pressed("reroll_enemy_palette"):
		for enemy_node in _living_enemies():
			if enemy_node.has_method("reroll_palette"):
				enemy_node.call("reroll_palette")



func _configure_input() -> void:
	_set_action("move_left", 0.18, [
		_key(KEY_A), _key(KEY_LEFT), _joy_button(JOY_BUTTON_DPAD_LEFT), _joy_axis(JOY_AXIS_LEFT_X, -1.0)
	])
	_set_action("move_right", 0.18, [
		_key(KEY_D), _key(KEY_RIGHT), _joy_button(JOY_BUTTON_DPAD_RIGHT), _joy_axis(JOY_AXIS_LEFT_X, 1.0)
	])
	_set_action("jump", 0.2, [
		_key(KEY_SPACE), _key(KEY_W), _key(KEY_UP), _joy_button(JOY_BUTTON_A)
	])
	_set_action("run", 0.2, [
		_key(KEY_SHIFT), _joy_axis(JOY_AXIS_TRIGGER_RIGHT, 1.0), _joy_button(JOY_BUTTON_LEFT_STICK)
	])
	_set_action("attack_primary", 0.2, [
		_key(KEY_J), _joy_button(JOY_BUTTON_X)
	])
	_set_action("attack_secondary", 0.2, [
		_key(KEY_K), _joy_button(JOY_BUTTON_Y)
	])
	_set_action("slam", 0.2, [
		_key(KEY_L), _joy_button(JOY_BUTTON_RIGHT_SHOULDER)
	])
	_set_action("roll", 0.2, [
		_key(KEY_CTRL), _key(KEY_C), _joy_button(JOY_BUTTON_B)
	])
	_set_action("reroll_enemy_palette", 0.2, [
		_key(KEY_P)
	])
	_set_action("debug_death", 0.2, [
		_key(KEY_BACKSPACE), _joy_button(JOY_BUTTON_BACK)
	])
	_set_action("respawn", 0.2, [
		_key(KEY_R), _joy_button(JOY_BUTTON_START)
	])

func _set_action(action: StringName, deadzone: float, events: Array) -> void:
	if InputMap.has_action(action):
		InputMap.erase_action(action)
	InputMap.add_action(action, deadzone)
	for event in events:
		InputMap.action_add_event(action, event)

func _key(code: int) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = code
	return event

func _joy_button(button: int) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.button_index = button
	return event

func _joy_axis(axis: int, value: float) -> InputEventJoypadMotion:
	var event := InputEventJoypadMotion.new()
	event.axis = axis
	event.axis_value = value
	return event

func request_combat_impact(kind: StringName, world_position: Vector2) -> void:
	var hit_stop := 0.045
	var shake := 2.0
	var burst_power := 1.0

	match kind:
		&"combo_jab", &"attack_1":
			hit_stop = 0.040
			shake = 1.5
			burst_power = 0.85
		&"combo_hook":
			hit_stop = 0.060
			shake = 2.5
			burst_power = 1.10
		&"combo_uppercut":
			hit_stop = 0.082
			shake = 3.6
			burst_power = 1.35
		&"attack_2":
			hit_stop = 0.072
			shake = 3.0
			burst_power = 1.25
		&"slam":
			hit_stop = 0.100
			shake = 5.4
			burst_power = 1.65
		&"enemy_hit":
			hit_stop = 0.055
			shake = 2.8
			burst_power = 1.05

	_start_hit_stop(hit_stop)
	_start_camera_shake(shake, 0.13)
	_spawn_impact_burst(world_position, burst_power)
	_play_impact_sfx(kind)


func _play_impact_sfx(kind: StringName) -> void:
	var stream: AudioStream = SFX_LIGHT
	var volume_db := -7.0

	match kind:
		&"combo_hook", &"combo_uppercut", &"attack_2":
			stream = SFX_HEAVY
			volume_db = -6.0
		&"slam":
			stream = SFX_SLAM
			volume_db = -5.0
		&"enemy_hit":
			stream = SFX_ENEMY
			volume_db = -7.0

	var player_sfx := AudioStreamPlayer.new()
	player_sfx.stream = stream
	player_sfx.volume_db = volume_db
	add_child(player_sfx)
	player_sfx.finished.connect(player_sfx.queue_free)
	player_sfx.play()


func _start_hit_stop(duration: float) -> void:
	hit_stop_serial += 1
	var serial := hit_stop_serial

	# Near-freeze rather than absolute zero keeps the engine responsive while
	# still producing the classic brawler "contact pause".
	Engine.time_scale = 0.06

	await get_tree().create_timer(duration, true, false, true).timeout

	if serial == hit_stop_serial:
		Engine.time_scale = 1.0


func _start_camera_shake(strength: float, duration: float) -> void:
	shake_strength = max(shake_strength, strength)
	shake_end_msec = max(
		shake_end_msec,
		Time.get_ticks_msec() + int(duration * 1000.0)
	)


func _update_camera_shake() -> void:
	if not is_instance_valid(camera):
		return

	if Time.get_ticks_msec() < shake_end_msec:
		camera.offset = Vector2(
			randf_range(-shake_strength, shake_strength),
			randf_range(-shake_strength, shake_strength)
		)
	else:
		shake_strength = 0.0
		camera.offset = camera.offset.lerp(Vector2.ZERO, 0.40)
		if camera.offset.length() < 0.05:
			camera.offset = Vector2.ZERO


func _spawn_impact_burst(world_position: Vector2, power: float) -> void:
	var burst = IMPACT_BURST_SCRIPT.new()
	burst.global_position = world_position
	burst.z_index = 60
	add_child(burst)
	burst.setup(power)


func _on_player_attack_landed(_kind: StringName, _damage: int) -> void:
	var now := Time.get_ticks_msec()

	if now - last_combo_hit_msec > 900:
		combo_hit_count = 0

	combo_hit_count += 1
	last_combo_hit_msec = now
	combo_hide_msec = now + 1050

	if combo_hit_count >= 2:
		combo_label.text = "%d HIT" % combo_hit_count
		combo_label.visible = true
		combo_label.scale = Vector2(1.18, 1.18)
		var tween := create_tween()
		tween.set_trans(Tween.TRANS_BACK)
		tween.set_ease(Tween.EASE_OUT)
		tween.tween_property(combo_label, "scale", Vector2.ONE, 0.12)


func _update_combo_counter() -> void:
	if combo_label.visible and Time.get_ticks_msec() >= combo_hide_msec:
		combo_label.visible = false
		combo_hit_count = 0


func _exit_tree() -> void:
	# Never leave global time scale altered when stopping/reloading the scene.
	Engine.time_scale = 1.0


func _spawn_initial_enemies() -> void:
	var left_index := 0
	var right_index := 0

	for i in range(initial_enemy_count):
		var spawn_left := i % 2 == 1
		var x := 0.0

		if spawn_left:
			if left_index < INITIAL_LEFT_SLOTS.size():
				x = INITIAL_LEFT_SLOTS[left_index]
			else:
				x = randf_range(55.0, 235.0)
			left_index += 1
		else:
			if right_index < INITIAL_RIGHT_SLOTS.size():
				x = INITIAL_RIGHT_SLOTS[right_index]
			else:
				x = randf_range(560.0, 1080.0)
			right_index += 1

		_spawn_enemy_at(Vector2(x, ENEMY_FLOOR_Y), false)


func _update_enemy_spawning(delta: float) -> void:
	if not enable_reinforcements:
		return

	reinforcement_timer -= delta
	if reinforcement_timer > 0.0:
		return

	if _living_enemies().size() < max_active_enemies:
		_spawn_reinforcement_wave()

	_reset_reinforcement_timer()


func _reset_reinforcement_timer() -> void:
	var min_delay = min(reinforcement_min_delay, reinforcement_max_delay)
	var max_delay = max(reinforcement_min_delay, reinforcement_max_delay)
	reinforcement_timer = randf_range(min_delay, max_delay)


func _spawn_reinforcement_wave() -> void:
	var available := max_active_enemies - _living_enemies().size()
	if available <= 0:
		return

	var amount = min(enemies_per_reinforcement, available)
	var left_offset := 0
	var right_offset := 0

	for i in range(amount):
		var spawn_left := (reinforcement_wave_index + i) % 2 == 0
		var x := OFFSCREEN_LEFT_X

		if spawn_left:
			x -= float(left_offset) * 38.0
			left_offset += 1
		else:
			x = OFFSCREEN_RIGHT_X + float(right_offset) * 38.0
			right_offset += 1

		_spawn_enemy_at(Vector2(x, ENEMY_FLOOR_Y), true)

	reinforcement_wave_index += 1


func _spawn_enemy_at(spawn_position: Vector2, from_offscreen: bool) -> Node:
	var enemy_node: Node = ENEMY_SCENE.instantiate()
	enemy_node.set("auto_respawn", false)

	add_child(enemy_node)
	enemy_node.set("global_position", spawn_position)
	enemy_node.call("set_target", player)

	if from_offscreen and enemy_node.has_method("begin_offscreen_entry"):
		enemy_node.call("begin_offscreen_entry")

	enemy_node.set("cooldown_timer", randf_range(0.20, 0.85))

	if enemy_node.has_signal("health_changed"):
		enemy_node.connect(
			"health_changed",
			_on_enemy_health_changed.bind(enemy_node)
		)

	enemies.append(enemy_node)

	if tracked_enemy == null or not is_instance_valid(tracked_enemy):
		tracked_enemy = enemy_node

	return enemy_node


func _living_enemies() -> Array[Node]:
	var living: Array[Node] = []

	for enemy_node in enemies:
		if not is_instance_valid(enemy_node):
			continue
		if bool(enemy_node.get("defeated")):
			continue
		if not bool(enemy_node.get("visible")):
			continue
		living.append(enemy_node)

	return living


func _cleanup_enemy_list() -> void:
	var cleaned: Array[Node] = []

	for enemy_node in enemies:
		if is_instance_valid(enemy_node):
			cleaned.append(enemy_node)

	enemies = cleaned


func _nearest_living_enemy() -> Node:
	var nearest: Node
	var nearest_distance := INF

	if not is_instance_valid(player):
		return nearest

	for enemy_node in _living_enemies():
		var enemy_position: Vector2 = enemy_node.get("global_position")
		var distance = abs(enemy_position.x - player.global_position.x)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = enemy_node

	return nearest


func _update_enemy_hud() -> void:
	_cleanup_enemy_list()
	var living := _living_enemies()

	if (
		not is_instance_valid(tracked_enemy)
		or bool(tracked_enemy.get("defeated"))
		or not bool(tracked_enemy.get("visible"))
	):
		tracked_enemy = _nearest_living_enemy()

	if is_instance_valid(tracked_enemy):
		enemy_label.text = "ENEMIES  %d / %d   •   TARGET  %d / %d" % [
			living.size(),
			max_active_enemies,
			int(tracked_enemy.get("health")),
			int(tracked_enemy.get("max_health"))
		]
	else:
		enemy_label.text = "ENEMIES  %d / %d   •   CLEAR" % [
			living.size(),
			max_active_enemies
		]


func _on_enemy_health_changed(current: int, _maximum: int, source_enemy: Node) -> void:
	if is_instance_valid(source_enemy) and current > 0:
		tracked_enemy = source_enemy
	elif tracked_enemy == source_enemy:
		tracked_enemy = _nearest_living_enemy()

	_update_enemy_hud()


func request_enemy_attack(enemy_node: Node) -> bool:
	_cleanup_attack_slots()

	var enemy_id := enemy_node.get_instance_id()
	if active_attackers.has(enemy_id):
		return true

	if active_attackers.size() >= max_simultaneous_attackers:
		return false

	active_attackers[enemy_id] = weakref(enemy_node)
	return true


func release_enemy_attack(enemy_node: Node) -> void:
	if not is_instance_valid(enemy_node):
		return

	active_attackers.erase(enemy_node.get_instance_id())


func _cleanup_attack_slots() -> void:
	var stale_ids: Array = []

	for enemy_id in active_attackers:
		var enemy_ref: WeakRef = active_attackers[enemy_id]
		var enemy_node = enemy_ref.get_ref()

		if (
			not is_instance_valid(enemy_node)
			or bool(enemy_node.get("defeated"))
			or enemy_node.get("state_name") != &"ATTACK"
		):
			stale_ids.append(enemy_id)

	for enemy_id in stale_ids:
		active_attackers.erase(enemy_id)
