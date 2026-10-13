extends Control
## Main menu: home, route + season select, and the garage. Built in code so
## it stays easy to restyle; big buttons so it works on a phone.

const RACE_SCENE := "res://scenes/race/race_session.tscn"
const BG := Color(0.09, 0.09, 0.11)
const COPPER := Color(0.85, 0.45, 0.2)

var _page: Control


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = BG
	add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_show_home()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"menu") and not (_page and _page.name == "Home"):
		_show_home()


func _new_page(page_name: String, title: String) -> VBoxContainer:
	if _page:
		_page.queue_free()
	var scroll := ScrollContainer.new()
	scroll.name = page_name
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 32)
	_page = scroll
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 14)
	scroll.add_child(box)
	var heading := _text(title, 44, COPPER)
	box.add_child(heading)
	box.add_child(_text("In the bank: K%d" % GameState.total_kwacha, 24, Color(0.9, 0.9, 0.85)))
	return box


func _show_home() -> void:
	var box := _new_page("Home", "MINIBUS MAYHEM: KITWE")
	box.add_child(_text("Race rival minibuses around the Copperbelt. Pick up passengers, dodge the police, earn kwacha.", 20, Color(0.75, 0.75, 0.75)))
	if GameState.races_played > 0:
		box.add_child(_text("Races: %d   Best take-home: K%d" % [GameState.races_played, GameState.best_run], 20, Color(0.75, 0.75, 0.75)))
	box.add_child(_spacer(20))
	_button(box, "Drive", _show_routes).grab_focus()
	_button(box, "Garage", _show_garage)
	_button(box, "Quit", get_tree().quit)
	box.add_child(_spacer(20))
	box.add_child(_text("Map data © OpenStreetMap contributors", 14, Color(0.5, 0.5, 0.5)))


func _show_routes() -> void:
	var box := _new_page("Routes", "CHOOSE A ROUTE")
	var routes := GameState.ROUTES.filter(func(path: String) -> bool: return ResourceLoader.exists(path))
	if GameState.selected_route not in routes and not routes.is_empty():
		GameState.selected_route = routes[0]
	for path in routes:
		var route: RouteDef = load(path)
		var km := _route_length(route) / 1000.0
		var label := "%s   (%.1f km, %d stops, %d police, %d fuel)\n%s" % [
			route.route_name, km, route.stop_names.size(), route.checkpoint_offsets.size(),
			route.fuel_offsets.size(), route.description]
		var button := _button(box, label, func() -> void:
			GameState.selected_route = path
			_show_routes())
		button.custom_minimum_size.y = 84
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		if path == GameState.selected_route:
			button.modulate = COPPER.lightened(0.3)
			button.grab_focus.call_deferred()

	box.add_child(_text("Season", 28, COPPER))
	var seasons := HBoxContainer.new()
	seasons.add_theme_constant_override("separation", 16)
	box.add_child(seasons)
	for i in GameState.WEATHERS.size():
		var weather: WeatherDef = load(GameState.WEATHERS[i])
		var button := _button(seasons, weather.display_name, func() -> void:
			GameState.selected_weather = i
			_show_routes())
		button.tooltip_text = weather.description
		if i == GameState.selected_weather:
			button.modulate = COPPER.lightened(0.3)
	box.add_child(_text(GameState.weather().description, 18, Color(0.75, 0.75, 0.75)))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	box.add_child(row)
	_button(row, "Start driving", _start_race)
	_button(row, "Back", _show_home)


func _show_garage() -> void:
	var box := _new_page("Garage", "GARAGE")
	box.add_child(_text("Spend your savings on the bus. Upgrades last forever.", 20, Color(0.75, 0.75, 0.75)))
	for path in GameState.UPGRADES:
		var upgrade: UpgradeDef = load(path)
		var level := GameState.upgrade_level(upgrade.id)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 16)
		box.add_child(row)
		var info := _text("%s  [%d/%d]\n%s" % [upgrade.display_name, level, upgrade.max_level(), upgrade.description], 20, Color(0.92, 0.92, 0.9))
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(info)
		var maxed := level >= upgrade.max_level()
		var price := 0 if maxed else upgrade.prices[level]
		var buy := _button(row, "Maxed" if maxed else "Buy K%d" % price, func() -> void:
			GameState.buy_upgrade(upgrade)
			_show_garage())
		buy.custom_minimum_size.x = 200
		buy.disabled = maxed or GameState.total_kwacha < price

	box.add_child(_text("Paint", 28, COPPER))
	var paints := HBoxContainer.new()
	paints.add_theme_constant_override("separation", 12)
	box.add_child(paints)
	for i in GameState.PAINTS.size():
		var swatch := _button(paints, "  ✓  " if i == GameState.paint else "     ", func() -> void:
			GameState.paint = i
			GameState.save_game()
			_show_garage())
		swatch.custom_minimum_size = Vector2(90, 56)
		swatch.self_modulate = GameState.PAINTS[i]
	_button(box, "Back", _show_home).grab_focus()


func _start_race() -> void:
	GameState.launch_from_menu = true
	GameState.save_game()
	get_tree().change_scene_to_file(RACE_SCENE)


func _route_length(route: RouteDef) -> float:
	var total := 0.0
	var pts := route.path_points
	for i in pts.size():
		total += pts[i].distance_to(pts[(i + 1) % pts.size()])
	return total


func _button(parent: Control, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(320, 60)
	button.add_theme_font_size_override("font_size", 24)
	button.pressed.connect(action)
	parent.add_child(button)
	return button


func _text(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _spacer(height: float) -> Control:
	var spacer := Control.new()
	spacer.custom_minimum_size.y = height
	return spacer
