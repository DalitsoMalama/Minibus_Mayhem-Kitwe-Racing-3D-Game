class_name WeatherDef
extends Resource
## A season / weather profile. Zambia has a dry season (May-October) and a
## rainy season (November-April) with heavy afternoon storms.

@export var display_name := "Dry season"
@export_multiline var description := ""
@export var rain := false
## Multiplies every bus's tyre grip.
@export var grip_mult := 1.0
## Multiplies how fast passengers arrive at stops (everyone wants a lift in the rain).
@export var passenger_rate_mult := 1.0
@export var sky_top := Color(0.25, 0.5, 0.85)
@export var sky_horizon := Color(0.78, 0.82, 0.88)
@export var fog_color := Color(0.8, 0.7, 0.6)
@export var fog_density := 0.002
@export var sun_energy := 1.0
## Road surface roughness (lower = wet and shiny).
@export var road_roughness := 0.9
## Number of puddles scattered on the route.
@export var puddles := 0
