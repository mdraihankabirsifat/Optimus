extends Node

signal player_connected(peer_id: int)
signal player_disconnected(peer_id: int)
signal connection_failed(reason: String)

const PHASE_ONE_MESSAGE: String = "Hosted networking is not implemented in Phase 1."

func connect_to_server(_server_url: String) -> bool:
	connection_failed.emit(PHASE_ONE_MESSAGE)
	return false

func disconnect_from_server() -> void:
	pass

func create_or_join_room(_room_code: String) -> bool:
	connection_failed.emit(PHASE_ONE_MESSAGE)
	return false
