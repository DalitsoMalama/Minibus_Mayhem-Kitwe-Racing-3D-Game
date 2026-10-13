class_name CallBoy
extends Node
## The conductor hanging out of the player's minibus door. Shouts stop names,
## warns about police and fuel, reacts to fines, a full bus and poaching rivals.
## TODO(Phase 3): move lines to data/dialogue/*.csv and record real voices;
## check the Bemba/Zambian-English slang with people from Kitwe.

const COOLDOWN := 2.0

var bus: Minibus
var route: RouteManager

var _announced: BusStop = null
var _warned_checkpoint: PoliceCheckpoint = null
var _warned_fuel := false
var _cooldown := 0.0


func _ready() -> void:
	EventBus.passenger_boarded.connect(_on_boarded)
	EventBus.fined.connect(_on_fined)
	EventBus.refuelled.connect(_on_refuelled)


func _process(delta: float) -> void:
	_cooldown -= delta
	var here := bus.route_progress

	var cp := route.next_checkpoint(here)
	if cp and cp != _warned_checkpoint and not cp.is_cleared(bus):
		var d := route.signed_distance(here, cp.route_offset, PoliceCheckpoint.ZONE_AFTER)
		if d < 260.0:
			_warned_checkpoint = cp
			if bus.is_overloaded():
				_say("Ba police ahead! We're overloaded, driver, they'll fine us!", true)
			else:
				_say("Police ahead! Slow down, %d only." % cp.speed_limit_kmh, true)
			return
	if cp and cp.is_cleared(bus):
		_warned_checkpoint = null  # warn again next lap

	if bus.uses_fuel and not _warned_fuel and bus.fuel_l < 1.5:
		_warned_fuel = true
		_say("Driver, the diesel is finishing! Find a filling station!", true)
		return

	var stop := route.next_stop(here)
	if stop == _announced or route.stop_distance(here, stop) > 70.0:
		return
	if stop.wants_service(bus):
		_announced = stop
		if bus.has_passenger_for(stop.stop_index):
			_say("Driver, pa stop! %s!" % stop.stop_name, true)
		else:
			_say("%s! %s! %d waiting!" % [stop.stop_name, stop.stop_name, stop.waiting], true)


func _on_boarded(boarding_bus: Node, stop: Node, fare: int) -> void:
	if boarding_bus == bus:
		if bus.free_seats() == 0:
			_say("Bus is full! Tuleya, driver!", true)
		elif bus.is_overloaded() and randf() < 0.5:
			_say("Squeeze, squeeze! Mama, move up a bit!")
		elif randf() < 0.3:
			_say("+K%d. Squeeze in, ba boss!" % fare)
	elif stop == _announced:
		_say("Eh! %s is taking our passengers at %s!" % [(boarding_bus as Minibus).driver_name, (stop as BusStop).stop_name])


func _on_fined(fined_bus: Node, _amount: int, _reason: String) -> void:
	if fined_bus != bus:
		return
	_cooldown = COOLDOWN * 2.0  # let the HUD's fine message stay on screen


func _on_refuelled(refuelled_bus: Node, litres: float, cost: int) -> void:
	if refuelled_bus == bus and litres > 0.1:
		_warned_fuel = false
		_say("Filled %.0f L for K%d. Tuleya!" % [litres, cost], true)


func _say(text: String, important := false) -> void:
	if _cooldown > 0.0 and not important:
		return
	_cooldown = COOLDOWN
	EventBus.bark.emit(text)
