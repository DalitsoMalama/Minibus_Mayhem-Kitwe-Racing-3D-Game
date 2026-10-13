class_name WeatherSystem
extends Node3D
## Applies a WeatherDef to the scene: sky, fog, sunlight, wet road sheen,
## falling rain around the camera, and puddles on the route that drag buses.
## Grip and passenger rates are applied by RaceSession / RouteManager.

var weather: WeatherDef
var _puddles: Array[Area3D] = []


func apply(def: WeatherDef, world: GrayboxWorld, camera: Camera3D, route: RouteManager) -> void:
	weather = def
	world.sky_material.sky_top_color = def.sky_top
	world.sky_material.sky_horizon_color = def.sky_horizon
	world.environment.fog_light_color = def.fog_color
	world.environment.fog_density = def.fog_density
	world.sun.light_energy = def.sun_energy
	world.road_material.roughness = def.road_roughness
	if def.rain:
		world.road_material.metallic_specular = 0.9
		_add_rain(camera)
	_add_puddles(def.puddles, route)


func _add_rain(camera: Camera3D) -> void:
	var drop := BoxMesh.new()
	drop.size = Vector3(0.02, 0.6, 0.02)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.75, 0.8, 0.9, 0.45)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	drop.material = mat
	var rain := CPUParticles3D.new()
	rain.name = "Rain"
	rain.mesh = drop
	rain.amount = 1400
	rain.lifetime = 1.2
	rain.preprocess = 1.2
	rain.local_coords = false
	rain.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	rain.emission_box_extents = Vector3(30, 1, 30)
	rain.direction = Vector3(0.1, -1, 0)
	rain.spread = 3.0
	rain.initial_velocity_min = 22.0
	rain.initial_velocity_max = 28.0
	rain.gravity = Vector3(0, -10, 0)
	rain.position = Vector3(0, 14, -12)  # above and ahead of the camera
	camera.add_child(rain)


func _add_puddles(count: int, route: RouteManager) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026
	var water := StandardMaterial3D.new()
	water.albedo_color = Color(0.16, 0.18, 0.2)
	water.roughness = 0.05
	water.metallic_specular = 1.0
	for i in count:
		var offset := rng.randf_range(0.0, route.length)
		var lane := RouteManager.LEFT_LANE * (1.0 if rng.randf() < 0.6 else -1.0) + rng.randf_range(-1.5, 1.5)
		var disc := CylinderMesh.new()
		disc.top_radius = rng.randf_range(1.2, 2.6)
		disc.bottom_radius = disc.top_radius
		disc.height = 0.02
		disc.radial_segments = 12
		disc.material = water
		var puddle := Area3D.new()
		puddle.name = "Puddle%d" % i
		puddle.position = route.lane_point(offset, lane) + Vector3(0, 0.06, 0)
		var mi := MeshInstance3D.new()
		mi.mesh = disc
		puddle.add_child(mi)
		var shape := CylinderShape3D.new()
		shape.radius = disc.top_radius
		shape.height = 1.5
		var col := CollisionShape3D.new()
		col.shape = shape
		puddle.add_child(col)
		add_child(puddle)
		_puddles.append(puddle)


## Water drag: buses splashing through puddles lose a little speed.
func _physics_process(delta: float) -> void:
	for puddle in _puddles:
		for body in puddle.get_overlapping_bodies():
			if body is Minibus:
				var bus := body as Minibus
				bus.linear_velocity = bus.linear_velocity * (1.0 - 0.8 * delta)
