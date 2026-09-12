class_name PauseMenu
extends Control

signal resume_requested
signal restart_requested
signal menu_requested
signal cycle_requested(player_id: int)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade := ColorRect.new()
	shade.color = Color(0.01, 0.03, 0.07, 0.88)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UIFactory.panel_style())
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	var title := UIFactory.make_label("SYSTEM PAUSED", 34)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	_add_button(box, "RESUME", resume_requested.emit, true)
	_add_button(box, "CYCLE PLAYER 1 DOF", cycle_requested.emit.bind(1))
	_add_button(box, "CYCLE PLAYER 2 DOF", cycle_requested.emit.bind(2))
	_add_button(box, "RESTART ARENA", restart_requested.emit)
	_add_button(box, "RETURN TO MENU", menu_requested.emit)

func _add_button(parent: VBoxContainer, text_value: String, callback: Callable, primary: bool = false) -> void:
	var button := Button.new()
	button.text = text_value
	UIFactory.setup_button(button, primary)
	button.pressed.connect(callback)
	parent.add_child(button)
