class_name PlayerInteraction
extends Node
## The E key. Casts from the camera, finds an interactable, shows a prompt, and calls
## `interact(racer)` on it. Decides nothing about what a box contains.

signal target_changed(prompt: String)

const LAYER_INTERACTABLE := 4

var current_target: Node = null

var _player: PlayerController
var _ray: RayCast3D
var _last_prompt: String = ""


func _ready() -> void:
	_player = get_parent() as PlayerController
	set_physics_process(false)
	# Wait for the whole racer: a BotController clears is_local_player in its own _ready.
	if not _player.is_node_ready():
		await _player.ready
	_ray = _player.get_node("Head/Camera3D/InteractRay") as RayCast3D
	_ray.target_position = Vector3(0.0, 0.0, -AppConfig.INTERACT_RANGE)
	# Cave walls are in the mask so they block the ray: no opening boxes through rock.
	_ray.collision_mask = LAYER_INTERACTABLE | CaveBuilder.LAYER_WORLD
	_ray.collide_with_areas = true
	_ray.collide_with_bodies = true
	set_physics_process(_player.is_local_player)


func _physics_process(_delta: float) -> void:
	var target: Node = null
	if _ray.is_colliding():
		var hit := _ray.get_collider()
		if hit != null and hit.has_method("interact") and hit.has_method("prompt_text"):
			target = hit

	current_target = target
	var prompt := ""
	if target != null and _player.input_enabled:
		prompt = target.prompt_text()
	if prompt != _last_prompt:
		_last_prompt = prompt
		target_changed.emit(prompt)

	if target != null and _player.input_enabled and Input.is_action_just_pressed("interact"):
		target.interact(_player)
