class_name DOFPlayer3D
extends CharacterBody3D

signal health_changed(player_id: int, health: int)

@export_range(1, 3) var dof: int = 1:
	set(value):
		dof = clampi(value, 1, 3)
@export var player_id: int = 1
@export var move_speed: float = 5.0
@export var rotation_speed: float = 2.8
@export var player_color: Color = Color("27d9ff")
var health: int = 100
var input_enabled: bool = true
var damage_cooldown: float = 0.0
var label: Label3D

func _ready() -> void:
	GreyboxGeometry.box(self, Vector3(0, 0.5, 0), Vector3(0.8, 0.6, 0.8), player_color)
	GreyboxGeometry.box(self, Vector3(0, 0.9, 0), Vector3(0.5, 0.3, 0.5), Color("eaf4ff"))
	GreyboxGeometry.box(self, Vector3(0, 1.13, -0.35), Vector3(0.18, 0.18, 0.9), Color("ff9b42"))
	for x: float in [-0.5, 0.5]:
		GreyboxGeometry.box(self, Vector3(x, 0.25, 0), Vector3(0.18, 0.3, 0.85), Color("263449"))
	label = Label3D.new()
	label.position.y = 1.7
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 40
	label.pixel_size = 0.014
	add_child(label)

func _physics_process(delta: float) -> void:
	damage_cooldown = maxf(0.0, damage_cooldown - delta)
	label.text = "P%d / %d DOF" % [player_id, dof]
	var prefix := "p%d_" % player_id
	var movement := Input.get_vector(prefix + "left", prefix + "right", prefix + "up", prefix + "down")
	var turn := Input.get_axis(prefix + "rotate_left", prefix + "rotate_right")
	apply_motion(movement, turn, delta)

func apply_motion(movement: Vector2, turn: float, delta: float) -> void:
	velocity = Vector3.ZERO
	if not input_enabled or health <= 0:
		return
	# All commands, including injected test input, pass through the same constraint.
	if dof == 1:
		movement.y = 0.0
	movement = movement.limit_length(1.0)
	velocity = Vector3(movement.x, 0, movement.y) * move_speed
	var ground_height := global_position.y
	var locked_z := global_position.z
	move_and_slide()
	# Collision sliding must not introduce a forbidden ground axis or elevation.
	global_position.y = ground_height
	if dof == 1:
		global_position.z = locked_z
		velocity.z = 0.0
	rotation.x = 0.0
	rotation.z = 0.0
	if dof == 3:
		rotation.y += clampf(turn, -1.0, 1.0) * rotation_speed * delta

func cycle_dof() -> void:
	dof = dof % 3 + 1

func take_damage(amount: int) -> void:
	if damage_cooldown > 0.0 or health <= 0 or not input_enabled:
		return
	damage_cooldown = 0.7
	health = maxi(0, health - maxi(0, amount))
	health_changed.emit(player_id, health)
