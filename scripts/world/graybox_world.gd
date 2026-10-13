class_name GrayboxWorld
extends Node3D
## Phase 0 stand-in for Kitwe: red Copperbelt soil, a road loop, shop blocks with
## tin roofs and a mine headframe. Replaced by OSM-generated chunks in Phase 1.

const SOIL := Color(0.56, 0.32, 0.2)
const ROAD := Color(0.18, 0.18, 0.19)
const LINE := Color(0.9, 0.9, 0.85)
const TIN := Color(0.55, 0.56, 0.58)
const STEEL := Color(0.35, 0.3, 0.28)
const WALLS := [
	Color(0.93, 0.88, 0.74), Color(0.62, 0.78, 0.86), Color(0.85, 0.62, 0.32),
	Color(0.9, 0.7, 0.72), Color(0.75, 0.82, 0.6), Color(0.95, 0.95, 0.93),
]


## Exposed so WeatherSystem can restyle the scene.
var environment: Environment
var sky_material: ProceduralSkyMaterial
var sun: DirectionalLight3D
var road_material: StandardMaterial3D


func build(route: RouteManager) -> void:
	_build_environment()
	Graybox.solid_box(self, Vector3(1000, 1, 800), Vector3(0, -0.5, 0), SOIL)
	road_material = Graybox.mat(ROAD)
	_build_road(route)
	_build_town(route)
	_build_headframe(Vector3.ZERO)


func _build_environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.25, 0.5, 0.85)
	sky_mat.sky_horizon_color = Color(0.78, 0.82, 0.88)
	sky_mat.ground_horizon_color = Color(0.6, 0.5, 0.42)
	var sky := Sky.new()
	sky.sky_material = sky_mat

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color(0.8, 0.7, 0.6)  # dry-season dust
	env.fog_density = 0.002

	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)
	environment = env
	sky_material = sky_mat

	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -30, 0)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 150.0
	add_child(sun)


func _build_road(route: RouteManager) -> void:
	var pts := route.route.path_points
	var width := route.route.road_width
	for i in pts.size():
		var a := pts[i]
		var b := pts[(i + 1) % pts.size()]
		var mid := (a + b) * 0.5
		var seg_len := a.distance_to(b)
		var basis := Basis.looking_at(b - a, Vector3.UP)
		var road := Graybox.box(self, Vector3(width, 0.02, seg_len + width), mid + Vector3(0, 0.01, 0), ROAD)
		road.basis = basis
		var line := Graybox.box(self, Vector3(0.2, 0.02, seg_len - width), mid + Vector3(0, 0.025, 0), LINE)
		line.basis = basis


func _build_town(route: RouteManager) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1964  # fixed seed: same town layout every run
	for x in range(-340, 341, 28):
		for z in range(-240, 241, 28):
			if rng.randf() < 0.35:
				continue
			var pos := Vector3(x + rng.randf_range(-5, 5), 0, z + rng.randf_range(-5, 5))
			var size := Vector3(rng.randf_range(8, 16), rng.randf_range(3.5, 9), rng.randf_range(8, 16))
			var to_road := pos.distance_to(route.curve.get_closest_point(pos))
			if to_road < 22.0 or pos.length() < 30.0:
				continue
			var wall: Color = WALLS[rng.randi() % WALLS.size()]
			var shop := Graybox.solid_box(self, size, pos + Vector3(0, size.y * 0.5, 0), wall)
			Graybox.box(shop, Vector3(size.x + 0.6, 0.25, size.z + 0.6), Vector3(0, size.y * 0.5 + 0.1, 0), TIN)


## Placeholder for the Nkana mine headframe, the landmark you see across town.
func _build_headframe(base: Vector3) -> void:
	var root := Node3D.new()
	root.name = "NkanaHeadframe"
	root.position = base
	add_child(root)
	for sx in [-3, 3]:
		for sz in [-3, 3]:
			Graybox.solid_box(root, Vector3(0.8, 40, 0.8), Vector3(sx, 20, sz), STEEL)
	for h in [10, 20, 30, 40]:
		Graybox.box(root, Vector3(7, 0.6, 7), Vector3(0, h, 0), STEEL)
	var torus := TorusMesh.new()
	torus.inner_radius = 2.6
	torus.outer_radius = 3.0
	torus.material = Graybox.mat(STEEL)
	var sheave := MeshInstance3D.new()
	sheave.mesh = torus
	sheave.position = Vector3(0, 43.5, 0)
	sheave.rotation_degrees = Vector3(90, 0, 0)
	root.add_child(sheave)
