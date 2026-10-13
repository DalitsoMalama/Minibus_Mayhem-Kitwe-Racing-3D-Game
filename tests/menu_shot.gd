extends SceneTree
## Renders each main-menu page to PNG.  godot --path . --script res://tests/menu_shot.gd -- --out=C:/tmp/menu
var _out := "user://menu"
var _menu: Control
var _frame := 0

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
	_menu = load("res://scenes/shell/main_menu.tscn").instantiate()
	root.add_child(_menu)

func _process(_delta: float) -> bool:
	_frame += 1
	var pages := {10: "home", 30: "routes", 50: "garage"}
	if _frame in [5, 25, 45]:
		if _frame == 25: _menu._show_routes()
		if _frame == 45: _menu._show_garage()
	if pages.has(_frame):
		root.get_texture().get_image().save_png("%s_%s.png" % [_out, pages[_frame]])
	if _frame > 55:
		quit()
		return true
	return false
