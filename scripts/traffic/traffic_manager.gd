class_name TrafficManager
extends Node3D
## Keeps a small pool of ambient vehicles alive around the player: cars and
## copper trucks both ways, charcoal bicycles at the kerb. Vehicles that fall
## too far behind are recycled ahead, out of sight.

const SPAWN_MIN := 140.0
const SPAWN_MAX := 420.0
const DESPAWN := 520.0

@export var cars := 10
@export var trucks := 2
@export var bicycles := 4

var route: RouteManager
var focus: Minibus
## Buses + traffic: the shared list every driver checks before moving.
var obstacles: Array[Node3D] = []
var vehicles: Array[TrafficCar] = []

var _check_timer := 0.0


func start(route_manager: RouteManager, player: Minibus, buses: Array[Minibus]) -> void:
	route = route_manager
	focus = player
	for bus in buses:
		obstacles.append(bus)
	var kinds: Array[TrafficCar.Kind] = []
	for i in cars:
		kinds.append(TrafficCar.Kind.CAR)
	for i in trucks:
		kinds.append(TrafficCar.Kind.TRUCK)
	for i in bicycles:
		kinds.append(TrafficCar.Kind.BICYCLE)
	for kind in kinds:
		var car := TrafficCar.new()
		car.obstacles = obstacles
		add_child(car)
		var spot := _free_spot()
		car.setup(kind, route, spot.x, int(spot.y))
		vehicles.append(car)
		obstacles.append(car)


func _physics_process(delta: float) -> void:
	_check_timer -= delta
	if _check_timer > 0.0 or focus == null:
		return
	_check_timer = 0.5
	for car in vehicles:
		if car.global_position.distance_to(focus.global_position) > DESPAWN:
			var spot := _free_spot()
			car.place_at(spot.x, int(spot.y))


## Returns (offset, direction) for a spawn point near the player but not on top of anyone.
func _free_spot() -> Vector2:
	var here := maxf(focus.route_progress, 0.0)
	for attempt in 12:
		var side := 1.0 if randf() < 0.65 else -1.0
		var offset := route.wrap_offset(here + side * randf_range(SPAWN_MIN, SPAWN_MAX))
		var dir := 1 if randf() < 0.5 else -1
		var pos := route.lane_point(offset, RouteManager.LEFT_LANE * dir)
		var clear := true
		for other in obstacles:
			if other.global_position.distance_to(pos) < 25.0:
				clear = false
				break
		if clear:
			return Vector2(offset, dir)
	return Vector2(route.wrap_offset(here + SPAWN_MAX), 1)
