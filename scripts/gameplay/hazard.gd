class_name Hazard
extends Area3D
## A volume that hurts racers who stand in it.
##
## Damage is applied on a repeating tick rather than on body_entered, because a racer who
## walks into fire and stays there should keep taking damage. PlayerHealth's per-source
## cooldown is what stops that becoming a per-frame drain, so the rate is honest and
## identical for humans and bots.
##
## Hazards never have solid collision. They threaten a route, they do not close it -- a
## hazard that could seal the only path to the exit would make a cave unwinnable, and the
## generator's solvability guarantee says nothing about damage.

@export var damage: float = 0.5
@export var source: String = "fire"
## Minimum seconds between hits from this hazard type. Also the fairness knob: too short
## and standing in fire is instant death, too long and hazards are scenery.
@export var hit_cooldown: float = 1.2

## Overlap tests are throttled -- checking every physics frame is wasted work when the
## cooldown means most checks cannot do anything anyway.
const CHECK_INTERVAL := 0.2

var _timer: float = 0.0


func _ready() -> void:
	collision_layer = 0
	collision_mask = CaveBuilder.LAYER_RACERS
	monitoring = true


func _physics_process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = CHECK_INTERVAL

	for body: Node3D in get_overlapping_bodies():
		var health: PlayerHealth = body.get("health")
		if health == null or health.is_eliminated:
			continue
		health.apply_damage(damage, source, hit_cooldown)
