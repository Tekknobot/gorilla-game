extends Node2D

@onready var player = $Player
@onready var state_label: Label = $HUD/StateLabel
@onready var dummy = $TrainingDummy

func _ready() -> void:
	_configure_input()
	if dummy.has_signal("health_changed"):
		dummy.health_changed.connect(_on_dummy_health_changed)
	if dummy.has_signal("respawned"):
		dummy.respawned.connect(_on_dummy_respawned)

func _process(_delta: float) -> void:
	if is_instance_valid(player):
		var pad_name := "Keyboard"
		var pads := Input.get_connected_joypads()
		if not pads.is_empty():
			pad_name = Input.get_joy_name(pads[0])
		state_label.text = "STATE  %s\nSPEED  %3d\nPAD    %s" % [player.state_name, int(abs(player.velocity.x)), pad_name]

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

func _on_dummy_health_changed(current: int, maximum: int) -> void:
	$HUD/DummyLabel.text = "TRAINING TARGET  %d / %d" % [current, maximum]

func _on_dummy_respawned(maximum: int) -> void:
	$HUD/DummyLabel.text = "TRAINING TARGET  %d / %d" % [maximum, maximum]
