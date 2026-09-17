class_name LobbyState
extends RefCounted
## One room's lobby, as pure data: who is in which slot, who hosts, which slots are bots,
## who is ready, and the race settings. The server holds the only authoritative copy and
## sends clients snapshots of it.
##
## No networking lives here, so every lobby rule is testable headlessly:
##   - 2 to 5 racers in total, at least one of them human
##   - Online Race is humans only; Mixed Race may add bots and fill empty slots with them
##   - the host sets the slot count, adds and removes bots, and starts the race
##   - a race starts only with at least two racers and every human ready
## See tests/test_net_lobby.gd.

const MIN_RACERS := 2
const MAX_RACERS := 5
const MODE_ONLINE := "online"
const MODE_MIXED := "mixed"

## Five distinct racer colours, so two racers never share one.
const COLOURS: Array[Color] = [
	Color(0.36, 0.78, 1.0),
	Color(0.95, 0.45, 0.30),
	Color(0.50, 0.85, 0.45),
	Color(0.85, 0.60, 0.95),
	Color(0.95, 0.85, 0.35),
]
const COLOUR_NAMES: Array[String] = ["Sky", "Ember", "Moss", "Amethyst", "Amber"]
const BOT_NAMES: Array[String] = ["Rook", "Vex", "Nim", "Kilo", "Juno"]
## Room codes avoid letters and digits that read alike (O/0, I/1).
const CODE_ALPHABET := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
const CODE_LENGTH := 4

var code: String = ""
var mode: String = MODE_MIXED
var host_id: int = 0
var total_slots: int = 4
## Slot order is race order. Each entry:
##   {id: int (peer id, or negative for a bot), name, is_bot, ready, colour: int, connected}
var members: Array[Dictionary] = []
var seed_value: int = 0
var cave_size: int = 1
var bot_skill: int = 1
var move_regen: bool = false
## ART-012: environment, a CaveTheme id. Visual only.
var theme_id: String = "stone_age"
## Prompt 3: Normal or Rush, and the Rush length. Frozen into the match config at start.
var ruleset: String = AppConfig.RULESET_NORMAL
var rush_seconds: int = AppConfig.RUSH_DEFAULT
## Mixed Race: a human who drops mid-race is taken over by a fresh bot that knows nothing.
## Online Race: they are marked disconnected and the race continues without them.
var replace_disconnected_with_bot: bool = true
var in_match: bool = false

var _next_bot_id: int = -1


func _init(p_code: String = "", p_mode: String = MODE_MIXED) -> void:
	code = p_code
	mode = p_mode if p_mode in [MODE_ONLINE, MODE_MIXED] else MODE_MIXED
	replace_disconnected_with_bot = mode == MODE_MIXED
	total_slots = 4 if mode == MODE_MIXED else 2


# --- Queries --------------------------------------------------------------------------

func human_count() -> int:
	var n := 0
	for m: Dictionary in members:
		if not m["is_bot"]:
			n += 1
	return n


func bot_count() -> int:
	return members.size() - human_count()


func find(id: int) -> Dictionary:
	for m: Dictionary in members:
		if int(m["id"]) == id:
			return m
	return {}


func has_member(id: int) -> bool:
	return not find(id).is_empty()


func is_host(id: int) -> bool:
	return id == host_id and host_id != 0


func is_empty_of_humans() -> bool:
	return human_count() == 0


## "" when the host may start, otherwise the reason shown on the Start button.
func start_problem() -> String:
	if in_match:
		return "A race is already running"
	if members.size() < MIN_RACERS:
		return "Need at least %d racers" % MIN_RACERS
	if members.size() > MAX_RACERS:
		return "At most %d racers" % MAX_RACERS
	if human_count() < 1:
		return "At least one racer must be human"
	if mode == MODE_ONLINE and bot_count() > 0:
		return "Online Race is humans only"
	for m: Dictionary in members:
		if not m["is_bot"] and not m["ready"] and int(m["id"]) != host_id:
			return "Waiting for %s to ready up" % m["name"]
	return ""


# --- Membership -----------------------------------------------------------------------

## Adds a human. Returns "" on success, otherwise why they could not join.
func add_human(peer_id: int, raw_name: String) -> String:
	if in_match:
		return "That room is mid-race. Try again when it finishes."
	if has_member(peer_id):
		return ""
	if members.size() >= total_slots:
		# A human always outranks a bot for a seat.
		if not _drop_last_bot():
			return "That room is full."
	var entry := {
		"id": peer_id,
		"name": unique_name(sanitize_name(raw_name)),
		"is_bot": false,
		"ready": false,
		"colour": _free_colour(),
		"connected": true,
	}
	members.append(entry)
	if host_id == 0:
		host_id = peer_id
		entry["ready"] = true
	return ""


## Removes a member. If the host leaves, the next human becomes host.
func remove_member(id: int) -> void:
	for i in members.size():
		if int(members[i]["id"]) == id:
			members.remove_at(i)
			break
	if id == host_id:
		host_id = 0
		for m: Dictionary in members:
			if not m["is_bot"]:
				host_id = int(m["id"])
				m["ready"] = true
				break


func set_ready(id: int, ready: bool) -> void:
	var m := find(id)
	if not m.is_empty() and not m["is_bot"]:
		m["ready"] = ready or id == host_id


## After a race everyone but the host readies up again for the next one.
func reset_ready() -> void:
	for m: Dictionary in members:
		if not m["is_bot"]:
			m["ready"] = int(m["id"]) == host_id


# --- Host controls --------------------------------------------------------------------

func set_total_slots(n: int) -> String:
	var wanted := clampi(n, MIN_RACERS, MAX_RACERS)
	if wanted < human_count():
		return "%d humans are already here" % human_count()
	while members.size() > wanted:
		if not _drop_last_bot():
			break
	total_slots = wanted
	return ""


func add_bot() -> String:
	if mode != MODE_MIXED:
		return "Bots are only allowed in Mixed Race"
	if members.size() >= total_slots:
		return "No empty slot"
	members.append({
		"id": _next_bot_id,
		"name": unique_name(_free_bot_name()),
		"is_bot": true,
		"ready": true,
		"colour": _free_colour(),
		"connected": true,
	})
	_next_bot_id -= 1
	return ""


func remove_bot() -> String:
	return "" if _drop_last_bot() else "No bot to remove"


## Fill Empty Slots With Bots.
func fill_with_bots() -> String:
	if mode != MODE_MIXED:
		return "Bots are only allowed in Mixed Race"
	while members.size() < total_slots:
		var err := add_bot()
		if err != "":
			return err
	return ""


func set_mode(p_mode: String) -> void:
	if p_mode not in [MODE_ONLINE, MODE_MIXED]:
		return
	mode = p_mode
	replace_disconnected_with_bot = mode == MODE_MIXED
	if mode == MODE_ONLINE:
		while _drop_last_bot():
			pass


# --- Snapshots ------------------------------------------------------------------------

## What clients receive. Plain types only, so it crosses the wire unchanged.
func snapshot() -> Dictionary:
	var slots: Array = []
	for m: Dictionary in members:
		slots.append({
			"id": int(m["id"]), "name": String(m["name"]), "is_bot": bool(m["is_bot"]),
			"ready": bool(m["ready"]), "colour": int(m["colour"]), "connected": bool(m["connected"]),
			"host": int(m["id"]) == host_id,
		})
	return {
		"code": code, "mode": mode, "host_id": host_id, "total_slots": total_slots,
		"slots": slots, "seed": seed_value, "cave_size": cave_size, "bot_skill": bot_skill,
		"move_regen": move_regen, "replace_disconnected": replace_disconnected_with_bot,
		"theme": theme_id, "ruleset": ruleset, "rush_seconds": rush_seconds,
		"in_match": in_match, "start_problem": start_problem(),
	}


## The race roster, in slot order. `rid` is the racer's index in every racer list on
## the server and on every client, so events can name a racer with one small integer.
func roster() -> Array:
	var out: Array = []
	for i in members.size():
		var m: Dictionary = members[i]
		out.append({
			"rid": i, "name": String(m["name"]), "is_bot": bool(m["is_bot"]),
			"peer": 0 if m["is_bot"] else int(m["id"]),
			"colour": COLOURS[int(m["colour"]) % COLOURS.size()].to_html(false),
		})
	return out


# --- Sanitising -----------------------------------------------------------------------

static func sanitize_name(raw: String) -> String:
	var out := ""
	for ch in raw.strip_edges():
		var c := ch.unicode_at(0)
		var ok := (c >= 48 and c <= 57) or (c >= 65 and c <= 90) or (c >= 97 and c <= 122) \
			or ch in [" ", "_", "-", "."]
		if ok:
			out += ch
		if out.length() >= 16:
			break
	out = out.strip_edges()
	return out if out != "" else "Racer"


static func normalize_code(raw: String) -> String:
	var out := ""
	for ch in raw.to_upper():
		if CODE_ALPHABET.contains(ch):
			out += ch
		if out.length() >= CODE_LENGTH:
			break
	return out


static func random_code(rng: RandomNumberGenerator) -> String:
	var out := ""
	for i in CODE_LENGTH:
		out += CODE_ALPHABET[rng.randi_range(0, CODE_ALPHABET.length() - 1)]
	return out


func unique_name(base: String) -> String:
	var taken := {}
	for m: Dictionary in members:
		taken[String(m["name"]).to_lower()] = true
	if not taken.has(base.to_lower()):
		return base
	for n in range(2, 10):
		var candidate := "%s %d" % [base.left(13), n]
		if not taken.has(candidate.to_lower()):
			return candidate
	return "%s %d" % [base.left(10), members.size() + 1]


# --- Internals ------------------------------------------------------------------------

func _drop_last_bot() -> bool:
	for i in range(members.size() - 1, -1, -1):
		if members[i]["is_bot"]:
			members.remove_at(i)
			return true
	return false


func _free_colour() -> int:
	var used := {}
	for m: Dictionary in members:
		used[int(m["colour"])] = true
	for i in COLOURS.size():
		if not used.has(i):
			return i
	return members.size() % COLOURS.size()


func _free_bot_name() -> String:
	var used := {}
	for m: Dictionary in members:
		used[String(m["name"])] = true
	for n: String in BOT_NAMES:
		if not used.has(n):
			return n
	return "Bot"
