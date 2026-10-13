# Minibus Mayhem: Kitwe

A 3D minibus racing game set in Kitwe, Zambia. Race rival minibuses on the
left-hand side of the road, stop for passengers, and earn the most kwacha.

**Status:** Phase 2 alpha — three routes over real Kitwe streets, two rivals,
traffic, police checkpoints, fuel, garage upgrades and a rainy season.
See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

Map data © OpenStreetMap contributors (ODbL).

## Rebuild the map from OpenStreetMap
Edit `ROUTES` / `BBOX` at the top of `tools/osm_import.py`, then (optionally pass route ids):
```
python tools/osm_import.py
```
Raw downloads are cached in `tools/osm_cache/`; add `--refresh` to re-download.
The Overpass servers are often busy — the tool retries several mirrors automatically.
The old graybox loop is still available: `data/routes/town_chimwemwe_loop.tres`.

## Run it
1. Install **Godot 4.4 or newer** (Standard edition, not .NET): https://godotengine.org/download
2. Open Godot → **Import** → select `project.godot` in this folder.
3. Press **F5** (Run Project).

## Smoke test (headless)
Simulates 90 s of racing and prints what the buses did:
```
godot --headless --path . --script res://tests/smoke_test.gd
```

## Controls
| Action | Keyboard | Gamepad |
|---|---|---|
| Accelerate | W / ↑ | Right trigger |
| Brake / reverse | S / ↓ | Left trigger |
| Steer | A D / ← → | Left stick |
| Handbrake | Space | A |
| Squeeze (overload) on/off | Q | X |
| Reset bus onto road | R | Y |
| Play again (after results) | Enter | Start |
| Back to menu | Esc | Back |

On a touchscreen, on-screen buttons appear automatically (steer, GO, BRAKE, HB, RESET, SQZ).

**How to play:** pick a route and season, then follow the gold line on the minimap;
green dots are stops with passengers waiting. Stop (nearly at a standstill) inside a
yellow bus bay. Watch your diesel (stop at a filling station), stop at police
checkpoints and keep under the limit near them. Squeezing extra riders in pays more,
until the police count heads. Spend your take-home in the garage.

At a stop, riders for that stop get off first, then waiting passengers board and pay
K10 each. A fuller bus is heavier and slower. Out-earn both rivals before time runs out.

## Layout
```
autoload/      InputSetup, EventBus, GameState
data/          routes, vehicles, rivals, upgrades, weather (*.tres: tune here); osm/*.json maps
scenes/shell/  main_menu.tscn (main scene)
scenes/race/   race_session.tscn
scripts/
  ai/          AIDriver
  traffic/     TrafficManager, TrafficCar
  data/        RouteDef, VehicleDef, RivalDef, UpgradeDef, WeatherDef
  gameplay/    RaceSession, RouteManager, BusStop, PoliceCheckpoint, FuelStation, CallBoy
  ui/          MainMenu, Hud, Minimap, TouchControls, ChaseCamera
  vehicles/    Minibus, PlayerDriver
  world/       OsmWorld, GrayboxWorld, WeatherSystem, Graybox helpers
docs/          plan & architecture
```
