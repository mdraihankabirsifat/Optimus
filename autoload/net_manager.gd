extends Node
## Tier 3 networking. Deliberately a no-op stub.
##
## Offline Bot Race is the judging fallback and must never call into this file. If a
## future change makes offline play depend on anything here, the change is wrong.
## See docs/MVP_SCOPE.md, "HARD ABORT GATE".


func is_online() -> bool:
	return false


func is_available() -> bool:
	return AppConfig.NETWORKING_ENABLED
