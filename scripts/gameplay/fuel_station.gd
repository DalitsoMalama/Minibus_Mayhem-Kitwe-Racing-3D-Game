class_name FuelStation
extends Node3D
## A roadside filling station. Stop at the kerb in front of it and the
## attendant fills the tank; the cost comes out of this race's earnings.

const PRICE_PER_L := 28.0  ## roughly Zambian diesel pump price, kwacha per litre
const FILL_RATE := 4.0  ## litres per second
const ZONE_BEFORE := 10.0
const ZONE_AFTER := 10.0

var route: RouteManager
var route_offset := 0.0
var buses: Array[Minibus] = []

var _filling := {}  ## Minibus -> [litres, cost] so far this visit


func _ready() -> void:
	_build_visuals()


func _physics_process(delta: float) -> void:
	for bus in buses:
		if not bus.uses_fuel:
			continue
		var d := route.signed_distance(bus.route_progress, route_offset, ZONE_AFTER + 5.0)
		var at_pump := d < ZONE_BEFORE and d > -ZONE_AFTER and absf(bus.forward_speed()) < BusStop.STOP_SPEED
		if at_pump and bus.fuel_l < bus.def.fuel_capacity_l - 0.05:
			var before := bus.fuel_spent
			var litres := bus.refuel(FILL_RATE * delta, PRICE_PER_L)
			var visit: Array = _filling.get(bus, [0.0, 0])
			_filling[bus] = [visit[0] + litres, visit[1] + bus.fuel_spent - before]
		elif _filling.has(bus):
			var visit: Array = _filling[bus]
			_filling.erase(bus)
			EventBus.refuelled.emit(bus, visit[0], visit[1])


func _build_visuals() -> void:
	var concrete := Color(0.62, 0.62, 0.6)
	Graybox.box(self, Vector3(14, 0.06, 26), Vector3(14.0, 0.03, 0), concrete)  # forecourt
	for x in [9.0, 19.0]:
		for z in [-8.0, 8.0]:
			Graybox.box(self, Vector3(0.35, 4.5, 0.35), Vector3(x, 2.25, z), Color(0.9, 0.9, 0.9))
	Graybox.box(self, Vector3(12, 0.5, 20), Vector3(14.0, 4.7, 0), Color(0.85, 0.1, 0.1))  # canopy
	for z in [-4.0, 4.0]:
		Graybox.box(self, Vector3(0.8, 1.6, 1.0), Vector3(12.0, 0.8, z), Color(0.95, 0.95, 0.95))  # pumps
	Graybox.box(self, Vector3(8, 3.5, 6), Vector3(22.0, 1.75, 6.0), Color(0.95, 0.92, 0.8))  # shop
	var board := Label3D.new()
	board.text = "FILLING STATION\nDiesel K%d/L" % int(PRICE_PER_L)
	board.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	board.font_size = 72
	board.outline_size = 16
	board.pixel_size = 0.012
	board.position = Vector3(8.0, 6.5, 0)
	add_child(board)
