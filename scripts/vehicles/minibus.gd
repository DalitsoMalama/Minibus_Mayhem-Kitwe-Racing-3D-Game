class_name Minibus
extends VehicleBody3D
## A Toyota HiAce-style minibus. It doesn't know who drives it: a PlayerDriver or
## AIDriver child writes throttle / steer_input / handbrake every physics tick.
## Forward is +Z (VehicleBody3D convention); positive steering turns left.

signal passengers_changed(count: int, seats: int)
signal out_of_fuel

## How many extra riders the call boy can squeeze in (illegal: police fine it).
const SQUEEZE_EXTRA := 4

var def: VehicleDef
var driver_name := "Driver"
var is_player := false
var controls_enabled := true

## Ledger for this race. earnings = fares - fines - fuel.
var fares := 0
var fines := 0
var fuel_spent := 0
var earnings: int:
	get:
		return fares - fines - fuel_spent

## When true the call boy squeezes riders in beyond the legal seat count.
var squeeze := false
## Litres in the tank. Rivals' owners keep them topped up (uses_fuel = false).
var fuel_l := 0.0
var uses_fuel := false
## Metres along the route, updated every physics tick by RaceSession.
var route_progress := -1.0

var throttle := 0.0  ## -1 (brake/reverse) .. 1 (full gas)
var steer_input := 0.0  ## -1 (right) .. 1 (left)
var handbrake := false

## Destination stop index for each passenger on board.
var passengers: Array[int] = []


func _ready() -> void:
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0, 0.3, 0)  # low CoM so the top-heavy bus doesn't roll
	_build_body()
	for x in [-0.85, 0.85]:
		_add_wheel(Vector3(x, 0.5, 1.55), true, false)
		_add_wheel(Vector3(x, 0.5, -1.55), false, true)
	_update_mass()


func _physics_process(delta: float) -> void:
	if not controls_enabled:
		throttle = 0.0
		steer_input = 0.0
		handbrake = true

	var speed := forward_speed()
	var top := def.top_speed_kmh / 3.6
	_burn_fuel(speed, delta)
	engine_force = 0.0
	brake = 0.0
	if throttle > 0.0 and has_fuel():
		engine_force = throttle * def.max_engine_force * (1.0 - clampf(speed / top, 0.0, 1.0))
	elif throttle < 0.0:
		if speed > 1.0:
			brake = -throttle * def.max_brake
		elif has_fuel():
			engine_force = throttle * def.reverse_force
	else:
		brake = 2.0  # rolling resistance
	if handbrake:
		engine_force = 0.0
		brake = def.max_brake

	var steer_limit := deg_to_rad(def.max_steer_deg) * lerpf(1.0, 0.35, clampf(absf(speed) / 30.0, 0.0, 1.0))
	steering = move_toward(steering, steer_input * steer_limit, 2.0 * delta)


func forward_speed() -> float:
	return linear_velocity.dot(global_basis.z)


## Legal seats, plus the squeezed-in extras when the call boy is packing them in.
func capacity() -> int:
	return def.seats + (SQUEEZE_EXTRA if squeeze else 0)


func free_seats() -> int:
	return capacity() - passengers.size()


func is_overloaded() -> bool:
	return passengers.size() > def.seats


## Police make the extra riders get off.
func offload_extra() -> int:
	var removed := 0
	while passengers.size() > def.seats:
		passengers.pop_back()
		removed += 1
	_update_mass()
	return removed


func fine(amount: int, reason: String) -> void:
	fines += amount
	EventBus.fined.emit(self, amount, reason)


func has_fuel() -> bool:
	return not uses_fuel or fuel_l > 0.0


## Adds fuel, paying `price_per_l`. Returns litres actually added.
func refuel(litres: float, price_per_l: float) -> float:
	var added := minf(litres, def.fuel_capacity_l - fuel_l)
	if added <= 0.0:
		return 0.0
	fuel_l += added
	fuel_spent += int(ceil(added * price_per_l))
	return added


func _burn_fuel(speed: float, delta: float) -> void:
	if not uses_fuel or fuel_l <= 0.0 or not controls_enabled:
		return
	var load_factor := 1.0 + 0.3 * float(passengers.size()) / float(def.seats)
	var km := absf(speed) * delta / 1000.0
	var burn := def.fuel_l_per_km * km * (0.6 + 0.6 * maxf(throttle, 0.0)) * load_factor
	burn += def.fuel_idle_l_per_min * delta / 60.0
	fuel_l = maxf(fuel_l - burn, 0.0)
	if fuel_l <= 0.0:
		out_of_fuel.emit()


func has_passenger_for(stop_index: int) -> bool:
	return passengers.has(stop_index)


func add_passenger(destination: int) -> void:
	passengers.append(destination)
	_update_mass()


func drop_passenger_for(stop_index: int) -> bool:
	var i := passengers.find(stop_index)
	if i < 0:
		return false
	passengers.remove_at(i)
	_update_mass()
	return true


func reset_to(xform: Transform3D) -> void:
	global_transform = xform
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	steering = 0.0


func _update_mass() -> void:
	mass = def.empty_mass_kg + passengers.size() * def.passenger_mass_kg
	passengers_changed.emit(passengers.size(), def.seats)


func _build_body() -> void:
	var box := BoxShape3D.new()
	box.size = Vector3(1.9, 1.7, 4.8)
	var col := CollisionShape3D.new()
	col.shape = box
	col.position = Vector3(0, 1.25, 0)
	add_child(col)

	# Toyota HiAce-style body: front is +Z, kerb (passenger door) side is +X
	# because Zambia drives on the left.
	var glass := Color(0.08, 0.1, 0.12)
	var trim := Color(0.06, 0.06, 0.06)
	var stripe := def.body_color.darkened(0.45) if def.body_color.get_luminance() > 0.5 else Color(0.95, 0.95, 0.92)
	Graybox.box(self, Vector3(1.9, 1.05, 4.8), Vector3(0, 0.92, 0), def.body_color)  # lower body
	Graybox.box(self, Vector3(1.86, 0.92, 4.25), Vector3(0, 1.9, -0.27), def.body_color)  # cabin
	var screen := Graybox.box(self, Vector3(1.74, 1.0, 0.08), Vector3(0, 1.88, 2.05), glass)
	screen.rotation_degrees = Vector3(-22, 0, 0)  # raked windscreen
	Graybox.box(self, Vector3(1.86, 0.25, 0.45), Vector3(0, 2.24, 2.0), def.body_color)  # roof edge over screen
	for side in [-1.0, 1.0]:
		Graybox.box(self, Vector3(0.02, 0.55, 3.7), Vector3(0.94 * side, 1.95, -0.45), glass)  # side windows
		Graybox.box(self, Vector3(0.02, 0.12, 4.78), Vector3(0.955 * side, 1.12, 0), stripe)  # body stripe
		Graybox.box(self, Vector3(0.3, 0.12, 0.08), Vector3(0.97 * side, 1.75, 1.75), trim)  # mirror arm
	Graybox.box(self, Vector3(0.03, 1.45, 0.04), Vector3(0.96, 1.25, 0.85), trim)  # sliding door seams
	Graybox.box(self, Vector3(0.03, 1.45, 0.04), Vector3(0.96, 1.25, -0.45), trim)
	Graybox.box(self, Vector3(1.95, 0.25, 0.18), Vector3(0, 0.5, 2.43), trim)  # front bumper
	Graybox.box(self, Vector3(1.95, 0.25, 0.18), Vector3(0, 0.5, -2.43), trim)  # rear bumper
	Graybox.box(self, Vector3(1.0, 0.22, 0.05), Vector3(0, 0.9, 2.41), trim)  # grille
	for x in [-0.72, 0.72]:
		Graybox.box(self, Vector3(0.3, 0.18, 0.05), Vector3(x, 0.92, 2.42), Color(1.0, 0.95, 0.7))  # headlights
		Graybox.box(self, Vector3(0.18, 0.35, 0.05), Vector3(x * 1.15, 1.0, -2.42), Color(0.75, 0.05, 0.05))  # tail lights
	Graybox.box(self, Vector3(1.6, 0.12, 3.2), Vector3(0, 2.42, -0.4), trim)  # roof rack
	Graybox.box(self, Vector3(1.0, 0.5, 0.9), Vector3(0.2, 2.73, -1.3), Color(0.6, 0.2, 0.15))  # luggage
	Graybox.box(self, Vector3(0.6, 0.35, 0.6), Vector3(-0.35, 2.66, 0.2), Color(0.85, 0.75, 0.3))  # maize sack

	var plate := Label3D.new()
	plate.text = "KTW %04d" % (absi(driver_name.hash()) % 10000)
	plate.font_size = 40
	plate.pixel_size = 0.004
	plate.modulate = Color.BLACK
	plate.outline_size = 0
	plate.position = Vector3(0, 0.5, -2.53)
	plate.rotation_degrees = Vector3(0, 180, 0)
	Graybox.box(self, Vector3(0.5, 0.15, 0.02), Vector3(0, 0.5, -2.525), Color(0.95, 0.95, 0.9))
	add_child(plate)

	if not is_player:
		var tag := Label3D.new()
		tag.text = driver_name
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.position = Vector3(0, 3.6, 0)
		tag.font_size = 64
		tag.outline_size = 12
		tag.pixel_size = 0.01
		add_child(tag)


func _add_wheel(pos: Vector3, steer: bool, drive: bool) -> void:
	var wheel := VehicleWheel3D.new()
	wheel.position = pos
	wheel.use_as_steering = steer
	wheel.use_as_traction = drive
	wheel.wheel_radius = 0.36
	wheel.wheel_rest_length = 0.3
	wheel.suspension_travel = 0.3
	wheel.suspension_stiffness = def.suspension_stiffness
	wheel.suspension_max_force = def.suspension_max_force
	wheel.damping_compression = def.damping_compression
	wheel.damping_relaxation = def.damping_relaxation
	wheel.wheel_friction_slip = def.wheel_grip
	wheel.wheel_roll_influence = 0.1
	add_child(wheel)

	var tyre := CylinderMesh.new()
	tyre.top_radius = 0.36
	tyre.bottom_radius = 0.36
	tyre.height = 0.28
	tyre.material = Graybox.mat(Color(0.08, 0.08, 0.08))
	var mesh := MeshInstance3D.new()
	mesh.mesh = tyre
	mesh.rotation_degrees = Vector3(0, 0, 90)
	wheel.add_child(mesh)
