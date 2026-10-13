extends Node
## Registers input actions in code so project.godot stays readable.
## Keyboard + gamepad for now; on-screen touch controls arrive in Phase 1 (Android).


func _ready() -> void:
	_add_keys(&"accelerate", [KEY_W, KEY_UP])
	_add_joy_axis(&"accelerate", JOY_AXIS_TRIGGER_RIGHT, 1.0)
	_add_keys(&"brake_reverse", [KEY_S, KEY_DOWN])
	_add_joy_axis(&"brake_reverse", JOY_AXIS_TRIGGER_LEFT, 1.0)
	_add_keys(&"steer_left", [KEY_A, KEY_LEFT])
	_add_joy_axis(&"steer_left", JOY_AXIS_LEFT_X, -1.0)
	_add_keys(&"steer_right", [KEY_D, KEY_RIGHT])
	_add_joy_axis(&"steer_right", JOY_AXIS_LEFT_X, 1.0)
	_add_keys(&"handbrake", [KEY_SPACE])
	_add_joy_button(&"handbrake", JOY_BUTTON_A)
	_add_keys(&"reset_bus", [KEY_R])
	_add_joy_button(&"reset_bus", JOY_BUTTON_Y)
	_add_keys(&"restart", [KEY_ENTER])
	_add_joy_button(&"restart", JOY_BUTTON_START)
	_add_keys(&"squeeze", [KEY_Q])
	_add_joy_button(&"squeeze", JOY_BUTTON_X)
	_add_keys(&"menu", [KEY_ESCAPE])
	_add_joy_button(&"menu", JOY_BUTTON_BACK)


func _ensure(action: StringName) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.2)


func _add_keys(action: StringName, keys: Array) -> void:
	_ensure(action)
	for key in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = key
		InputMap.action_add_event(action, ev)


func _add_joy_axis(action: StringName, axis: JoyAxis, value: float) -> void:
	_ensure(action)
	var ev := InputEventJoypadMotion.new()
	ev.axis = axis
	ev.axis_value = value
	InputMap.action_add_event(action, ev)


func _add_joy_button(action: StringName, button: JoyButton) -> void:
	_ensure(action)
	var ev := InputEventJoypadButton.new()
	ev.button_index = button
	InputMap.action_add_event(action, ev)
