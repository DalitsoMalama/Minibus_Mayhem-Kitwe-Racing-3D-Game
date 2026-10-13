class_name RivalDef
extends Resource
## A rival minibus driver: who they are, what they drive, how hard they push.

@export var driver_name := "Rival"
@export var vehicle: VehicleDef
@export var cruise_speed := 14.0  ## m/s on straights
@export var corner_speed := 6.0
## Metres along the route where this rival starts (negative = behind the start line).
@export var start_offset := 15.0
## Reckless rivals overload their bus (more fares, but police fines).
@export var squeezes := false
