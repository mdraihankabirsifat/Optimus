class_name ArenaHazard
extends Area2D

@export var damage: int = 15
@export var radius: float = 42.0

func _ready() -> void:
	body_entered.connect(_damage_body)
	body_exited.connect(_stop_damage)
	var timer := Timer.new()
	timer.wait_time = 0.2
	timer.autostart = true
	timer.timeout.connect(_damage_overlapping)
	add_child(timer)
	queue_redraw()

func _damage_body(body: Node2D) -> void:
	if body is DOFPlayer:
		(body as DOFPlayer).take_damage(damage)

func _stop_damage(_body: Node2D) -> void:
	pass

func _damage_overlapping() -> void:
	for body: Node2D in get_overlapping_bodies():
		_damage_body(body)

func _draw() -> void:
	draw_circle(Vector2.ZERO, radius, Color(0.9, 0.12, 0.16, 0.16))
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 36, UIFactory.RED, 3.0)
	for angle: float in [0.0, TAU / 3.0, TAU * 2.0 / 3.0]:
		draw_line(Vector2.ZERO, Vector2.RIGHT.rotated(angle) * radius, UIFactory.RED, 2.0)
