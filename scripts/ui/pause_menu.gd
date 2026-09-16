class_name PauseMenu
extends CanvasLayer
## Esc during a race. Offline it pauses the tree, frees the mouse, and offers settings in
## place so adjusting sensitivity never costs the race.
##
## Online the race belongs to the server and cannot be paused: the menu opens over a race
## that keeps running, your racer stands still while it is open, and "Restart" becomes
## "Leave race".

signal restart_requested()
signal leave_requested()
signal open_changed(open: bool)

## Set before adding to the tree.
var online: bool = false

var _root: Control
var _main: VBoxContainer
var _settings: VBoxContainer


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.theme = UiKit.theme()
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45 if online else 0.65)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)

	_main = UiKit.centre_column(_root, 12)
	_main.add_child(UiKit.title("Paused" if not online else "Menu", 64))
	if online:
		_main.add_child(UiKit.title("The race is still running", 20, UiKit.DANGER))
	_main.add_child(UiKit.button("Resume", close))
	_main.add_child(UiKit.button("Settings", func() -> void: _show_settings(true)))
	_main.add_child(UiKit.button("Controls", func() -> void: _show_controls(true)))
	if online:
		_main.add_child(UiKit.button("Leave race", func() -> void:
			close()
			leave_requested.emit()))
	else:
		_main.add_child(UiKit.button("Restart (same cave)", func() -> void:
			close()
			restart_requested.emit()))
		_main.add_child(UiKit.button("Quit to Menu", func() -> void: SceneRouter.go_to(SceneRouter.MAIN_MENU)))

	_settings = UiKit.centre_column(_root, 16)
	_settings.add_child(UiKit.title("Settings", 52))
	var panel := PanelContainer.new()
	panel.add_child(UiKit.settings_panel())
	_settings.add_child(panel)
	var back := UiKit.button("Back", func() -> void: _show_settings(false))
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_settings.add_child(back)

	_controls = UiKit.centre_column(_root, 12)
	_controls.add_child(UiKit.title("Controls", 52))
	var controls_panel := PanelContainer.new()
	controls_panel.add_child(UiKit.controls_table())
	_controls.add_child(controls_panel)
	var controls_back := UiKit.button("Back", func() -> void: _show_controls(false))
	controls_back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_controls.add_child(controls_back)
	_root.visible = false


var _controls: VBoxContainer


func open() -> void:
	if _root.visible:
		return
	_root.visible = true
	_show_settings(false)
	if not online:
		get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_first_button().grab_focus()
	open_changed.emit(true)


func close() -> void:
	if not _root.visible:
		return
	_root.visible = false
	if not online:
		get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	open_changed.emit(false)


func is_open() -> bool:
	return _root.visible


func _first_button() -> Button:
	for child in _main.get_children():
		if child is Button:
			return child
	return null


func _show_settings(on: bool) -> void:
	_main.get_parent().visible = not on
	_controls.get_parent().visible = false
	_settings.get_parent().visible = on


func _show_controls(on: bool) -> void:
	_main.get_parent().visible = not on
	_settings.get_parent().visible = false
	_controls.get_parent().visible = on


func _unhandled_input(event: InputEvent) -> void:
	if _root.visible and event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		if _settings.get_parent().visible:
			_show_settings(false)
		elif _controls.get_parent().visible:
			_show_controls(false)
		else:
			close()
