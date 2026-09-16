class_name PauseMenu
extends CanvasLayer
## Esc during a race. Pauses the tree, frees the mouse, and offers settings in place so
## adjusting sensitivity never costs the race.

signal restart_requested()

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
	dim.color = Color(0, 0, 0, 0.65)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)

	_main = UiKit.centre_column(_root, 12)
	_main.add_child(UiKit.title("Paused", 64))
	_main.add_child(UiKit.button("Resume", close))
	_main.add_child(UiKit.button("Settings", func() -> void: _show_settings(true)))
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
	_root.visible = false


func open() -> void:
	if _root.visible:
		return
	_root.visible = true
	_show_settings(false)
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	(_main.get_child(1) as Button).grab_focus()


func close() -> void:
	if not _root.visible:
		return
	_root.visible = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func is_open() -> bool:
	return _root.visible


func _show_settings(on: bool) -> void:
	_main.get_parent().visible = not on
	_settings.get_parent().visible = on


func _unhandled_input(event: InputEvent) -> void:
	if _root.visible and event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		if _settings.get_parent().visible:
			_show_settings(false)
		else:
			close()
