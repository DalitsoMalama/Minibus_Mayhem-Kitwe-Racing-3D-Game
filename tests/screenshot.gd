extends SceneTree
## Renders the race for a few seconds (throttle held) and saves screenshots.
##   godot --path . --script res://tests/screenshot.gd -- --out=C:/tmp/shot --seconds=6 [--route=...] [--rain]

var _out := "user://shot"
var _frames := 60 * 6
var _frame := 0
var _session: Node


func _initialize() -> void:
	root.get_node("GameState").persist = false
	var session: Node = load("res://scenes/race/race_session.tscn").instantiate()
	session.weather = load("res://data/weather/dry.tres")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--route="):
			session.route = load(arg.trim_prefix("--route="))
		elif arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
		elif arg.begins_with("--seconds="):
			_frames = 60 * int(arg.trim_prefix("--seconds="))
		elif arg == "--rain":
			session.weather = load("res://data/weather/rainy.tres")
	root.add_child(session)
	current_scene = session
	_session = session


func _process(_delta: float) -> bool:
	Input.action_press(&"accelerate")
	_frame += 1
	if _frame == _frames / 2 or _frame == _frames:
		var img := root.get_texture().get_image()
		var path := "%s_%d.png" % [_out, 1 if _frame < _frames else 2]
		img.save_png(path)
		print("saved ", path)
	if _frame >= _frames:
		quit()
		return true
	return false
