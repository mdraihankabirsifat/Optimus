extends MenuBase

var controls: Dictionary = {}

func _ready() -> void:
	super()
	add_header("System Calibration", "SETTINGS", "Changes are previewed immediately and saved when applied.")
	_add_slider("Master Volume", "master_volume")
	_add_slider("Music Volume", "music_volume")
	_add_slider("SFX Volume", "sfx_volume")
	_add_toggle("Mute Master", "master_muted")
	if not OS.has_feature("web"):
		_add_toggle("Fullscreen", "fullscreen")
	add_spacer(4)
	add_button("APPLY & BACK", _apply_and_back, true)
	add_button("RESET TO DEFAULTS", _reset)
	add_button("BACK WITHOUT SAVING", _cancel)

func _add_slider(label_text: String, key: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	var label := UIFactory.make_label(label_text, 16)
	label.custom_minimum_size.x = 180
	row.add_child(label)
	var slider := HSlider.new()
	slider.custom_minimum_size = Vector2(240, 36)
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.01
	slider.value = float(SettingsManager.values[key])
	slider.value_changed.connect(_preview_value.bind(key))
	row.add_child(slider)
	content.add_child(row)
	controls[key] = slider

func _add_toggle(label_text: String, key: String) -> void:
	var toggle := CheckButton.new()
	toggle.text = label_text
	toggle.button_pressed = bool(SettingsManager.values[key])
	toggle.add_theme_font_size_override("font_size", 16)
	toggle.toggled.connect(_preview_toggle.bind(key))
	content.add_child(toggle)
	controls[key] = toggle

func _preview_value(value: float, key: String) -> void:
	SettingsManager.values[key] = value
	SettingsManager.apply_settings()

func _preview_toggle(value: bool, key: String) -> void:
	SettingsManager.values[key] = value
	SettingsManager.apply_settings()

func _apply_and_back() -> void:
	SettingsManager.save_settings()
	go_back(GameManager.MAIN_MENU)

func _reset() -> void:
	SettingsManager.reset_defaults()
	for key: String in controls:
		var control: Control = controls[key]
		if control is Range:
			(control as Range).value = float(SettingsManager.values[key])
		elif control is BaseButton:
			(control as BaseButton).button_pressed = bool(SettingsManager.values[key])

func _cancel() -> void:
	SettingsManager.load_settings()
	SettingsManager.apply_settings()
	go_back(GameManager.MAIN_MENU)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_cancel()
