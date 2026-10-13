class_name AIDriver
extends Node
## Rival minibus brain: keeps to the left lane, slows for bends, races the
## player to stops with passengers, follows slower traffic, overtakes on the
## right when the oncoming lane is clear, and stops for police checkpoints.

@export var cruise_speed := 14.0  ## m/s (~50 km/h); overridden by RivalDef
@export var corner_speed := 6.0
@export var stop_decel := 2.0  ## m/s², used to plan braking into a stop
@export var max_dwell := 10.0
@export var steer_gain := 1.5

var route: RouteManager
## Everything on the road (buses + traffic). Shared with TrafficManager.
var traffic: Array[Node3D] = []

@onready var bus: Minibus = get_parent()

var _dwelling_at: Node3D = null  ## a BusStop or PoliceCheckpoint
var _dwell_time := 0.0
var _last_served: BusStop = null
var _stuck_time := 0.0
var _overtake_time := 0.0


func _physics_process(delta: float) -> void:
	if route == null or not bus.controls_enabled:
		return
	if _dwelling_at:
		_dwell(delta)
		return

	var speed := bus.forward_speed()
	var here := bus.route_progress

	# Forget the last stop once well past it, so it can be served again next lap.
	if _last_served:
		var past := route.ahead_distance(_last_served.route_offset, here)
		if past > 30.0 and past < route.length - 30.0:
			_last_served = null

	var bend := route.direction_at(here).angle_to(route.direction_at(here + 25.0))
	var target_speed := lerpf(cruise_speed, corner_speed, clampf(bend / (PI * 0.5), 0.0, 1.0))
	var stopping := false

	var stop := route.next_stop(here, _last_served)
	if stop and stop.wants_service(bus):
		var dist := route.stop_distance(here, stop)
		if dist < 60.0:
			stopping = true
			target_speed = minf(target_speed, _brake_speed(dist))
			if absf(dist) < 7.0 and speed < BusStop.STOP_SPEED:
				_begin_dwell(stop)

	var cp := route.next_checkpoint(here)
	if cp and not cp.is_cleared(bus):
		var dist := route.signed_distance(here, cp.route_offset, PoliceCheckpoint.ZONE_AFTER)
		if dist < PoliceCheckpoint.TRAP_DISTANCE + 20.0:
			target_speed = minf(target_speed, cp.speed_limit_kmh / 3.6 - 2.0)  # no speeding fines
		if dist < 60.0:
			stopping = true
			target_speed = minf(target_speed, _brake_speed(dist - 4.0))
			if dist < PoliceCheckpoint.ZONE_BEFORE and speed < BusStop.STOP_SPEED:
				_begin_dwell(cp)

	# Traffic: follow whatever is ahead, or pass it on the right when it's slow and the way is clear.
	var blocker := _obstacle_ahead()
	if blocker and _overtake_time <= 0.0:
		var gap := bus.to_local(blocker.global_position).z - 7.0
		var their_speed := _speed_along(blocker, bus.global_basis.z)
		var slow := their_speed < 2.0 or their_speed < cruise_speed * 0.6
		if slow and not stopping and _oncoming_clear(80.0):
			_overtake_time = 4.0
		else:
			target_speed = minf(target_speed, maxf(their_speed + gap * 0.4 - 1.0, 0.0))
	if _overtake_time > 0.0:
		_overtake_time -= delta
		if not _oncoming_clear(35.0):
			_overtake_time = 0.0  # abort: duck back in
	var lane := -RouteManager.LEFT_LANE if _overtake_time > 0.0 else RouteManager.LEFT_LANE

	var target := route.lane_point(here + 6.0 + absf(speed) * 0.7, lane)
	var local := bus.to_local(target)
	bus.steer_input = clampf(atan2(local.x, local.z) * steer_gain, -1.0, 1.0)

	_drive_towards(target_speed, speed, here, delta)


func _brake_speed(dist: float) -> float:
	return sqrt(2.0 * stop_decel * maxf(dist - 1.0, 0.0))


func _begin_dwell(place: Node3D) -> void:
	_dwelling_at = place
	_dwell_time = 0.0


## Nearest vehicle in our lane within 25 m ahead.
func _obstacle_ahead() -> Node3D:
	var nearest: Node3D = null
	var nearest_z := 25.0
	for other in traffic:
		if other == bus:
			continue
		var rel := bus.to_local(other.global_position)
		if rel.z > 0.0 and rel.z < nearest_z and absf(rel.x) < 2.6:
			nearest = other
			nearest_z = rel.z
	return nearest


## No vehicle coming towards us in the right-hand lane within `metres`.
func _oncoming_clear(metres: float) -> bool:
	var fwd := bus.global_basis.z
	for other in traffic:
		if other == bus:
			continue
		var rel := bus.to_local(other.global_position)
		if rel.z > -5.0 and rel.z < metres and rel.x < -1.0 and rel.x > -7.0 and _speed_along(other, fwd) < 1.0:
			return false
	return true


func _speed_along(node: Node3D, dir: Vector3) -> float:
	if node is RigidBody3D:
		return (node as RigidBody3D).linear_velocity.dot(dir)
	if node is TrafficCar:
		return (node as TrafficCar).velocity.dot(dir)
	return 0.0


func _drive_towards(target_speed: float, speed: float, here: float, delta: float) -> void:
	bus.handbrake = false
	if target_speed < 0.5 and speed < BusStop.STOP_SPEED:
		bus.throttle = 0.0
		bus.handbrake = true
		_stuck_time = 0.0
		return
	bus.throttle = clampf((target_speed - speed) * 0.5, -1.0, 1.0)
	if bus.throttle < 0.0 and speed < BusStop.STOP_SPEED:
		bus.throttle = 0.0  # never reverse by accident

	# Wedged against something: put the bus back on the road a little ahead.
	if bus.throttle > 0.3 and absf(speed) < 0.5:
		_stuck_time += delta
		if _stuck_time > 4.0:
			_stuck_time = 0.0
			bus.reset_to(route.lane_transform(here + 8.0, RouteManager.LEFT_LANE, 1.0))
	else:
		_stuck_time = 0.0


func _dwell(delta: float) -> void:
	bus.throttle = 0.0
	bus.steer_input = 0.0
	bus.handbrake = true
	_dwell_time += delta
	var done := false
	if _dwelling_at is BusStop:
		done = _dwell_time > 1.0 and not (_dwelling_at as BusStop).wants_service(bus)
		if done or _dwell_time > max_dwell:
			_last_served = _dwelling_at
	elif _dwelling_at is PoliceCheckpoint:
		done = (_dwelling_at as PoliceCheckpoint).is_cleared(bus)
	if done or _dwell_time > max_dwell:
		_dwelling_at = null
