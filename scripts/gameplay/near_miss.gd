class_name NearMiss
extends RefCounted
## FEEL-008: a close call deserves a reaction. A whoosh and a small camera kick, rate-limited
## so a racer dancing next to a piston is not spammed.

static var _last_ms: int = -100000


static func trigger(racer: PlayerController) -> void:
	var now := Time.get_ticks_msec()
	if now - _last_ms < 1500 or racer.health.is_invulnerable:
		return
	_last_ms = now
	AudioManager.play_sfx("whoosh", -2.0)
	var cam := racer.camera as CameraController
	if cam != null:
		cam.add_shake(0.15)
