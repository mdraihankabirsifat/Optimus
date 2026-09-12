class_name EnergyNode
extends Area2D

signal collected(player_id: int)

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	var tween := create_tween().set_loops()
	tween.tween_property(self, "rotation", TAU, 2.8).from(0.0)

func _on_body_entered(body: Node2D) -> void:
	if body is DOFPlayer:
		monitoring = false
		collected.emit((body as DOFPlayer).player_id)
		queue_free()

func _draw() -> void:
	var points := PackedVector2Array([Vector2(0, -16), Vector2(14, -8), Vector2(14, 8), Vector2(0, 16), Vector2(-14, 8), Vector2(-14, -8)])
	draw_colored_polygon(points, Color("36e6a2"))
	draw_polyline(points + PackedVector2Array([points[0]]), Color.WHITE, 2.0)
	draw_circle(Vector2.ZERO, 5.0, Color.WHITE)
