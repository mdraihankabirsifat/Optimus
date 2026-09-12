class_name MenuBase
extends Control

var content: VBoxContainer

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_shell()

func _build_shell() -> void:
	var background := ColorRect.new()
	background.color = UIFactory.BG
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	var glow := Polygon2D.new()
	glow.polygon = PackedVector2Array([Vector2(0, 0), Vector2(460, 0), Vector2(250, 720), Vector2(0, 720)])
	glow.color = Color(0.05, 0.35, 0.5, 0.16)
	add_child(glow)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(520, 0)
	panel.add_theme_stylebox_override("panel", UIFactory.panel_style())
	center.add_child(panel)
	content = VBoxContainer.new()
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_theme_constant_override("separation", 12)
	panel.add_child(content)

func add_header(kicker: String, title: String, subtitle: String = "") -> void:
	var kicker_label := UIFactory.make_label(kicker.to_upper(), 13, UIFactory.CYAN)
	kicker_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(kicker_label)
	var title_label := UIFactory.make_label(title, 42)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(title_label)
	if not subtitle.is_empty():
		var subtitle_label := UIFactory.make_label(subtitle, 16, UIFactory.MUTED)
		subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		subtitle_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		content.add_child(subtitle_label)
	add_spacer(8)

func add_button(text_value: String, callback: Callable, primary: bool = false, disabled: bool = false) -> Button:
	var button := Button.new()
	button.text = text_value
	button.disabled = disabled
	UIFactory.setup_button(button, primary)
	button.pressed.connect(callback)
	content.add_child(button)
	return button

func add_spacer(height: float) -> void:
	var spacer := Control.new()
	spacer.custom_minimum_size.y = height
	content.add_child(spacer)

func go_back(path: String) -> void:
	GameManager.go_to(path)
