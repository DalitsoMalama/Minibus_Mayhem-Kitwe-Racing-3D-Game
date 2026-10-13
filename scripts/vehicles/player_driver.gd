class_name PlayerDriver
extends Node
## Feeds player input into the parent Minibus.

@onready var bus: Minibus = get_parent()


func _physics_process(_delta: float) -> void:
	bus.throttle = Input.get_axis(&"brake_reverse", &"accelerate")
	bus.steer_input = Input.get_axis(&"steer_right", &"steer_left")
	bus.handbrake = Input.is_action_pressed(&"handbrake")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"squeeze") and bus.controls_enabled:
		bus.squeeze = not bus.squeeze
		EventBus.bark.emit("Squeeze in! Four more!" if bus.squeeze else "No more squeezing, legal load only.")
