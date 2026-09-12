class_name UIFactory
extends RefCounted

const BG: Color = Color("07101f")
const PANEL: Color = Color("111f35")
const CYAN: Color = Color("2ad9ff")
const ORANGE: Color = Color("ff9b42")
const TEXT: Color = Color("edf7ff")
const MUTED: Color = Color("8ba4bc")
const GREEN: Color = Color("4be08a")
const RED: Color = Color("ff5f69")

static func panel_style(color: Color = PANEL, radius: int = 12, border_color: Color = Color("244666")) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border_color
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 22.0
	style.content_margin_right = 22.0
	style.content_margin_top = 18.0
	style.content_margin_bottom = 18.0
	return style

static func setup_button(button: Button, primary: bool = false) -> void:
	button.custom_minimum_size = Vector2(280, 50)
	button.add_theme_font_size_override("font_size", 18)
	button.add_theme_color_override("font_color", TEXT)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_stylebox_override("normal", panel_style(Color("142640"), 8, Color("315779")))
	button.add_theme_stylebox_override("hover", panel_style(Color("1a3856"), 8, CYAN))
	button.add_theme_stylebox_override("pressed", panel_style(Color("0d7894") if primary else Color("244d6a"), 8, CYAN))
	button.add_theme_stylebox_override("focus", panel_style(Color("173450"), 8, ORANGE))
	button.mouse_entered.connect(_animate_button.bind(button, 1.03))
	button.mouse_exited.connect(_animate_button.bind(button, 1.0))

static func _animate_button(button: Button, target_scale: float) -> void:
	button.pivot_offset = button.size * 0.5
	var tween := button.create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(button, "scale", Vector2.ONE * target_scale, 0.1)

static func make_label(text_value: String, size: int = 18, color: Color = TEXT) -> Label:
	var label := Label.new()
	label.text = text_value
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label
