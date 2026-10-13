class_name UpgradeDef
extends Resource
## A garage upgrade bought with saved kwacha. Each level adds `per_level` to
## one VehicleDef stat (see GameState.build_player_vehicle).

enum Stat { ENGINE, GRIP, SEATS, FUEL_TANK, BRAKES, SUSPENSION }

@export var id := ""
@export var display_name := ""
@export_multiline var description := ""
@export var stat: Stat = Stat.ENGINE
@export var per_level := 0.0
## Price of each level in kwacha; the array length is the max level.
@export var prices := PackedInt32Array()


func max_level() -> int:
	return prices.size()


## Applies `level` levels of this upgrade to a vehicle definition in place.
func apply(def: VehicleDef, level: int) -> void:
	var amount := per_level * level
	match stat:
		Stat.ENGINE:
			def.max_engine_force *= 1.0 + amount
			def.top_speed_kmh += amount * 40.0
		Stat.GRIP:
			def.wheel_grip += amount
		Stat.SEATS:
			def.seats += int(amount)
		Stat.FUEL_TANK:
			def.fuel_capacity_l += amount
		Stat.BRAKES:
			def.max_brake *= 1.0 + amount
		Stat.SUSPENSION:
			def.suspension_stiffness *= 1.0 + amount
			def.damping_compression *= 1.0 + amount * 0.5
