class_name Combat
extends RefCounted
## The one hitscan both combat modes fire through: the Freedom Duel (two finalists) and
## Battle Mode (any number). It only answers "where does this shot stop, and did it stop on a
## racer" -- who may be hurt, and for how much, is each mode's rule.


## {to: Vector3, body: PlayerController or null}. Walls and racers block; the shooter never.
static func hitscan(shooter: PlayerController, from: Vector3, dir: Vector3, reach: float = AppConfig.PULSE_RANGE) -> Dictionary:
	var to := from + dir.normalized() * reach
	var space := shooter.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to, CaveBuilder.LAYER_WORLD | CaveBuilder.LAYER_RACERS, [shooter.get_rid()])
	var result := space.intersect_ray(query)
	if result.is_empty():
		return {"to": to, "body": null}
	return {"to": result["position"], "body": result["collider"] as PlayerController}
