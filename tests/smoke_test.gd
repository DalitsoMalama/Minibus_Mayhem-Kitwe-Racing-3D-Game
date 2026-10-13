extends SceneTree
## Headless smoke test: runs the race, holds the player's throttle, and prints
## what every bus did. Fails (exit 1) if no rival earns anything.
##   godot --headless --path . --script res://tests/smoke_test.gd -- [--route=res://data/routes/x.tres] [--seconds=90] [--rain]

var _frames := 60 * 90
var REPORT_EVERY := 900
var _frame := 0
var _session: Node


func _initialize() -> void:
	root.get_node("GameState").persist = false
	var session: Node = load("res://scenes/race/race_session.tscn").instantiate()
	session.weather = load("res://data/weather/dry.tres")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--route="):
			session.route = load(arg.trim_prefix("--route="))
		elif arg.begins_with("--seconds="):
			_frames = 60 * int(arg.trim_prefix("--seconds="))
		elif arg.begins_with("--every="):
			REPORT_EVERY = 60 * int(arg.trim_prefix("--every="))
		elif arg == "--rain":
			session.weather = load("res://data/weather/rainy.tres")
	var events := root.get_node("EventBus")
	events.fined.connect(func(bus: Node, amount: int, reason: String) -> void:
		print("    FINE %s K%d: %s" % [bus.driver_name, amount, reason]))
	events.refuelled.connect(func(bus: Node, litres: float, cost: int) -> void:
		print("    REFUEL %s %.1f L K%d" % [bus.driver_name, litres, cost]))
	root.add_child(session)
	current_scene = session
	_session = session


func _physics_process(_delta: float) -> bool:
	if _frame == 0:
		var rm = _session.route_manager
		print("Route: %s, %.0f m, %d stops, %d checkpoints, %d fuel, weather %s, traffic %d" % [
			_session.route.route_name, rm.length, rm.stops.size(), rm.checkpoints.size(),
			rm.fuel_stations.size(), _session.weather.display_name, _session.traffic.vehicles.size()])
	Input.action_press(&"accelerate")
	_frame += 1
	if _frame % REPORT_EVERY == 0:
		_report()
	if _frame >= _frames:
		return _finish()
	return false


func _report() -> void:
	for bus in _session.buses:
		print("t=%3ds %-10s at %6.0fm  %5.1f km/h  y=%5.2f  riders=%2d  fuel=%4.1f  K%d (fares %d fines %d fuel %d)" % [
			_frame / 60, bus.driver_name, bus.route_progress, absf(bus.forward_speed()) * 3.6,
			bus.global_position.y, bus.passengers.size(), bus.fuel_l, bus.earnings, bus.fares, bus.fines, bus.fuel_spent,
		])


func _finish() -> bool:
	var ok := false
	for rival in _session.rival_buses:
		ok = ok or rival.fares > 0
	print("SMOKE TEST %s" % ("PASSED" if ok else "FAILED"))
	Input.action_release(&"accelerate")
	quit(0 if ok else 1)
	return true
