# NETWORKING

Online Race and Mixed Race. Godot 4.7.2 `WebSocketMultiplayerPeer`, one authoritative
headless server, any number of rooms.

**Offline Bot Race never touches any of this.** The race code checks `net_role`, which is
empty offline, and never calls `NetManager`. If networking breaks, Bot Race still works.

---

## Pieces

| File | Role |
|---|---|
| `autoload/net_manager.gd` | The WebSocket peer, rooms, every RPC. Same node path on server and client. |
| `scripts/net/lobby_state.gd` | One room as pure data: slots, host, bots, ready flags, start rules. No sockets. |
| `scripts/net/net_match.gd` | One race's link to the network. Server: authority. Client: mirror. |
| `scripts/net/server_main.gd` + `scenes/net/server.tscn` | Dedicated server entry point. |
| `scripts/gameplay/game_world.gd` | One scene, three roles: `""` offline, `"client"`, `"server"`. |
| `scripts/gameplay/world_scope.gd` | Group lookups limited to one race, so rooms never see each other. |
| `scripts/ui/mode_select.gd`, `scripts/ui/online_lobby.gd` | Play screen and online lobby. |
| `Dockerfile`, `render.yaml`, `.env.example` | Deployment. |

## Authority

The server owns everything that decides the race:

- **Move charges.** A client asks to shift. The server checks racing phase, charges, direction,
  and deducts exactly once. A client predicts its own shift so the mechanic never waits on the
  network, and snaps back if the server refuses.
- **Hearts.** Hazards on the server hit server-side bodies. On a client, `PlayerHealth.net_client`
  makes local hazards harmless; hearts arrive from the server. A client reports falling out of
  the world; it can only ever hurt its own racer by doing so.
- **Mystery boxes.** First valid request wins. The server checks distance and opens once, rolls
  the reward and applies it. Clues are sent only to the racer who earned them.
- **Countdown, clock, finish trigger, placements, elimination, results.**
- **Bots.** Simulated on the server with the same discovered-graph planner as offline.
- **Crumbling floors and spiders.** Server state, relayed. Pistons follow the server clock.
- **The Freedom Duel** (Prompt 2). Finalist selection and order, moving finalists to the arena,
  fresh duel hearts, every finalist's DOF, weapon hits and damage, Axis Locks and immunity,
  Freedom Core spawns and captures, DOF shifts, sudden death, the Champion and final placements.
  A client's `FreedomDuel` only mirrors `s_duel_state`/`s_duel_event`. Human finalists are puppets
  on the server: it sets their arena spawn as the accepted pose and corrects any cave pose still
  in flight, which is what moves the client. Hits resolve against the server's copy of the target.
  While anyone has qualified the "all humans resolved" grace is off; the duel's own limits end it.
  A finalist who disconnects has already finished the cave, so no bot takes it over: it forfeits
  and the other finalist is Champion ("opponent left"). A disconnect while waiting simply leaves
  Qualified 1st waiting for someone else.

Clients own: their own movement, look, and everything rendered. A client's pose is accepted
only if it is plausible: under 75 units/s of travel, inside world bounds, finite. Otherwise the
server sends a correction. Gravity in a pose is ignored; the server's frame stands.

## Racer ids

Every racer has a `rid`: its slot index in the lobby, its index in `MatchController.racers`,
and its spawn angle, identical on every machine. Events name racers by `rid`.

## Messages

Client to server (all reliable except pose):

| RPC | Meaning |
|---|---|
| `c_hello(protocol, generator_version, name)` | First message. Wrong versions are turned away with a message. |
| `c_ping` | Every 3 s. Latency shown in the lobby; silent peers are dropped after 20 s. |
| `c_create_room(mode)`, `c_join_room(code)`, `c_leave_room` | Rooms. |
| `c_set_ready(bool)` | Guest readiness. |
| `c_host_action(action, value)` | Host only: slots, add/remove/fill bots, seed, size, skill, regen, mode, bot takeover. |
| `c_start` | Host only, validated by `LobbyState.start_problem()`. |
| `c_loaded(graph_hash)` | Cave built. Server starts the countdown when all have loaded (or after 15 s). A wrong hash removes the client. |
| `c_state(pos, rot, vel, grav, flags)` | 20 Hz pose. |
| `c_shift(dir)`, `c_interact(box)`, `c_fell(unrecoverable)`, `c_emote(k)` | Intent. |
| `c_duel_fire(kind, origin, dir)` | Freedom Duel trigger, `pulse` or `lock`. Refused outside the fight, on cooldown, for non-finalists or garbage; a muzzle more than 3 units from the shooter is pulled back to it. |
| `c_test_teleport(pos)` | Honoured only by a server started with `--test-mode`. |

Server to client: `s_welcome`, `s_notice`, `s_pong`, `s_lobby(snapshot)`, `s_left_room`,
`s_match_start(config)`, `s_countdown`, `s_go`, `s_snapshot` (20 Hz poses, spiders, clock),
`s_racer_state(rid, hearts, charges, flags)`, `s_shift`, `s_shift_denied`, `s_box`, `s_clue`,
`s_crumble`, `s_finished`, `s_eliminated`, `s_replaced`, `s_correct`, `s_emote`, `s_results`,
`s_duel_state(state)` (phase, finalist rids, clock, shift, core, and per finalist DOF, axis, lock,
immunity, core boost, cooldowns, hearts, shield, stats) and `s_duel_event(kind, args)` (`shot`,
`locked`, `resisted`, `core`, `end`). `PROTOCOL_VERSION` is 2.

WebSocket runs over TCP, so every message arrives in order whatever transfer mode is declared.

## Same cave everywhere

The server sends the seed, size and roster; each client generates the cave itself and reports
its `CaveGraph.graph_hash()`. The generator version is checked in the handshake. Verified across
Windows clients and the Linux Docker server: seed 4242 gives graph hash 266052552 on both.

## Rooms and concurrency

Room codes are 4 characters from an alphabet without look-alike letters. Each running race lives
in its own `SubViewport` with `own_world_3d`, so physics, hazards and finish triggers of different
rooms never interact, and all group lookups go through `WorldScope`. Up to 32 rooms.

A race ends when every racer resolves, when only one racer is left unresolved after someone has
finished, at the 5-minute limit, or 20 s after every human has finished or been eliminated.
Late joining is not allowed mid-race. After results the room returns to its lobby.

## Disconnects

- Lobby: the slot is freed. If the host leaves, the next human hosts. Empty rooms close.
- Mid-race, Mixed Race (default): a fresh bot takes the racer over. It knows nothing of the cave.
- Mid-race, Online Race or takeover off: the racer is marked DISCONNECTED and the race continues.
- Client loses the server: lobby clients reconnect up to 3 times and rejoin the room code.
  Mid-race clients see CONNECTION LOST and return to the menu; offline play still works.

Connection states shown: Offline, Connecting, Connected, Reconnecting, Failed.

---

## Run a local server and two clients

```bash
# Terminal 1: server (from source)
godot --headless --path . -- --server --port=8910

# Terminals 2 and 3: two game windows
godot --path .
```

In each game: Play, then Mixed Race (or Online Race), connect to `ws://127.0.0.1:8910`.
One creates a room; the other joins with its code. The exported exe works the same way:

```bash
SixWaysDown.exe --headless -- --server --port=8910
```

Release exports refuse a scene path on the command line, which is why `--server` exists.

## Docker

```bash
docker build -t six-ways-down-server .
docker run --rm -p 8910:8910 six-ways-down-server
```

Verified on this project: image builds, server starts, two Windows clients raced through it.

## Render

Not deployed by the team yet: it needs a Render account. Steps:

1. Push the repository to GitHub (done).
2. Render dashboard: New, Blueprint, pick the repository. `render.yaml` creates a free Docker
   web service named `six-ways-down-server`. (Or: New, Web Service, Docker runtime, root
   Dockerfile, no start command.)
3. Render sets `PORT` and terminates TLS. The server listens on `PORT` automatically.
4. When it is live, players connect to `wss://six-ways-down-server.onrender.com`.
5. Optional: put that address in `AppConfig.PUBLIC_SERVER_URL` so it is the default, or open the
   web build with `?server=wss://...`, or run the exe with `-- --server-url=wss://...`.

Free-tier limitations to know before judging:

- The service sleeps after about 15 minutes idle. The first connection can take up to a minute;
  the client waits 75 s and says so.
- One small instance. Several rooms fit; heavy load does not.
- A web build served over https must use `wss://`, never `ws://`.
- Redeploying restarts the server and ends every room.

**If Render is unavailable at judging, use offline Bot Race.** It needs nothing.

## Security notes

No secrets exist anywhere in the project. Names are sanitised to 16 safe characters, room codes to
the code alphabet, every RPC checks the sender is a known peer in that room, host actions check the
host, argument types are checked before use, and clients cannot award themselves anything.
