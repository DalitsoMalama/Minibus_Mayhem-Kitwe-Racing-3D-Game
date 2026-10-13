class_name VehicleDef
extends Resource
## Handling and capacity for a minibus. Tune feel here, not in code.

@export var display_name := "Toyota HiAce"
@export var body_color := Color(0.13, 0.36, 0.78)
@export var seats := 15

@export_group("Mass")
@export var empty_mass_kg := 2000.0
## Every passenger makes the bus heavier, so a full bus is slower and less nimble.
@export var passenger_mass_kg := 70.0

@export_group("Drive")
@export var max_engine_force := 6000.0
@export var reverse_force := 2500.0
@export var max_brake := 60.0
@export var max_steer_deg := 32.0
@export var top_speed_kmh := 110.0

@export_group("Fuel")
@export var fuel_capacity_l := 30.0
## Game-scaled consumption (city stop-start driving, overloaded, old engine).
@export var fuel_l_per_km := 0.5
@export var fuel_idle_l_per_min := 0.25

@export_group("Wheels")
@export var wheel_grip := 2.5
@export var suspension_stiffness := 40.0
@export var suspension_max_force := 28000.0
@export var damping_compression := 0.9
@export var damping_relaxation := 1.0
