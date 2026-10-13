class_name OsmWorld
extends GrayboxWorld
## Kitwe built from OpenStreetMap data (see tools/osm_import.py): real streets,
## building footprints and roadside trees. Each layer is merged into a single
## mesh so a phone only pays a handful of draw calls for the whole town.

const ASPHALT := Color(0.2, 0.2, 0.21)
const DIRT_ROAD := Color(0.6, 0.36, 0.24)  # many residential streets are red-soil gravel
const GRASS := Color(0.42, 0.4, 0.24)  # dry-season grass and soil
const ROOFS := [Color(0.55, 0.56, 0.58), Color(0.5, 0.22, 0.16), Color(0.62, 0.6, 0.55), Color(0.3, 0.35, 0.4)]
const CANOPY_GREEN := Color(0.22, 0.42, 0.16)
const CANOPY_JACARANDA := Color(0.55, 0.42, 0.8)  # Kitwe's purple jacarandas
const MAIN_ROADS := ["trunk", "primary", "secondary", "tertiary", "trunk_link", "primary_link", "secondary_link", "tertiary_link"]

## For the minimap: [{pts: PackedVector2Array, width: float, main: bool, bounds: Rect2}]
var roads_2d: Array[Dictionary] = []


func build(route: RouteManager) -> void:
	var data = JSON.parse_string(FileAccess.get_file_as_string(route.route.map_data))
	if not (data is Dictionary):
		push_error("Could not read map data %s" % route.route.map_data)
		super.build(route)
		return
	_build_environment()
	_build_roads(data["roads"], route)
	_build_buildings(data["buildings"])
	_build_trees(data["trees"])


func _build_roads(roads: Array, route: RouteManager) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var bounds := Rect2()
	for road in roads:
		var pts := PackedVector2Array()
		for p in road["pts"]:
			pts.append(Vector2(p[0], p[1]))
		var main: bool = road["class"] in MAIN_ROADS
		var width: float = road["width"]
		_add_ribbon(st, pts, width * 0.5, 0.03 if main else 0.02, ASPHALT if main else DIRT_ROAD)
		var rect := Rect2(pts[0], Vector2.ZERO)
		for p in pts:
			rect = rect.expand(p)
		bounds = rect if bounds.size == Vector2.ZERO else bounds.merge(rect)
		roads_2d.append({"pts": pts, "width": width, "main": main, "bounds": rect})

	# The route itself: always wide enough for a lane each way, with a dashed centre line.
	var route_pts := PackedVector2Array()
	for p in route.route.path_points:
		route_pts.append(Vector2(p.x, p.z))
	route_pts.append(route_pts[0])
	_add_ribbon(st, route_pts, route.route.road_width * 0.5, 0.04, ASPHALT)
	var dash := 0.0
	while dash < route.length:
		var a := route.point_at(dash)
		var b := route.point_at(dash + 3.0)
		_add_ribbon(st, PackedVector2Array([Vector2(a.x, a.z), Vector2(b.x, b.z)]), 0.1, 0.05, Color(0.9, 0.9, 0.85), false)
		dash += 9.0

	road_material = _add_mesh(st, "Roads").mesh.surface_get_material(0) as StandardMaterial3D
	bounds = bounds.grow(400.0)
	var ground := Graybox.solid_box(self, Vector3(bounds.size.x, 1, bounds.size.y),
			Vector3(bounds.get_center().x, -0.5, bounds.get_center().y), GRASS)
	ground.name = "Ground"


## Flat strip along a polyline: a quad per segment plus a disc at each joint
## so corners never show gaps. Vertex colours keep everything in one mesh.
func _add_ribbon(st: SurfaceTool, pts: PackedVector2Array, half: float, y: float, color: Color, joints := true) -> void:
	st.set_color(color)
	st.set_normal(Vector3.UP)
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		if a.is_equal_approx(b):
			continue
		var n := (b - a).normalized().orthogonal() * half
		_tri(st, a + n, b + n, b - n, y)
		_tri(st, a + n, b - n, a - n, y)
	if joints:
		for i in range(1, pts.size() - 1):
			for k in 8:
				var a0 := TAU * k / 8.0
				var a1 := TAU * (k + 1) / 8.0
				_tri(st, pts[i], pts[i] + Vector2(cos(a0), sin(a0)) * half, pts[i] + Vector2(cos(a1), sin(a1)) * half, y)


func _tri(st: SurfaceTool, a: Vector2, b: Vector2, c: Vector2, y: float) -> void:
	st.add_vertex(Vector3(a.x, y, a.y))
	st.add_vertex(Vector3(b.x, y, b.y))
	st.add_vertex(Vector3(c.x, y, c.y))


func _build_buildings(buildings: Array) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var faces := PackedVector3Array()
	for b in buildings:
		var poly := PackedVector2Array()
		for p in b["pts"]:
			poly.append(Vector2(p[0], p[1]))
		if Geometry2D.is_polygon_clockwise(poly):
			poly.reverse()
		var h: float = b["h"]
		var c: int = b["c"]
		st.set_color(WALLS[c % WALLS.size()])
		for i in poly.size():
			var a := poly[i]
			var d := poly[(i + 1) % poly.size()]
			var edge := d - a
			st.set_normal(Vector3(edge.y, 0, -edge.x).normalized())
			var quad := [Vector3(a.x, 0, a.y), Vector3(d.x, 0, d.y), Vector3(d.x, h, d.y), Vector3(a.x, h, a.y)]
			for idx in [0, 1, 2, 0, 2, 3]:
				st.add_vertex(quad[idx])
				faces.append(quad[idx])
		var tris := Geometry2D.triangulate_polygon(poly)
		st.set_color(ROOFS[c % ROOFS.size()])
		st.set_normal(Vector3.UP)
		for idx in tris:
			st.add_vertex(Vector3(poly[idx].x, h, poly[idx].y))
	var mesh_instance := _add_mesh(st, "Buildings")

	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	shape.backface_collision = true
	var body := StaticBody3D.new()
	body.name = "BuildingCollision"
	var col := CollisionShape3D.new()
	col.shape = shape
	body.add_child(col)
	mesh_instance.add_child(body)


func _build_trees(trees: Array) -> void:
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.18
	trunk.bottom_radius = 0.28
	trunk.height = 3.0
	trunk.radial_segments = 6
	trunk.rings = 1
	trunk.material = Graybox.mat(Color(0.32, 0.22, 0.15))
	var canopy := SphereMesh.new()
	canopy.radius = 3.2
	canopy.height = 4.0
	canopy.radial_segments = 8
	canopy.rings = 4
	var leaf := StandardMaterial3D.new()
	leaf.vertex_color_use_as_albedo = true
	leaf.vertex_color_is_srgb = true
	canopy.material = leaf

	var trunks := _multimesh("Trunks", trunk, trees.size(), false)
	var canopies := _multimesh("Canopies", canopy, trees.size(), true)
	for i in trees.size():
		var t: Array = trees[i]
		var s: float = t[2]
		var basis := Basis.from_scale(Vector3.ONE * s)
		trunks.set_instance_transform(i, Transform3D(basis, Vector3(t[0], 1.5 * s, t[1])))
		canopies.set_instance_transform(i, Transform3D(basis, Vector3(t[0], 4.2 * s, t[1])))
		canopies.set_instance_color(i, CANOPY_JACARANDA if i % 4 == 0 else CANOPY_GREEN.lightened(0.15 * fmod(i * 0.37, 1.0)))


func _multimesh(node_name: String, mesh: Mesh, count: int, colors: bool) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = colors
	mm.mesh = mesh
	mm.instance_count = count
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	add_child(mmi)
	return mm


func _add_mesh(st: SurfaceTool, node_name: String) -> MeshInstance3D:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true  # colours are authored like Graybox's albedo colours
	mat.roughness = 0.9
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	st.set_material(mat)
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = st.commit()
	add_child(mi)
	return mi
