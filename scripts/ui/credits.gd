extends Control

func _ready() -> void:
	UiKit.text_page(self, "Credits", "\n".join([
		"[center][font_size=30][color=#ff9e3d]%s[/color][/font_size][/center]" % AppConfig.TEAM_NAME,
		"",
		"[center]Md. Raihan Kabir Sifat[/center]",
		"[center]Estiak Zaman Atul[/center]",
		"[center]Sadman Sakib[/center]",
		"[center]Ashraf Hossain Chowdhury[/center]",
		"",
		"[center][color=#9b928a]Made with Godot Engine 4.7 (MIT licence) -- godotengine.org/license[/color][/center]",
		"[center][color=#9b928a]All geometry, textures, music and sound effects are generated in code at runtime.[/color][/center]",
		"[center][color=#9b928a]No third-party art or audio assets are used.[/color][/center]",
		"[center][color=#9b928a]AI assistance was used during development -- see AI_DISCLOSURE.md.[/color][/center]",
		"",
		"[center]Made for the BUET Robotics Society GameJam 2026[/center]",
		"[center]Theme: Degree of Freedom[/center]",
	]))
