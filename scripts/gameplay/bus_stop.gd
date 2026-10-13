class_name BusStop
extends Area3D
## A roadside stop. Passengers queue here over time; whichever minibus stops in
## the bay first gets them. Riders for this stop get off before new ones board.

const BOARD_INTERVAL := 0.5
const STOP_SPEED := 1.5  ## m/s: the bus must be (nearly) stopped to load.
const MAX_TRIP_STOPS := 5
const CHITENGE := [
	Color(0.95, 0.5, 0.1), Color(0.1, 0.6, 0.6), Color(0.8, 0.15, 0.5),
	Color(0.95, 0.8, 0.15), Color(0.2, 0.6, 0.2), Color(0.8, 0.15, 0.15),
]

@export var max_waiting := 8
@export var spawn_interval := 7.0  ## divided by the weather's passenger_rate_mult

var stop_index := 0
var stop_name := ""
var route_offset := 0.0
var stop_count := 1
var fare := 10
var waiting := 0
var rate_mult := 1.0  ## from the weather: more people want a lift in the rain

var _buses: Array[Minibus] = []
var _board_timer := 0.0
var _spawn_timer := 0.0
var _people: Node3D
var _sign: Label3D


func setup(index: int, display_name: String, offset_m: float, count: int, fare_kwacha: int) -> void:
	stop_index = index
	stop_name = display_name
	route_offset = offset_m
	stop_count = count
	fare = fare_kwacha
	waiting = randi_range(2, 5)
	_spawn_timer = spawn_interval


func _ready() -> void:
	var box := BoxShape3D.new()
	box.size = Vector3(8, 4, 18)
	var col := CollisionShape3D.new()
	col.shape = box
	col.position = Vector3(0, 2, 0)
	add_child(col)
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_build_visuals()
	_refresh_people()


func wants_service(bus: Minibus) -> bool:
	return bus.has_passenger_for(stop_index) or (waiting > 0 and bus.free_seats() > 0)


func _physics_process(delta: float) -> void:
	_spawn_timer -= delta
	if _spawn_timer <= 0.0:
		_spawn_timer = spawn_interval / rate_mult * randf_range(0.7, 1.3)
		if waiting < max_waiting:
			waiting += 1
			_refresh_people()

	_board_timer -= delta
	if _board_timer > 0.0:
		return
	# First bus to arrive is served first.
	for bus in _buses:
		if absf(bus.forward_speed()) > STOP_SPEED:
			continue
		if bus.drop_passenger_for(stop_index):
			EventBus.passenger_alighted.emit(bus, self)
			_board_timer = BOARD_INTERVAL
			return
		if waiting > 0 and bus.free_seats() > 0:
			waiting -= 1
			# Most riders only go a few stops, so seats keep turning over.
			bus.add_passenger((stop_index + randi_range(1, mini(MAX_TRIP_STOPS, stop_count - 1))) % stop_count)
			bus.fares += fare
			EventBus.passenger_boarded.emit(bus, self, fare)
			_refresh_people()
			_board_timer = BOARD_INTERVAL
			return


func _on_body_entered(body: Node3D) -> void:
	if body is Minibus and not _buses.has(body):
		_buses.append(body)


func _on_body_exited(body: Node3D) -> void:
	if body is Minibus:
		_buses.erase(body)


# Local +X points to the kerb side (left of the road), see RouteManager.lane_transform.
func _build_visuals() -> void:
	Graybox.box(self, Vector3(5.5, 0.02, 16), Vector3(0, 0.04, 0), Color(0.95, 0.75, 0.1, 0.35))
	Graybox.box(self, Vector3(2.6, 0.15, 6), Vector3(5.8, 2.6, 0), Color(0.2, 0.45, 0.25))
	for z in [-2.8, 2.8]:
		Graybox.box(self, Vector3(0.15, 2.6, 0.15), Vector3(4.7, 1.3, z), Color(0.3, 0.3, 0.3))
	Graybox.box(self, Vector3(0.6, 0.45, 4), Vector3(6.4, 0.25, 0), Color(0.45, 0.3, 0.2))

	_sign = Label3D.new()
	_sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_sign.position = Vector3(5.8, 4.0, 0)
	_sign.font_size = 72
	_sign.outline_size = 16
	_sign.pixel_size = 0.01
	add_child(_sign)

	_people = Node3D.new()
	add_child(_people)


func _refresh_people() -> void:
	_sign.text = "%s\n%d waiting" % [stop_name, waiting]
	for child in _people.get_children():
		child.queue_free()
	for i in waiting:
		var capsule := CapsuleMesh.new()
		capsule.radius = 0.25
		capsule.height = 1.65
		capsule.material = Graybox.mat(CHITENGE[(i + stop_index) % CHITENGE.size()])
		var person := MeshInstance3D.new()
		person.mesh = capsule
		person.position = Vector3(5.0 + (i % 2) * 0.8, 0.83, -5.0 + i * 1.3)
		_people.add_child(person)
