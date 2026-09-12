class_name Prototype3DHUD
extends CanvasLayer

signal pause_requested
signal restart_requested
signal menu_requested
signal cycle_requested(player_id: int)

var status: Label
var overlay: Control

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	status = UIFactory.make_label("", 18)
	status.position = Vector2(24, 16)
	root.add_child(status)
	var hint := UIFactory.make_label("GREEN: hold nearby to collect. RED: damage.\n1 DOF: fast harvest | 2 DOF: any facing | 3 DOF: aim orange nose for 20 points\nP1 A/D W/S Q/E | P2 arrows ,/. | Esc: pause / cycle DOF", 16)
	hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	hint.position = Vector2(24, -86)
	root.add_child(hint)

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		pause_requested.emit()

func show_pause() -> void:
	close_overlay()
	var menu := preload("res://scenes/ui/pause_menu.tscn").instantiate() as PauseMenu
	menu.resume_requested.connect(pause_requested.emit)
	menu.restart_requested.connect(restart_requested.emit)
	menu.menu_requested.connect(menu_requested.emit)
	menu.cycle_requested.connect(cycle_requested.emit)
	add_child(menu)
	overlay = menu
	(menu.find_children("*", "Button", true, false)[0] as Button).grab_focus()

func close_overlay() -> void:
	if is_instance_valid(overlay):
		remove_child(overlay)
		overlay.queue_free()
		overlay = null

func show_result(reason: String, score: int) -> void:
	close_overlay()
	var menu := MenuBase.new()
	add_child(menu)
	overlay = menu
	menu.add_header("3D GREYBOX / SESSION ONLY", reason, "Team score: %d. Experimental scores do not change 2D records or unlocks." % score)
	menu.add_button("RESTART 3D", restart_requested.emit, true).grab_focus()
	menu.add_button("RETURN TO MENU", menu_requested.emit)
