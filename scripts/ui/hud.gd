class_name Hud
extends CanvasLayer
## Race HUD: earnings, seats, speed, fuel, clock, next stop, police warnings,
## standings, minimap, call-boy barks and the results screen.

signal drive_again_pressed
signal menu_pressed

const BARK_SECONDS := 3.0
const MINIMAP_SIZE := 230.0
const WARN := Color(1.0, 0.45, 0.3)

var minimap: Minimap
var route: RouteManager

var _stats: Label
var _alerts: Label
var _standings: Label
var _bark: Label
var _results: Label
var _buttons: HBoxContainer
var _bark_time := 0.0


func _ready() -> void:
	minimap = Minimap.new()
	add_child(minimap)
	minimap.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	minimap.offset_left = -MINIMAP_SIZE - 20.0
	minimap.offset_right = -20.0
	minimap.offset_top = 20.0
	minimap.offset_bottom = MINIMAP_SIZE + 20.0

	_stats = _label(26, HORIZONTAL_ALIGNMENT_LEFT, VERTICAL_ALIGNMENT_TOP)
	_alerts = _label(24, HORIZONTAL_ALIGNMENT_CENTER, VERTICAL_ALIGNMENT_TOP)
	_alerts.add_theme_color_override("font_color", WARN)
	_standings = _label(22, HORIZONTAL_ALIGNMENT_RIGHT, VERTICAL_ALIGNMENT_TOP)
	_standings.offset_top = MINIMAP_SIZE + 30.0
	_bark = _label(32, HORIZONTAL_ALIGNMENT_CENTER, VERTICAL_ALIGNMENT_BOTTOM)
	_bark.offset_bottom = -80.0
	_results = _label(34, HORIZONTAL_ALIGNMENT_CENTER, VERTICAL_ALIGNMENT_CENTER)
	_results.visible = false

	_buttons = HBoxContainer.new()
	_buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	_buttons.add_theme_constant_override("separation", 24)
	add_child(_buttons)
	_buttons.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_buttons.offset_top = -110.0
	_buttons.offset_bottom = -40.0
	_buttons.offset_left = -300.0
	_buttons.offset_right = 300.0
	for spec in [["Drive again", drive_again_pressed], ["Main menu", menu_pressed]]:
		var button := Button.new()
		button.text = spec[0]
		button.custom_minimum_size = Vector2(240, 64)
		button.add_theme_font_size_override("font_size", 28)
		button.pressed.connect((spec[1] as Signal).emit)
		_buttons.add_child(button)
	_buttons.visible = false

	EventBus.bark.connect(show_bark)
	EventBus.fined.connect(_on_fined)


func _process(delta: float) -> void:
	if _bark_time > 0.0:
		_bark_time -= delta
		_bark.modulate.a = clampf(_bark_time, 0.0, 1.0)


func update_stats(player: Minibus, buses: Array[Minibus], time_left: float, next_stop: String, next_dist: float) -> void:
	var secs := int(ceil(time_left))
	var seats := "%d/%d" % [player.passengers.size(), player.def.seats]
	if player.squeeze:
		seats += "  SQUEEZE"
	_stats.text = "K%d\nSeats %s\n%d km/h\nFuel %.1f L\n%d:%02d\nNext: %s (%dm)" % [
		player.earnings, seats,
		int(absf(player.forward_speed()) * 3.6),
		player.fuel_l,
		secs / 60, secs % 60,
		next_stop, int(maxf(next_dist, 0.0)),
	]

	var alerts := PackedStringArray()
	if route:
		var cp := route.next_checkpoint(player.route_progress)
		if cp and not cp.is_cleared(player):
			var d := route.signed_distance(player.route_progress, cp.route_offset, PoliceCheckpoint.ZONE_AFTER)
			if d < 300.0:
				alerts.append("POLICE CHECKPOINT %dm  -  limit %d km/h, stop for inspection" % [int(maxf(d, 0.0)), cp.speed_limit_kmh])
		if player.fuel_l < 1.5:
			var station := route.next_fuel_station(player.route_progress)
			var where := " - filling station in %dm" % int(route.signed_distance(player.route_progress, station.route_offset)) if station else ""
			alerts.append("LOW FUEL" + where)
	_alerts.text = "\n".join(alerts)

	var sorted := buses.duplicate()
	sorted.sort_custom(func(a: Minibus, b: Minibus) -> bool: return a.earnings > b.earnings)
	var lines := PackedStringArray()
	for i in sorted.size():
		lines.append("%d. %s  K%d" % [i + 1, sorted[i].driver_name, sorted[i].earnings])
	_standings.text = "\n".join(lines)


func show_bark(text: String) -> void:
	_bark.text = text
	_bark_time = BARK_SECONDS
	_bark.modulate.a = 1.0


func _on_fined(bus: Node, amount: int, reason: String) -> void:
	var who := "You" if (bus as Minibus).is_player else (bus as Minibus).driver_name
	show_bark("%s: fined K%d. %s" % [who, amount, reason])


## Small credit line, e.g. the OpenStreetMap attribution the ODbL licence requires.
func set_credit(text: String) -> void:
	var credit := _label(14, HORIZONTAL_ALIGNMENT_RIGHT, VERTICAL_ALIGNMENT_BOTTOM)
	credit.text = text
	credit.offset_right = -8.0
	credit.offset_bottom = -4.0
	credit.modulate.a = 0.7


func show_results(player: Minibus, rivals: Array[Minibus], total_saved: int) -> void:
	var lines := PackedStringArray(["TIME UP!", ""])
	lines.append("Fares K%d   Fines -K%d   Fuel -K%d" % [player.fares, player.fines, player.fuel_spent])
	lines.append("You took home K%d" % player.earnings)
	var best: Minibus = player
	for rival in rivals:
		lines.append("%s: K%d" % [rival.driver_name, rival.earnings])
		if rival.earnings > best.earnings:
			best = rival
	lines.append("")
	lines.append("You win the route!" if best == player else "%s wins this time." % best.driver_name)
	lines.append("In the bank: K%d" % total_saved)
	_results.text = "\n".join(lines)
	_results.offset_bottom = -120.0
	_results.visible = true
	_buttons.visible = true
	_bark.visible = false
	_alerts.visible = false
	(_buttons.get_child(0) as Button).grab_focus()


func _label(font_size: int, h: HorizontalAlignment, v: VerticalAlignment) -> Label:
	var label := Label.new()
	add_child(label)
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 24)
	label.horizontal_alignment = h
	label.vertical_alignment = v
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_constant_override("outline_size", 8)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	return label
