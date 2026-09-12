class_name DOFPlayer
extends CharacterBody2D

signal health_changed(player_id: int, health: int)

@export_range(1, 3, 1) var dof: int = 1:
	set(value):
		dof = clampi(value, 1, 3)
		queue_redraw()
@export var player_id: int = 1
@export var move_speed: float = 260.0
@export var rotation_speed: float = 2.8
@export var player_color: Color = Color("2ad9ff")
@export var movement_bounds: Rect2 = Rect2(55, 145, 1170, 520)

var health: int = 100
var input_enabled: bool = true
var _last_damage_ms: int = -1000

func _ready() -> void:
	queue_redraw()

func _physics_process(delta: float) -> void:
	if not input_enabled:
		velocity = Vector2.ZERO
		return
	var prefix := "p%d_" % player_id
	var horizontal := Input.get_axis(prefix + "left", prefix + "right")
	var vertical := Input.get_axis(prefix + "up", prefix + "down") if dof >= 2 else 0.0
	velocity = Vector2(horizontal, vertical).normalized() * move_speed
	move_and_slide()
	global_position.x = clampf(global_position.x, movement_bounds.position.x, movement_bounds.end.x)
	global_position.y = clampf(global_position.y, movement_bounds.position.y, movement_bounds.end.y)
	if dof >= 3:
		var turn := Input.get_axis(prefix + "rotate_left", prefix + "rotate_right")
		rotation += turn * rotation_speed * delta

func cycle_dof() -> void:
	dof = dof % 3 + 1

func take_damage(amount: int) -> void:
	var now := Time.get_ticks_msec()
	if now - _last_damage_ms < 700 or health <= 0:
		return
	_last_damage_ms = now
	health = maxi(0, health - amount)
	health_changed.emit(player_id, health)
	var tween := create_tween()
	tween.tween_property(self, "modulate", UIFactory.RED, 0.08)
	tween.tween_property(self, "modulate", Color.WHITE, 0.18)

func _draw() -> void:
	draw_circle(Vector2.ZERO, 25.0, Color(player_color, 0.2))
	draw_arc(Vector2.ZERO, 24.0, 0.0, TAU, 32, player_color, 3.0)
	draw_rect(Rect2(-15, -15, 30, 30), Color("13263d"), true)
	draw_rect(Rect2(-15, -15, 30, 30), player_color, false, 2.0)
	draw_line(Vector2.ZERO, Vector2(22, 0), UIFactory.ORANGE if dof == 3 else player_color, 4.0)
	for index: int in dof:
		draw_circle(Vector2(-8 + index * 8, 10), 2.5, player_color)
