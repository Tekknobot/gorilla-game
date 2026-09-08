extends Node2D

@onready var player = $Player
@onready var state_label: Label = $HUD/StateLabel
@onready var enemy_spawn: Marker2D = $EnemySpawn
@onready var camera: Camera2D = $Camera2D
@onready var combo_label: Label = $HUD/ComboLabel

const ENEMY_SCENE := preload("res://Scenes/enemy.tscn")
const IMPACT_BURST_SCRIPT := preload("res://Scripts/impact_burst.gd")
const SFX_LIGHT := preload("res://Audio/impact_light.wav")
const SFX_HEAVY := preload("res://Audio/impact_heavy.wav")
const SFX_SLAM := preload("res://Audio/impact_slam.wav")
const SFX_ENEMY := preload("res://Audio/enemy_hit.wav")

var enemy
var hit_stop_serial := 0
var shake_strength := 0.0
var shake_end_msec := 0
var combo_hit_count := 0
var last_combo_hit_msec := 0
var combo_hide_msec := 0

func _ready() -> void:
	_configure_input()
	_spawn_enemy()

	if is_instance_valid(player) and player.has_signal("attack_landed"):
		player.attack_landed.connect(_on_player_attack_landed)

func _process(_delta: float) -> void:
	if is_instance_valid(player):
		var pad_name := "Keyboard"
		var pads := Input.get_connected_joypads()
		if not pads.is_empty():
			pad_name = Input.get_joy_name(pads[0])
		state_label.text = "STATE  %s\nSPEED  %3d\nPAD    %s" % [player.state_name, int(abs(player.velocity.x)), pad_name]

	_update_camera_shake()
	_update_combo_counter()


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


func _spawn_enemy() -> void:
	enemy = ENEMY_SCENE.instantiate()
	enemy.global_position = enemy_spawn.global_position
	add_child(enemy)
	enemy.set_target(player)
	if enemy.has_signal("health_changed"):
		enemy.health_changed.connect(_on_enemy_health_changed)
	if enemy.has_signal("respawned"):
		enemy.respawned.connect(_on_enemy_respawned)
	_on_enemy_health_changed(enemy.health, enemy.max_health)

func _on_enemy_health_changed(current: int, maximum: int) -> void:
	$HUD/DummyLabel.text = "HUMAN ENEMY  %d / %d" % [current, maximum]

func _on_enemy_respawned(maximum: int) -> void:
	$HUD/DummyLabel.text = "HUMAN ENEMY  %d / %d" % [maximum, maximum]
