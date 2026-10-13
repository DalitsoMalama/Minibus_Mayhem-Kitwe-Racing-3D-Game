class_name TrafficCar
extends AnimatableBody3D
## Lightweight ambient vehicle that rides the route like a tram: no physics
## simulation, just "keep moving unless something is in front of me". Cheap
## enough for phones. Oncoming traffic uses the right-hand lane (dir = -1).

enum Kind { CAR, TRUCK, BICYCLE }

const KIND_SPEED := {Kind.CAR: 13.0, Kind.TRUCK: 9.0, Kind.BICYCLE: 4.0}
const KIND_LANE := {Kind.CAR: 3.0, Kind.TRUCK: 3.0, Kind.BICYCLE: 5.2}
const CAR_COLOURS := [
	Color(0.85, 0.85, 0.85), Color(0.15, 0.15, 0.17), Color(0.7, 0.1, 0.1),
	Color(0.2, 0.3, 0.6), Color(0.55, 0.55, 0.58), Color(0.9, 0.9, 0.85),
]

var kind := Kind.CAR
var route: RouteManager
var offset := 0.0
var dir := 1  ## +1 = with the route, -1 = oncoming
var cruise := 13.0
var speed := 0.0
var velocity := Vector3.ZERO
## Everything this car must not drive into (buses + other traffic). Shared array.
var obstacles: Array[Node3D] = []


func setup(car_kind: Kind, route_manager: RouteManager, start_offset: float, direction: int) -> void:
	kind = car_kind
	route = route_manager
	offset = start_offset
	dir = direction
	cruise = KIND_SPEED[kind] * randf_range(0.85, 1.15)
	speed = cruise
	sync_to_physics = true
	_build()
	_place()


func place_at(start_offset: float, direction: int) -> void:
	offset = start_offset
	dir = direction
	speed = cruise
	_place()
	reset_physics_interpolation()


func lane() -> float:
	return KIND_LANE[kind] * dir


func _physics_process(delta: float) -> void:
	if route == null:
		return
	var bend := route.direction_at(offset).angle_to(route.direction_at(offset + 20.0 * dir))
	var target := cruise * lerpf(1.0, 0.45, clampf(bend / (PI * 0.5), 0.0, 1.0))
	var gap := _gap_ahead()
	if gap < 28.0:
		target = minf(target, maxf((gap - 7.0) * 0.7, 0.0))
	speed = move_toward(speed, target, (3.0 if target > speed else 9.0) * delta)
	var before := global_position
	offset = route.wrap_offset(offset + speed * dir * delta)
	_place()
	velocity = (global_position - before) / delta


func _place() -> void:
	var xf := route.lane_transform(offset, lane(), 0.0)
	if dir < 0:
		xf.basis = xf.basis.rotated(Vector3.UP, PI)
	global_transform = xf


func _gap_ahead() -> float:
	var fwd := global_basis.z
	var gap := INF
	for other in obstacles:
		if other == self:
			continue
		var rel := other.global_position - global_position
		var along := rel.dot(fwd)
		if along <= 0.0 or along > 30.0:
			continue
		if (rel - fwd * along).length() < 2.2:
			gap = minf(gap, along)
	return gap


func _build() -> void:
	var size: Vector3
	match kind:
		Kind.CAR:
			size = Vector3(1.8, 1.4, 4.2)
			var paint: Color = CAR_COLOURS[randi() % CAR_COLOURS.size()]
			Graybox.box(self, Vector3(1.8, 0.75, 4.2), Vector3(0, 0.6, 0), paint)
			Graybox.box(self, Vector3(1.6, 0.6, 2.2), Vector3(0, 1.25, -0.2), paint.darkened(0.6))
		Kind.TRUCK:
			# A Copperbelt copper truck: cab plus a flatbed stacked with cathode plates.
			size = Vector3(2.5, 3.0, 10.0)
			Graybox.box(self, Vector3(2.5, 2.8, 2.4), Vector3(0, 1.6, 3.6), Color(0.9, 0.85, 0.75))
			Graybox.box(self, Vector3(2.5, 0.4, 7.4), Vector3(0, 0.9, -1.2), Color(0.2, 0.2, 0.2))
			Graybox.box(self, Vector3(1.8, 1.0, 6.0), Vector3(0, 1.6, -1.2), Color(0.72, 0.42, 0.25))
		Kind.BICYCLE:
			# Bicycle loaded with charcoal sacks, a common sight on the edge of town.
			size = Vector3(0.8, 1.7, 1.9)
			Graybox.box(self, Vector3(0.08, 0.7, 1.7), Vector3(0, 0.5, 0), Color(0.1, 0.1, 0.1))
			Graybox.box(self, Vector3(0.7, 0.7, 0.7), Vector3(0, 1.0, -0.6), Color(0.92, 0.9, 0.85))
			var rider := CapsuleMesh.new()
			rider.radius = 0.22
			rider.height = 1.2
			rider.material = Graybox.mat(Color(0.2, 0.4, 0.7))
			var mi := MeshInstance3D.new()
			mi.mesh = rider
			mi.position = Vector3(0, 1.3, 0.3)
			add_child(mi)
	var shape := BoxShape3D.new()
	shape.size = size
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position = Vector3(0, size.y * 0.5 + 0.1, 0)
	add_child(col)
