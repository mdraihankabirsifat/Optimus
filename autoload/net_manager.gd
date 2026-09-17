extends Node
## Online play: the WebSocket connection, rooms, and every remote call.
##
## OFFLINE BOT RACE NEVER CALLS INTO THIS FILE. It is the judging fallback, and it must keep
## working with no server, no network and nothing in here initialised. If a change makes
## offline play depend on NetManager, the change is wrong. See docs/NETWORKING.md.
##
## One script, two roles, same node path (/root/NetManager) on every machine, which is what
## lets Godot's RPCs find their target:
##   server  a headless process (scenes/net/server.tscn). Owns every room, every lobby and
##           every race. Each running race lives in its own SubViewport with its own
##           physics world, so rooms race side by side without touching.
##   client  a player's game. Sends intent (my pose, shift, open this box) and mirrors what
##           the server decides (hearts, Moves, loot, placements, results).
##
## Transport is WebSocketMultiplayerPeer: plain ws:// locally, wss:// behind Render's TLS.
## WebSocket rides on TCP, so every message arrives, in order.

signal state_changed(state: int)
signal lobby_updated(lobby: Dictionary)
signal notice(text: String, is_error: bool)
signal latency_updated(ms: int)

enum State { OFFLINE, CONNECTING, CONNECTED, RECONNECTING, FAILED }
const STATE_NAMES := ["Offline", "Connecting", "Connected", "Reconnecting", "Failed"]

## Bump when any RPC signature changes. Mismatched clients are turned away with a message
## rather than failing in confusing ways mid-race.
const PROTOCOL_VERSION := 1
const HELLO_TIMEOUT := 10.0
const SILENT_TIMEOUT := 20.0
const PING_INTERVAL := 3.0
## A sleeping free-tier Render service can take most of a minute to wake up.
const CONNECT_TIMEOUT := 75.0
const RECONNECT_ATTEMPTS := 3
const RECONNECT_DELAY := 2.0
const MAX_ROOMS := 32
const RESULTS_LINGER := 6.0

var state: int = State.OFFLINE
var is_server: bool = false
## Server: honour the test harness's teleport requests. Never set in a deployed server.
var test_mode: bool = false
var server_url: String = ""
var player_name: String = "Racer"
var local_peer_id: int = 0
## Client: the latest lobby snapshot, or empty when not in a room.
var lobby: Dictionary = {}
var latency_ms: int = -1
var last_error: String = ""

## Client: the race in progress on this machine, if any.
var client_match: NetMatch

# --- Server ---
var _rooms: Dictionary = {}        # code -> LobbyState
var _room_of: Dictionary = {}      # peer id -> code
var _peers: Dictionary = {}        # peer id -> {name, last_seen}
var _pending: Dictionary = {}      # peer id -> connected at (awaiting hello)
var _matches: Dictionary = {}      # code -> {viewport, world, match}
var _matches_root: Node
var _clock: float = 0.0
var _rng := RandomNumberGenerator.new()

# --- Client ---
var _peer: WebSocketMultiplayerPeer
var _connect_started: float = 0.0
var _ping_timer: float = 0.0
var _user_disconnect: bool = false
var _reconnect_left: int = 0
var _reconnect_timer: float = -1.0
var _rejoin_code: String = ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func is_online() -> bool:
	return state == State.CONNECTED


func is_available() -> bool:
	return AppConfig.NETWORKING_ENABLED


func state_name() -> String:
	return STATE_NAMES[state]


## Where to connect unless the player types something else: --server-url=... on the command
## line, then ?server=... in the web page's address, then the last server this player used,
## then the deployed public server, then a server on this machine.
func default_server_url() -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--server-url="):
			return arg.trim_prefix("--server-url=")
	if OS.has_feature("web"):
		var from_page: Variant = JavaScriptBridge.eval(
			"new URLSearchParams(window.location.search).get('server') || ''", true)
		if from_page is String and String(from_page) != "":
			return String(from_page)
	if SettingsManager.server_url != "":
		return SettingsManager.server_url
	if AppConfig.PUBLIC_SERVER_URL != "":
		return AppConfig.PUBLIC_SERVER_URL
	return AppConfig.DEFAULT_SERVER_URL


func in_room() -> bool:
	return not lobby.is_empty()


func is_host() -> bool:
	return in_room() and int(lobby.get("host_id", 0)) == local_peer_id


# ======================================================================================
# Server
# ======================================================================================

func start_server(port: int) -> Error:
	_peer = WebSocketMultiplayerPeer.new()
	var err := _peer.create_server(port)
	if err != OK:
		push_error("Server could not listen on port %d (error %d)" % [port, err])
		return err
	multiplayer.multiplayer_peer = _peer
	is_server = true
	GameState.net_role = "server"
	_matches_root = Node.new()
	_matches_root.name = "Matches"
	add_child(_matches_root)
	print("[server] %s listening on ws://0.0.0.0:%d  (protocol %d, cave generator %d)"
		% [AppConfig.GAME_TITLE, port, PROTOCOL_VERSION, CaveGenerator.VERSION])
	return OK


func room_count() -> int:
	return _rooms.size()


func _process(delta: float) -> void:
	_clock += delta
	if is_server:
		_server_housekeeping()
	elif _peer != null or _reconnect_timer >= 0.0:
		_client_housekeeping(delta)


func _server_housekeeping() -> void:
	for id: int in _pending.keys():
		if _clock - float(_pending[id]) > HELLO_TIMEOUT:
			_pending.erase(id)
			_kick(id)
	for id: int in _peers.keys():
		if _clock - float(_peers[id]["last_seen"]) > SILENT_TIMEOUT:
			print("[server] peer %d timed out" % id)
			_kick(id)


func _kick(id: int) -> void:
	if _peer != null and _peer.get_peer(id) != null:
		_peer.disconnect_peer(id)


func _on_peer_connected(id: int) -> void:
	if is_server:
		_pending[id] = _clock


func _on_peer_disconnected(id: int) -> void:
	if not is_server:
		return
	_pending.erase(id)
	_leave_room(id, "disconnected")
	_peers.erase(id)


func _sender() -> int:
	if not is_server:
		return 0
	var id := multiplayer.get_remote_sender_id()
	if not _peers.has(id):
		return 0
	_peers[id]["last_seen"] = _clock
	return id


func _room_for(id: int) -> LobbyState:
	return _rooms.get(_room_of.get(id, ""), null)


func _send_lobby(room: LobbyState) -> void:
	var snap := room.snapshot()
	for m: Dictionary in room.members:
		if not m["is_bot"]:
			server_send(int(m["id"]), "s_lobby", [snap])


func _tell(id: int, text: String, is_error: bool = true) -> void:
	server_send(id, "s_notice", [text, is_error])


func _leave_room(id: int, reason: String) -> void:
	var room := _room_for(id)
	_room_of.erase(id)
	if room == null:
		return
	if room.in_match and _matches.has(room.code):
		var net_match: NetMatch = _matches[room.code]["match"]
		if is_instance_valid(net_match):
			net_match.server_on_disconnect(id)
	room.remove_member(id)
	print("[server] peer %d left room %s (%s)" % [id, room.code, reason])
	if room.is_empty_of_humans():
		_close_room(room.code)
	else:
		_send_lobby(room)


func _close_room(code: String) -> void:
	if _matches.has(code):
		var entry: Dictionary = _matches[code]
		if is_instance_valid(entry["viewport"]):
			entry["viewport"].queue_free()
		_matches.erase(code)
	_rooms.erase(code)
	print("[server] room %s closed" % code)


func _start_match(room: LobbyState) -> void:
	room.in_match = true
	var roster := room.roster()
	var config := {
		"room": room.code, "seed": room.seed_value, "cave_size": room.cave_size,
		"bot_skill": room.bot_skill, "move_regen": room.move_regen, "mode": room.mode,
		"theme": room.theme_id,
		"roster": roster, "generator_version": CaveGenerator.VERSION,
	}
	var world: Node3D = load(SceneRouter.GAME).instantiate()
	world.set("net_role", "server")
	world.set("net_config", config)
	var viewport := SubViewport.new()
	viewport.name = "Room_" + room.code
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	viewport.size = Vector2i(2, 2)
	_matches_root.add_child(viewport)
	viewport.add_child(world)
	var graph: CaveGraph = world.get("graph")
	var net_match: NetMatch = world.get("net_match")
	if graph == null or net_match == null:
		push_error("[server] room %s: the race failed to build" % room.code)
		viewport.queue_free()
		room.in_match = false
		for m: Dictionary in room.members:
			if not m["is_bot"]:
				_tell(int(m["id"]), "The server could not build that cave. Try another seed.")
		_send_lobby(room)
		return
	_matches[room.code] = {"viewport": viewport, "world": world, "match": net_match}
	config["graph_hash"] = graph.graph_hash()
	print("[server] room %s racing: seed %d, %d racers, graph %d" % [room.code, room.seed_value, roster.size(), config["graph_hash"]])
	for entry: Dictionary in roster:
		if entry["is_bot"]:
			continue
		var personal := config.duplicate(true)
		personal["local_rid"] = int(entry["rid"])
		rpc_id(int(entry["peer"]), "s_match_start", personal)
	_send_lobby(room)


## Called by the server's NetMatch once results are sent.
func server_match_finished(code: String) -> void:
	await get_tree().create_timer(RESULTS_LINGER).timeout
	if _matches.has(code):
		var entry: Dictionary = _matches[code]
		if is_instance_valid(entry["viewport"]):
			entry["viewport"].queue_free()
		_matches.erase(code)
	var room: LobbyState = _rooms.get(code, null)
	if room == null:
		return
	room.in_match = false
	room.reset_ready()
	room.seed_value = _rng.randi() % 1000000
	_send_lobby(room)


## Room peers for a race, so the race can address its humans.
func server_send(peer_id: int, method: String, args: Array) -> void:
	if not is_server or _peer == null or _peer.get_peer(peer_id) == null:
		return
	match args.size():
		0: rpc_id(peer_id, method)
		1: rpc_id(peer_id, method, args[0])
		2: rpc_id(peer_id, method, args[0], args[1])
		3: rpc_id(peer_id, method, args[0], args[1], args[2])
		4: rpc_id(peer_id, method, args[0], args[1], args[2], args[3])
		5: rpc_id(peer_id, method, args[0], args[1], args[2], args[3], args[4])


func _match_for(id: int) -> NetMatch:
	var code: String = _room_of.get(id, "")
	if not _matches.has(code):
		return null
	var net_match: NetMatch = _matches[code]["match"]
	return net_match if is_instance_valid(net_match) else null


# --- Client -> server: lobby -----------------------------------------------------------

@rpc("any_peer", "call_remote", "reliable")
func c_hello(protocol: int, generator_version: int, p_name: String) -> void:
	if not is_server:
		return
	var id := multiplayer.get_remote_sender_id()
	if not _pending.has(id) and not _peers.has(id):
		return
	_pending.erase(id)
	if protocol != PROTOCOL_VERSION or generator_version != CaveGenerator.VERSION:
		rpc_id(id, "s_notice", "Version mismatch: this server runs protocol %d / cave %d. Update your game."
			% [PROTOCOL_VERSION, CaveGenerator.VERSION], true)
		get_tree().create_timer(0.5).timeout.connect(func() -> void: _kick(id))
		return
	_peers[id] = {"name": LobbyState.sanitize_name(p_name), "last_seen": _clock}
	rpc_id(id, "s_welcome", id, {"rooms": _rooms.size(), "title": AppConfig.GAME_TITLE})


@rpc("any_peer", "call_remote", "reliable")
func c_ping(sent_at: float) -> void:
	var id := _sender()
	if id != 0:
		rpc_id(id, "s_pong", sent_at)


@rpc("any_peer", "call_remote", "reliable")
func c_create_room(mode: String) -> void:
	var id := _sender()
	if id == 0:
		return
	if _room_of.has(id):
		_leave_room(id, "made a new room")
	if _rooms.size() >= MAX_ROOMS:
		_tell(id, "The server is full right now. Try again shortly.")
		return
	var code := LobbyState.random_code(_rng)
	while _rooms.has(code):
		code = LobbyState.random_code(_rng)
	var room := LobbyState.new(code, mode)
	room.seed_value = _rng.randi() % 1000000
	room.add_human(id, _peers[id]["name"])
	_rooms[code] = room
	_room_of[id] = code
	print("[server] peer %d created %s room %s" % [id, room.mode, code])
	_send_lobby(room)


@rpc("any_peer", "call_remote", "reliable")
func c_join_room(raw_code: String) -> void:
	var id := _sender()
	if id == 0:
		return
	var code := LobbyState.normalize_code(raw_code)
	var room: LobbyState = _rooms.get(code, null)
	if room == null:
		_tell(id, "No room with code %s." % (code if code != "" else "(empty)"))
		return
	if _room_of.get(id, "") == code:
		_send_lobby(room)
		return
	if _room_of.has(id):
		_leave_room(id, "joined another room")
	var err := room.add_human(id, _peers[id]["name"])
	if err != "":
		_tell(id, err)
		return
	_room_of[id] = code
	_send_lobby(room)


@rpc("any_peer", "call_remote", "reliable")
func c_leave_room() -> void:
	var id := _sender()
	if id == 0:
		return
	_leave_room(id, "left")
	rpc_id(id, "s_left_room", "")


@rpc("any_peer", "call_remote", "reliable")
func c_set_ready(ready: bool) -> void:
	var id := _sender()
	var room := _room_for(id)
	if room == null or room.in_match:
		return
	room.set_ready(id, ready)
	_send_lobby(room)


@rpc("any_peer", "call_remote", "reliable")
func c_host_action(action: String, value: Variant) -> void:
	var id := _sender()
	var room := _room_for(id)
	if room == null:
		return
	if not room.is_host(id):
		_tell(id, "Only the host can change the race.")
		return
	if room.in_match:
		return
	var err := ""
	match action:
		"slots":
			if value is int:
				err = room.set_total_slots(value)
		"add_bot":
			err = room.add_bot()
		"remove_bot":
			err = room.remove_bot()
		"fill_bots":
			err = room.fill_with_bots()
		"seed":
			if value is int:
				room.seed_value = clampi(value, 0, 999999999)
		"random_seed":
			room.seed_value = _rng.randi() % 1000000
		"cave_size":
			if value is int:
				room.cave_size = clampi(value, 0, CaveGenerator.SIZE_PRESETS.size() - 1)
		"bot_skill":
			if value is int:
				room.bot_skill = clampi(value, 0, 2)
		"move_regen":
			if value is bool:
				room.move_regen = value
		"theme":
			if value is String and value in CaveTheme.IDS:
				room.theme_id = value
		"replace_disconnected":
			if value is bool:
				room.replace_disconnected_with_bot = value
		"mode":
			if value is String:
				room.set_mode(value)
		_:
			err = "Unknown lobby action"
	if err != "":
		_tell(id, err)
	_send_lobby(room)


@rpc("any_peer", "call_remote", "reliable")
func c_start() -> void:
	var id := _sender()
	var room := _room_for(id)
	if room == null:
		return
	if not room.is_host(id):
		_tell(id, "Only the host can start the race.")
		return
	var problem := room.start_problem()
	if problem != "":
		_tell(id, problem)
		return
	_start_match(room)


# --- Client -> server: in the race ----------------------------------------------------

@rpc("any_peer", "call_remote", "reliable")
func c_loaded(graph_hash: int) -> void:
	var id := _sender()
	var m := _match_for(id)
	if m != null:
		m.server_on_loaded(id, graph_hash)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func c_state(pos: Vector3, rot: Quaternion, vel: Vector3, grav: int, flags: int) -> void:
	var id := _sender()
	var m := _match_for(id)
	if m != null:
		m.server_on_state(id, pos, rot, vel, grav, flags)


@rpc("any_peer", "call_remote", "reliable")
func c_shift(dir_index: int) -> void:
	var id := _sender()
	var m := _match_for(id)
	if m != null:
		m.server_on_shift(id, dir_index)


@rpc("any_peer", "call_remote", "reliable")
func c_interact(box_index: int) -> void:
	var id := _sender()
	var m := _match_for(id)
	if m != null:
		m.server_on_interact(id, box_index)


@rpc("any_peer", "call_remote", "reliable")
func c_fell(unrecoverable: bool) -> void:
	var id := _sender()
	var m := _match_for(id)
	if m != null:
		m.server_on_fell(id, unrecoverable)


@rpc("any_peer", "call_remote", "reliable")
func c_emote(k: int) -> void:
	var id := _sender()
	var m := _match_for(id)
	if m != null:
		m.server_on_emote(id, k)


## Test harness only, and only honoured by a server started with --test-mode.
@rpc("any_peer", "call_remote", "reliable")
func c_test_teleport(pos: Vector3) -> void:
	var id := _sender()
	var m := _match_for(id)
	if m != null and test_mode:
		m.server_on_test_teleport(id, pos)


# ======================================================================================
# Client
# ======================================================================================

## Connect and introduce ourselves. `url` is ws://host:port or wss://host.
func connect_to_server(url: String, p_name: String) -> void:
	var clean := url.strip_edges()
	if not (clean.begins_with("ws://") or clean.begins_with("wss://")):
		last_error = "Server address must start with ws:// or wss://"
		notice.emit(last_error, true)
		_set_state(State.FAILED)
		return
	_close_peer()
	server_url = clean
	player_name = LobbyState.sanitize_name(p_name)
	_user_disconnect = false
	_open_peer()


func _open_peer() -> void:
	_peer = WebSocketMultiplayerPeer.new()
	var err := _peer.create_client(server_url)
	if err != OK:
		last_error = "Could not start a connection to %s (error %d)" % [server_url, err]
		notice.emit(last_error, true)
		_peer = null
		_set_state(State.FAILED)
		return
	multiplayer.multiplayer_peer = _peer
	_connect_started = _clock
	if state != State.RECONNECTING:
		_set_state(State.CONNECTING)


func disconnect_from_server() -> void:
	_user_disconnect = true
	_rejoin_code = ""
	_reconnect_timer = -1.0
	_close_peer()
	lobby = {}
	lobby_updated.emit(lobby)
	_set_state(State.OFFLINE)


func _close_peer() -> void:
	if _peer != null:
		_peer.close()
	_peer = null
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	local_peer_id = 0


func create_room(mode: String) -> void:
	if is_online():
		rpc_id(1, "c_create_room", mode)


func join_room(code: String) -> void:
	if is_online():
		rpc_id(1, "c_join_room", LobbyState.normalize_code(code))


func leave_room() -> void:
	_rejoin_code = ""
	if is_online():
		rpc_id(1, "c_leave_room")
	lobby = {}
	lobby_updated.emit(lobby)


func set_ready(ready: bool) -> void:
	if is_online():
		rpc_id(1, "c_set_ready", ready)


func host_action(action: String, value: Variant = null) -> void:
	if is_online():
		rpc_id(1, "c_host_action", action, value)


func start_race() -> void:
	if is_online():
		rpc_id(1, "c_start")


func send_to_server(method: String, args: Array) -> void:
	if not is_online():
		return
	match args.size():
		0: rpc_id(1, method)
		1: rpc_id(1, method, args[0])
		2: rpc_id(1, method, args[0], args[1])
		5: rpc_id(1, method, args[0], args[1], args[2], args[3], args[4])


func _set_state(s: int) -> void:
	if state == s:
		return
	state = s
	state_changed.emit(state)


func _client_housekeeping(delta: float) -> void:
	if _reconnect_timer >= 0.0:
		_reconnect_timer -= delta
		if _reconnect_timer < 0.0:
			_open_peer()
		return
	if state == State.CONNECTING or state == State.RECONNECTING:
		if _clock - _connect_started > CONNECT_TIMEOUT:
			last_error = "No answer from %s" % server_url
			_close_peer()
			_retry_or_fail()
	elif state == State.CONNECTED:
		_ping_timer -= delta
		if _ping_timer <= 0.0:
			_ping_timer = PING_INTERVAL
			rpc_id(1, "c_ping", _clock)


func _on_connected_to_server() -> void:
	local_peer_id = multiplayer.get_unique_id()
	rpc_id(1, "c_hello", PROTOCOL_VERSION, CaveGenerator.VERSION, player_name)


func _on_connection_failed() -> void:
	last_error = "Could not connect to %s" % server_url
	_close_peer()
	_retry_or_fail()


func _on_server_disconnected() -> void:
	var was_racing := client_match != null and is_instance_valid(client_match)
	_close_peer()
	if was_racing:
		client_match.client_on_server_lost()
	if _user_disconnect:
		_set_state(State.OFFLINE)
		return
	last_error = "Lost connection to the server"
	# A lobby is worth getting back into; a race in progress cannot be rejoined.
	_rejoin_code = String(lobby.get("code", "")) if not was_racing else ""
	lobby = {}
	lobby_updated.emit(lobby)
	if was_racing:
		_set_state(State.FAILED)
		notice.emit(last_error, true)
		return
	_reconnect_left = RECONNECT_ATTEMPTS
	_retry_or_fail()


func _retry_or_fail() -> void:
	if not _user_disconnect and _reconnect_left > 0:
		_reconnect_left -= 1
		_set_state(State.RECONNECTING)
		_reconnect_timer = RECONNECT_DELAY
		return
	_rejoin_code = ""
	_set_state(State.FAILED)
	notice.emit(last_error, true)


# --- Server -> client -----------------------------------------------------------------

@rpc("authority", "call_remote", "reliable")
func s_welcome(peer_id: int, _info: Dictionary) -> void:
	local_peer_id = peer_id
	_reconnect_left = 0
	_set_state(State.CONNECTED)
	_ping_timer = 0.0
	if _rejoin_code != "":
		var code := _rejoin_code
		_rejoin_code = ""
		join_room(code)


@rpc("authority", "call_remote", "reliable")
func s_notice(text: String, is_error: bool) -> void:
	if is_error:
		last_error = text
	notice.emit(text, is_error)


@rpc("authority", "call_remote", "reliable")
func s_pong(sent_at: float) -> void:
	latency_ms = int((_clock - sent_at) * 1000.0)
	latency_updated.emit(latency_ms)


@rpc("authority", "call_remote", "reliable")
func s_lobby(snapshot: Dictionary) -> void:
	lobby = snapshot
	lobby_updated.emit(lobby)


@rpc("authority", "call_remote", "reliable")
func s_left_room(_reason: String) -> void:
	lobby = {}
	lobby_updated.emit(lobby)


@rpc("authority", "call_remote", "reliable")
func s_match_start(config: Dictionary) -> void:
	GameState.net_role = "client"
	GameState.net_config = config
	GameState.cave_size = int(config.get("cave_size", 1))
	GameState.seed_value = int(config.get("seed", 0))
	GameState.theme_id = String(config.get("theme", "stone_age"))
	GameState.last_results_online = false
	SceneRouter.start_match()


@rpc("authority", "call_remote", "reliable")
func s_countdown(value: int) -> void:
	if client_match != null:
		client_match.client_on_countdown(value)


@rpc("authority", "call_remote", "reliable")
func s_go(elapsed: float) -> void:
	if client_match != null:
		client_match.client_on_go(elapsed)


@rpc("authority", "call_remote", "unreliable_ordered")
func s_snapshot(elapsed: float, server_time: float, racers: Array, spiders: Array) -> void:
	if client_match != null:
		client_match.client_on_snapshot(elapsed, server_time, racers, spiders)


@rpc("authority", "call_remote", "reliable")
func s_racer_state(rid: int, hearts: float, charges: int, flags: int) -> void:
	if client_match != null:
		client_match.client_on_racer_state(rid, hearts, charges, flags)


@rpc("authority", "call_remote", "reliable")
func s_shift(rid: int, dir_index: int) -> void:
	if client_match != null:
		client_match.client_on_shift(rid, dir_index)


@rpc("authority", "call_remote", "reliable")
func s_shift_denied(reason: String, charges: int, grav: int) -> void:
	if client_match != null:
		client_match.client_on_shift_denied(reason, charges, grav)


@rpc("authority", "call_remote", "reliable")
func s_box(box_index: int, rid: int, reward: String, description: String) -> void:
	if client_match != null:
		client_match.client_on_box(box_index, rid, reward, description)


@rpc("authority", "call_remote", "reliable")
func s_clue(direction: Vector3, vertical: int) -> void:
	if client_match != null:
		client_match.client_on_clue(direction, vertical)


@rpc("authority", "call_remote", "reliable")
func s_crumble(tile_index: int) -> void:
	if client_match != null:
		client_match.client_on_crumble(tile_index)


@rpc("authority", "call_remote", "reliable")
func s_finished(rid: int, place: int, time: float) -> void:
	if client_match != null:
		client_match.client_on_finished(rid, place, time)


@rpc("authority", "call_remote", "reliable")
func s_eliminated(rid: int, time: float, disconnected: bool) -> void:
	if client_match != null:
		client_match.client_on_eliminated(rid, time, disconnected)


@rpc("authority", "call_remote", "reliable")
func s_replaced(rid: int, new_name: String) -> void:
	if client_match != null:
		client_match.client_on_replaced(rid, new_name)


@rpc("authority", "call_remote", "reliable")
func s_correct(pos: Vector3, rot: Quaternion, grav: int) -> void:
	if client_match != null:
		client_match.client_on_correct(pos, rot, grav)


@rpc("authority", "call_remote", "reliable")
func s_emote(rid: int, k: int) -> void:
	if client_match != null:
		client_match.client_on_emote(rid, k)


@rpc("authority", "call_remote", "reliable")
func s_results(results: Array, stats: Dictionary, elapsed: float) -> void:
	if client_match != null:
		client_match.client_on_results(results, stats, elapsed)
