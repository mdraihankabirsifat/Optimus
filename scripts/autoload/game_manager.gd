extends Node

const MAIN_MENU: String = "res://scenes/ui/main_menu.tscn"
const DIFFICULTIES: Dictionary = {
	"Easy": {"duration": 90.0, "speed_scale": 0.9, "hazard_damage": 10},
	"Difficult": {"duration": 70.0, "speed_scale": 1.0, "hazard_damage": 16},
	"Hard": {"duration": 55.0, "speed_scale": 1.15, "hazard_damage": 24},
}
const LEVELS: Array[Dictionary] = [
	{"name": "Level 1", "accent": Color("27d9ff"), "hazard_count": 1},
	{"name": "Level 2", "accent": Color("ff9b42"), "hazard_count": 2},
	{"name": "Level 3", "accent": Color("d26bff"), "hazard_count": 3},
]

var selected_difficulty: String = "Easy"
var selected_level: int = 1

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func go_to(path: String) -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file(path)

func difficulty_data() -> Dictionary:
	return DIFFICULTIES.get(selected_difficulty, DIFFICULTIES["Easy"])
