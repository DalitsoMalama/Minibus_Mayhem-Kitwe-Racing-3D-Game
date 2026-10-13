class_name RouteManager
extends Node3D
## Owns the route centreline (a closed Curve3D) and its bus stops. Anything that
## asks "where am I on the route?" (AI, call boy, HUD, respawn) asks this node.
## Phase 1 swaps the hand-typed points for a RoadGraph built from OSM data.

const LEFT_LANE := 3.0  ## Zambia drives on the left: lane centre is 3 m left of the line.

var route: RouteDef
var passenger_rate_mult := 1.0
var curve := Curve3D.new()
var length := 0.0
var stops: Array[BusStop] = []
var checkpoints: Array[PoliceCheckpoint] = []
var fuel_stations: Array[FuelStation] = []

var _baked := PackedVector3Array()
var _baked_offsets := PackedFloat32Array()  ## exact distance along the route of each baked point


func _ready() -> void:
	curve.bake_interval = 1.0
	for p in route.path_points:
		curve.add_point(p)
	curve.add_point(route.path_points[0])
	length = curve.get_baked_length()
	# Baked points aren't evenly spaced, so record each one's true offset.
	_baked = curve.get_baked_points()
	_baked_offsets.resize(_baked.size())
	var run := 0.0
	for i in _baked.size():
		if i > 0:
			run += _baked[i].distance_to(_baked[i - 1])
		_baked_offsets[i] = run

	for i in route.stop_names.size():
		var stop := BusStop.new()
		stop.name = "Stop_%s" % route.stop_names[i].validate_node_name()
		stop.setup(i, route.stop_names[i], route.stop_offsets[i], route.stop_names.size(), route.fare_kwacha)
		stop.transform = lane_transform(route.stop_offsets[i], LEFT_LANE)
		stop.rate_mult = passenger_rate_mult
		add_child(stop)
		stops.append(stop)

	for offset in route.checkpoint_offsets:
		var cp := PoliceCheckpoint.new()
		cp.route = self
		cp.route_offset = offset
		cp.speed_limit_kmh = route.speed_limit_kmh
		cp.transform = lane_transform(offset, LEFT_LANE)
		add_child(cp)
		checkpoints.append(cp)

	for offset in route.fuel_offsets:
		var station := FuelStation.new()
		station.route = self
		station.route_offset = offset
		station.transform = lane_transform(offset, LEFT_LANE)
		add_child(station)
		fuel_stations.append(station)


## Buses that facilities should watch. Set by RaceSession after spawning.
func set_buses(buses: Array[Minibus]) -> void:
	for cp in checkpoints:
		cp.buses = buses
	for station in fuel_stations:
		station.buses = buses


func wrap_offset(offset: float) -> float:
	return fposmod(offset, length)


func point_at(offset: float) -> Vector3:
	return curve.sample_baked(wrap_offset(offset))


func direction_at(offset: float) -> Vector3:
	return (point_at(offset + 1.0) - point_at(offset - 1.0)).normalized()


static func left_of(direction: Vector3) -> Vector3:
	return Vector3.UP.cross(direction).normalized()


func lane_point(offset: float, lane: float) -> Vector3:
	return point_at(offset) + left_of(direction_at(offset)) * lane


## Transform on the route facing the driving direction (+Z forward, like the buses).
func lane_transform(offset: float, lane: float, lift := 0.0) -> Transform3D:
	var dir := direction_at(offset)
	var pos := point_at(offset) + left_of(dir) * lane + Vector3.UP * lift
	return Transform3D(Basis.looking_at(-dir, Vector3.UP), pos)


## Offset of the nearest route point. Pass the previous offset as `hint` to only
## search just behind/ahead of it: real routes can pass the same junction twice,
## and a global search would then jump to the wrong part of the loop.
func closest_offset(world_pos: Vector3, hint := -1.0) -> float:
	var p := to_local(world_pos)
	if hint >= 0.0 and _baked.size() > 1:
		var n := _baked.size()
		var h := wrap_offset(hint)
		var i := clampi(_baked_offsets.bsearch(h), 0, n - 1)
		for _k in n:  # step back up to 25 m behind the hint
			var prev := posmod(i - 1, n)
			if ahead_distance(_baked_offsets[prev], h) > 25.0:
				break
			i = prev
		var best_i := i
		var best_d := INF
		for _k in n:  # then scan up to 80 m ahead of it
			var d := _baked[i].distance_squared_to(p)
			if d < best_d:
				best_d = d
				best_i = i
			i = (i + 1) % n
			var ahead := ahead_distance(h, _baked_offsets[i])
			if ahead > 80.0 and ahead < length - 25.0:
				break
		if best_d < 30.0 * 30.0:
			return _refine(best_i, p)
	return curve.get_closest_offset(p)


## Project p onto the baked segments either side of point i for a smooth offset.
func _refine(i: int, p: Vector3) -> float:
	var best := _baked_offsets[i]
	var best_d := _baked[i].distance_squared_to(p)
	for j in [i - 1, i]:
		if j < 0 or j + 1 >= _baked.size():
			continue
		var a := _baked[j]
		var b := _baked[j + 1]
		var ab := b - a
		var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
		var d := (a + ab * t).distance_squared_to(p)
		if d < best_d:
			best_d = d
			best = _baked_offsets[j] + ab.length() * t
	return wrap_offset(best)


## How far ahead `to` is from `from`, going forward around the loop.
func ahead_distance(from: float, to: float) -> float:
	return fposmod(to - from, length)


## Signed distance to a point on the route: small negatives mean "just rolled past it".
func signed_distance(from: float, offset: float, tolerance := 8.0) -> float:
	var ahead := ahead_distance(from, offset)
	return ahead - length if ahead > length - tolerance else ahead


func stop_distance(from: float, stop: BusStop, tolerance := 8.0) -> float:
	return signed_distance(from, stop.route_offset, tolerance)


func next_checkpoint(from: float) -> PoliceCheckpoint:
	var best: PoliceCheckpoint = null
	var best_dist := INF
	for cp in checkpoints:
		var dist := signed_distance(from, cp.route_offset, PoliceCheckpoint.ZONE_AFTER)
		if dist < best_dist:
			best_dist = dist
			best = cp
	return best


func next_fuel_station(from: float) -> FuelStation:
	var best: FuelStation = null
	var best_dist := INF
	for station in fuel_stations:
		var dist := signed_distance(from, station.route_offset)
		if dist < best_dist:
			best_dist = dist
			best = station
	return best


func next_stop(from: float, exclude: BusStop = null) -> BusStop:
	var best: BusStop = null
	var best_dist := INF
	for stop in stops:
		if stop == exclude:
			continue
		var dist := stop_distance(from, stop)
		if dist < best_dist:
			best_dist = dist
			best = stop
	return best
