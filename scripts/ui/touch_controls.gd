class_name TouchControls
extends CanvasLayer
## On-screen buttons for phones and tablets. They press the same input actions
## as the keyboard/gamepad, and stay hidden on devices without a touchscreen.

# action, label, screen anchor (0..1), offset from anchor (px), radius (px)
const LAYOUT := [
	[&"steer_left", "<", Vector2(0, 1), Vector2(105, -110), 78],
	[&"steer_right", ">", Vector2(0, 1), Vector2(280, -110), 78],
	[&"accelerate", "GO", Vector2(1, 1), Vector2(-110, -125), 90],
	[&"brake_reverse", "BRAKE", Vector2(1, 1), Vector2(-295, -95), 72],
	[&"handbrake", "HB", Vector2(1, 1), Vector2(-250, -255), 48],
	[&"reset_bus", "RESET", Vector2(0, 1), Vector2(190, -275), 44],
	[&"squeeze", "SQZ", Vector2(0, 1), Vector2(80, -275), 44],
]

var _buttons: Array[TouchScreenButton] = []


func _ready() -> void:
	layer = 5
	visible = DisplayServer.is_touchscreen_available()
	for spec in LAYOUT:
		var radius: int = spec[4]
		var button := TouchScreenButton.new()
		button.action = spec[0]
		button.texture_normal = _circle(radius, Color(1, 1, 1, 0.28))
		button.texture_pressed = _circle(radius, Color(1, 0.85, 0.2, 0.55))
		var shape := CircleShape2D.new()
		shape.radius = radius
		button.shape = shape
		button.passby_press = spec[0] in [&"steer_left", &"steer_right", &"accelerate", &"brake_reverse"]
		button.visibility_mode = TouchScreenButton.VISIBILITY_TOUCHSCREEN_ONLY
		button.set_meta("spec", spec)
		var label := Label.new()
		label.text = spec[1]
		label.size = Vector2(radius * 2, radius * 2)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 26 if radius > 60 else 18)
		button.add_child(label)
		add_child(button)
		_buttons.append(button)
	get_viewport().size_changed.connect(_layout)
	_layout()


## Driving buttons disappear on the results screen, which has its own buttons.
func set_race_over(over: bool) -> void:
	for button in _buttons:
		button.visible = not over


func _layout() -> void:
	var screen := get_viewport().get_visible_rect().size
	for button in _buttons:
		var spec: Array = button.get_meta("spec")
		var radius: float = spec[4]
		button.position = screen * (spec[2] as Vector2) + (spec[3] as Vector2) - Vector2(radius, radius)


static func _circle(radius: int, color: Color) -> ImageTexture:
	var diameter := radius * 2
	var img := Image.create_empty(diameter, diameter, false, Image.FORMAT_RGBA8)
	var centre := Vector2(radius, radius)
	for y in diameter:
		for x in diameter:
			var d := Vector2(x + 0.5, y + 0.5).distance_to(centre)
			var edge := clampf(radius - d, 0.0, 1.0)
			var rim := 1.0 if d > radius - 4.0 else 0.55
			img.set_pixel(x, y, Color(color.r, color.g, color.b, color.a * edge * rim))
	return ImageTexture.create_from_image(img)
