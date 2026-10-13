class_name Minimap
extends Control
## Heading-up minimap: nearby streets, the route (gold), stops and buses.
## Draws in world metres through a canvas transform, so it stays cheap.

@export var metres_across := 450.0

var route: RouteManager
var player: Minibus
var buses: Array[Minibus] = []
var roads: Array[Dictionary] = []  ## from OsmWorld.roads_2d (empty in graybox)

var _route_pts := PackedVector2Array()


func setup(route_manager: RouteManager, all_buses: Array[Minibus], player_bus: Minibus, road_list: Array[Dictionary]) -> void:
	route = route_manager
	buses = all_buses
	player = player_bus
	roads = road_list
	var baked := route.curve.get_baked_points()
	for i in range(0, baked.size(), 4):
		_route_pts.append(Vector2(baked[i].x, baked[i].z))
	_route_pts.append(_route_pts[0])
	clip_contents = true


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.05, 0.07, 0.05, 0.8))
	if player == null:
		return
	var centre := size * 0.5
	var zoom := size.x / metres_across
	var here := Vector2(player.global_position.x, player.global_position.z)
	var fwd := player.global_basis.z
	var angle := -PI * 0.5 - atan2(fwd.z, fwd.x)  # rotate so the bus always faces up
	draw_set_transform_matrix(Transform2D(angle, Vector2(zoom, zoom), 0.0, centre) * Transform2D(0.0, -here))

	var view := Rect2(here - Vector2.ONE * metres_across, Vector2.ONE * metres_across * 2.0)
	for road in roads:
		if (road["bounds"] as Rect2).intersects(view):
			draw_polyline(road["pts"], Color(0.45, 0.45, 0.45) if road["main"] else Color(0.35, 0.28, 0.22), road["width"])
	draw_polyline(_route_pts, Color(1.0, 0.78, 0.1), 9.0)
	for stop in route.stops:
		var p := Vector2(stop.global_position.x, stop.global_position.z)
		draw_circle(p, 16.0, Color(0.1, 0.1, 0.1))
		draw_circle(p, 11.0, Color(0.2, 0.85, 0.3) if stop.waiting > 0 else Color(0.5, 0.5, 0.5))
	for bus in buses:
		if bus != player:
			draw_circle(Vector2(bus.global_position.x, bus.global_position.z), 12.0, bus.def.body_color)

	draw_set_transform_matrix(Transform2D.IDENTITY)
	var arrow := PackedVector2Array([centre + Vector2(0, -10), centre + Vector2(7, 8), centre + Vector2(-7, 8)])
	draw_colored_polygon(arrow, Color.WHITE)
	draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, 0.4), false, 2.0)
