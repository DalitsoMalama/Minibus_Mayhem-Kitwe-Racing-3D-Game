extends Node
## Persistent player progress: bank balance, garage upgrades, last route and
## season. Offline-first: saved as JSON in user://.

const SAVE_PATH := "user://save.json"
const ROUTES := [
	"res://data/routes/kitwe_town_loop.tres",
	"res://data/routes/kitwe_parklands.tres",
	"res://data/routes/kitwe_chimwemwe.tres",
]
const WEATHERS := ["res://data/weather/dry.tres", "res://data/weather/rainy.tres"]
const UPGRADES := [
	"res://data/upgrades/engine.tres",
	"res://data/upgrades/tyres.tres",
	"res://data/upgrades/seats.tres",
	"res://data/upgrades/fuel_tank.tres",
	"res://data/upgrades/brakes.tres",
	"res://data/upgrades/suspension.tres",
]
const PAINTS := [Color(0.13, 0.36, 0.78), Color(0.1, 0.55, 0.3), Color(0.8, 0.15, 0.15), Color(0.95, 0.95, 0.92)]

## Kwacha saved from races, spent in the garage.
var total_kwacha := 0
var best_run := 0
var races_played := 0
var upgrade_levels := {}  ## upgrade id -> level
var paint := 0
var selected_route := ""  ## empty = use the scene's default route
var selected_weather := 0
## Set by the menu just before loading a race (not saved): use the selections above.
var launch_from_menu := false
## Tests turn this off so simulated races never touch the player's save.
var persist := true


func _ready() -> void:
	load_game()


func record_race(earned: int) -> void:
	if not persist:
		return
	total_kwacha = maxi(total_kwacha + earned, 0)
	best_run = maxi(best_run, earned)
	races_played += 1
	save_game()


func upgrade_level(id: String) -> int:
	return int(upgrade_levels.get(id, 0))


## Buys the next level of an upgrade. Returns false if maxed or unaffordable.
func buy_upgrade(upgrade: UpgradeDef) -> bool:
	var level := upgrade_level(upgrade.id)
	if level >= upgrade.max_level() or total_kwacha < upgrade.prices[level]:
		return false
	total_kwacha -= upgrade.prices[level]
	upgrade_levels[upgrade.id] = level + 1
	save_game()
	return true


func weather() -> WeatherDef:
	return load(WEATHERS[clampi(selected_weather, 0, WEATHERS.size() - 1)])


## The player's bus with every purchased upgrade and the chosen paint applied.
func build_player_vehicle(base: VehicleDef) -> VehicleDef:
	var def: VehicleDef = base.duplicate()
	for path in UPGRADES:
		var upgrade: UpgradeDef = load(path)
		upgrade.apply(def, upgrade_level(upgrade.id))
	def.body_color = PAINTS[clampi(paint, 0, PAINTS.size() - 1)]
	return def


func save_game() -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("Could not write save: %s" % FileAccess.get_open_error())
		return
	file.store_string(JSON.stringify({
		"total_kwacha": total_kwacha,
		"best_run": best_run,
		"races_played": races_played,
		"upgrade_levels": upgrade_levels,
		"paint": paint,
		"selected_route": selected_route,
		"selected_weather": selected_weather,
	}))


func load_game() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var data = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if data is Dictionary:
		total_kwacha = int(data.get("total_kwacha", 0))
		best_run = int(data.get("best_run", 0))
		races_played = int(data.get("races_played", 0))
		paint = int(data.get("paint", 0))
		selected_route = str(data.get("selected_route", ""))
		selected_weather = int(data.get("selected_weather", 0))
		var levels = data.get("upgrade_levels", {})
		if levels is Dictionary:
			for id in levels:
				upgrade_levels[id] = int(levels[id])
