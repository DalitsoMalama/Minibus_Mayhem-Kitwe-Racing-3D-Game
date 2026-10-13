extends Node3D
## A race on one route: the player's minibus vs data-driven rivals, with
## traffic, police, fuel and weather. Most kwacha (after fines and fuel) wins.

const PLAYER_START := 40.0  ## metres along the route
const START_FUEL_L := 5.0  ## the owner only left you a little diesel
const JERRYCAN_L := 4.0
const JERRYCAN_PRICE_PER_L := 60.0  ## roadside jerrycans cost double
const MENU_SCENE := "res://scenes/shell/main_menu.tscn"

@export var route: RouteDef
@export var player_vehicle: VehicleDef
@export var rivals: Array[RivalDef] = []
## Null = the season chosen in the menu (GameState).
@export var weather: WeatherDef

var route_manager: RouteManager
var player: Minibus
var rival_buses: Array[Minibus] = []
var buses: Array[Minibus] = []
var traffic: TrafficManager
var hud: Hud
var touch: TouchControls
var time_left := 0.0
var finished := false

var _empty_time := 0.0


func _ready() -> void:
	if GameState.launch_from_menu and GameState.selected_route != "":
		route = load(GameState.selected_route)
	if weather == null:
		weather = GameState.weather()

	route_manager = RouteManager.new()
	route_manager.name = "Route"
	route_manager.route = route
	route_manager.passenger_rate_mult = weather.passenger_rate_mult
	add_child(route_manager)

	var world: GrayboxWorld = OsmWorld.new() if route.map_data != "" else GrayboxWorld.new()
	world.name = "World"
	add_child(world)
	world.build(route_manager)

	player = _spawn_bus(GameState.build_player_vehicle(player_vehicle), "You", PLAYER_START)
	player.uses_fuel = true
	player.fuel_l = minf(START_FUEL_L, player.def.fuel_capacity_l)
	player.out_of_fuel.connect(func() -> void: EventBus.bark.emit("Eh! We're out of diesel, driver!"))
	player.add_child(PlayerDriver.new())
	var drivers: Array[AIDriver] = []
	for def in rivals:
		var bus := _spawn_bus(def.vehicle, def.driver_name, def.start_offset)
		bus.squeeze = def.squeezes
		var ai := AIDriver.new()
		ai.route = route_manager
		ai.cruise_speed = def.cruise_speed
		ai.corner_speed = def.corner_speed
		bus.add_child(ai)
		drivers.append(ai)
		rival_buses.append(bus)
	route_manager.set_buses(buses)

	traffic = TrafficManager.new()
	traffic.name = "Traffic"
	add_child(traffic)
	traffic.start(route_manager, player, buses)
	for ai in drivers:
		ai.traffic = traffic.obstacles

	var camera := ChaseCamera.new()
	add_child(camera)
	camera.follow(player)

	var weather_system := WeatherSystem.new()
	weather_system.name = "Weather"
	add_child(weather_system)
	weather_system.apply(weather, world, camera, route_manager)

	var call_boy := CallBoy.new()
	call_boy.bus = player
	call_boy.route = route_manager
	add_child(call_boy)

	hud = Hud.new()
	add_child(hud)
	hud.route = route_manager
	var roads: Array[Dictionary] = []
	if world is OsmWorld:
		roads = (world as OsmWorld).roads_2d
		hud.set_credit("Map data © OpenStreetMap contributors")
	hud.minimap.setup(route_manager, buses, player, roads)
	hud.drive_again_pressed.connect(_drive_again)
	hud.menu_pressed.connect(_to_menu)
	touch = TouchControls.new()
	add_child(touch)

	time_left = route.time_limit_sec
	EventBus.bark.emit("%s, %s: earn the most kwacha in %d minutes!" % [
		route.route_name, weather.display_name.to_lower(), int(route.time_limit_sec / 60.0)])


func _physics_process(delta: float) -> void:
	for bus in buses:
		bus.route_progress = route_manager.closest_offset(bus.global_position, bus.route_progress)
	_jerrycan_rescue(delta)


func _process(delta: float) -> void:
	if finished:
		return
	time_left = maxf(time_left - delta, 0.0)
	var next := route_manager.next_stop(player.route_progress)
	hud.update_stats(player, buses, time_left, next.stop_name, route_manager.stop_distance(player.route_progress, next))
	if time_left <= 0.0:
		_finish()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"reset_bus") and not finished:
		player.reset_to(route_manager.lane_transform(player.route_progress, RouteManager.LEFT_LANE, 1.0))
	elif event.is_action_pressed(&"restart") and finished:
		_drive_again()
	elif event.is_action_pressed(&"menu"):
		_to_menu()


## Stranded with an empty tank: a roadside seller brings a jerrycan, at a price.
func _jerrycan_rescue(delta: float) -> void:
	if finished or player.fuel_l > 0.0 or absf(player.forward_speed()) > 0.5:
		_empty_time = 0.0
		return
	_empty_time += delta
	if _empty_time > 3.0:
		_empty_time = 0.0
		player.refuel(JERRYCAN_L, JERRYCAN_PRICE_PER_L)
		EventBus.bark.emit("A kantemba seller brings a jerrycan: %d L for K%d" % [JERRYCAN_L, int(JERRYCAN_L * JERRYCAN_PRICE_PER_L)])


func _spawn_bus(base_def: VehicleDef, driver: String, offset: float) -> Minibus:
	var def: VehicleDef = base_def.duplicate()
	def.wheel_grip *= weather.grip_mult
	var bus := Minibus.new()
	bus.name = driver.validate_node_name()
	bus.def = def
	bus.driver_name = driver
	bus.is_player = buses.is_empty()
	bus.transform = route_manager.lane_transform(offset, RouteManager.LEFT_LANE, 1.0)
	bus.route_progress = route_manager.wrap_offset(offset)
	add_child(bus)
	buses.append(bus)
	return bus


func _finish() -> void:
	finished = true
	for bus in buses:
		bus.controls_enabled = false
	GameState.record_race(player.earnings)
	EventBus.race_finished.emit(player.earnings)
	hud.show_results(player, rival_buses, GameState.total_kwacha)
	touch.set_race_over(true)


func _drive_again() -> void:
	get_tree().reload_current_scene()


func _to_menu() -> void:
	GameState.launch_from_menu = false
	get_tree().change_scene_to_file(MENU_SCENE)
