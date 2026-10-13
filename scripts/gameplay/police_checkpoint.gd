class_name PoliceCheckpoint
extends Node3D
## A roadside police checkpoint, a familiar sight on Zambian roads. Every bus
## must stop for inspection. A speed trap before it catches anyone over the
## limit, overloaded buses are fined per extra rider (who must get off), and
## driving through without stopping costs the most.

const ZONE_BEFORE := 14.0  ## stop anywhere from 14 m before...
const ZONE_AFTER := 6.0  ## ...to 6 m past the officer
const TRAP_DISTANCE := 150.0
const INSPECT_TIME := 2.0
const FINE_SPEEDING := 50
const FINE_PER_EXTRA_RIDER := 40
const FINE_NO_STOP := 150

var route: RouteManager
var route_offset := 0.0
var speed_limit_kmh := 60
var buses: Array[Minibus] = []

var _state := {}  ## Minibus -> {prev: float, stopped: float, inspected: bool}


func _ready() -> void:
	_build_visuals()


## True once this bus has been inspected on its current pass.
func is_cleared(bus: Minibus) -> bool:
	return _state.has(bus) and _state[bus]["inspected"]


func _physics_process(delta: float) -> void:
	for bus in buses:
		if not _state.has(bus):
			_state[bus] = {"prev": INF, "stopped": 0.0, "inspected": false}
		var s: Dictionary = _state[bus]
		var d := route.signed_distance(bus.route_progress, route_offset, 40.0)
		var prev: float = s["prev"]
		s["prev"] = d
		if d > TRAP_DISTANCE + 60.0:
			s["inspected"] = false  # next lap
			s["stopped"] = 0.0
			continue

		# Speed trap.
		if prev > TRAP_DISTANCE and d <= TRAP_DISTANCE and prev - d < 30.0:
			var kmh := absf(bus.forward_speed()) * 3.6
			if kmh > speed_limit_kmh + 5:
				bus.fine(FINE_SPEEDING, "Speeding: %d km/h in a %d zone" % [kmh, speed_limit_kmh])

		# Inspection zone.
		if d < ZONE_BEFORE and d > -ZONE_AFTER and not s["inspected"]:
			if absf(bus.forward_speed()) < BusStop.STOP_SPEED:
				s["stopped"] += delta
				if s["stopped"] >= INSPECT_TIME:
					s["inspected"] = true
					_inspect(bus)
		elif prev >= -ZONE_AFTER and d < -ZONE_AFTER and prev - d < 30.0 and not s["inspected"]:
			s["inspected"] = true
			bus.fine(FINE_NO_STOP, "Drove through a police checkpoint")


func _inspect(bus: Minibus) -> void:
	if bus.is_overloaded():
		var extra := bus.offload_extra()
		bus.fine(FINE_PER_EXTRA_RIDER * extra, "Overloaded by %d" % extra)
	elif bus.is_player:
		EventBus.bark.emit("Officer: \"Proceed.\"")


# Local +X is the kerb side (see RouteManager.lane_transform).
func _build_visuals() -> void:
	for z in range(-12, 13, 3):
		var cone := CylinderMesh.new()
		cone.top_radius = 0.03
		cone.bottom_radius = 0.22
		cone.height = 0.7
		cone.material = Graybox.mat(Color(1.0, 0.45, 0.05))
		var mi := MeshInstance3D.new()
		mi.mesh = cone
		mi.position = Vector3(-3.1, 0.35, z)
		add_child(mi)
	var officer := CapsuleMesh.new()
	officer.radius = 0.28
	officer.height = 1.75
	officer.material = Graybox.mat(Color(0.85, 0.8, 0.6))
	var mi := MeshInstance3D.new()
	mi.mesh = officer
	mi.position = Vector3(4.2, 0.88, 0)
	add_child(mi)
	Graybox.box(self, Vector3(0.6, 0.25, 0.62), Vector3(4.2, 1.85, 0), Color(0.15, 0.2, 0.35))  # cap
	# Parked patrol car on the verge.
	Graybox.box(self, Vector3(1.8, 1.0, 4.2), Vector3(8.0, 0.75, -8.0), Color(0.95, 0.95, 0.95))
	Graybox.box(self, Vector3(1.82, 0.25, 4.22), Vector3(8.0, 0.9, -8.0), Color(0.1, 0.2, 0.6))
	Graybox.box(self, Vector3(1.6, 0.6, 2.2), Vector3(8.0, 1.5, -8.3), Color(0.15, 0.17, 0.2))
	var board := Label3D.new()
	board.text = "POLICE CHECKPOINT\nSTOP"
	board.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	board.modulate = Color(1, 0.9, 0.3)
	board.font_size = 72
	board.outline_size = 16
	board.pixel_size = 0.01
	board.position = Vector3(5.0, 3.5, 0)
	add_child(board)
