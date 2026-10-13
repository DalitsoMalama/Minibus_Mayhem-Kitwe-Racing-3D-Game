class_name ChaseCamera
extends Camera3D
## Smooth third-person camera behind a vehicle (vehicles face +Z).

@export var distance := 9.0
@export var height := 3.8
@export var look_ahead := 4.0
@export var smoothing := 5.0

var target: Node3D


func follow(node: Node3D) -> void:
	target = node
	global_position = _desired_position()
	make_current()


func _physics_process(delta: float) -> void:
	if target == null:
		return
	global_position = global_position.lerp(_desired_position(), 1.0 - exp(-smoothing * delta))
	look_at(target.global_position + Vector3.UP * 1.5 + target.global_basis.z * look_ahead)


func _desired_position() -> Vector3:
	var back := -target.global_basis.z
	back.y = 0.0
	return target.global_position + back.normalized() * distance + Vector3.UP * height
