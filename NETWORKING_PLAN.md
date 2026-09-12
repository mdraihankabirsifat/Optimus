# Phase 2 networking plan

## Why Phase 1 is local

The local prototype lets Team Optimus validate the core DOF movement rules, input feel, scoring loop, menus, and save flow without mixing those design questions with latency, deployment, identity, or synchronization bugs. Both players still use the same reusable controller and explicit player identity, which makes the prototype useful rather than disposable.

## Authoritative hosting

The final online version should use a dedicated authoritative server. Clients should send input intent; the server should validate movement against each player's DOF, simulate or validate position and rotation, own health and scores, and broadcast snapshots. This prevents a client from granting itself forbidden motion, health, or points.

A browser client cannot simply host a reliable public game server: browsers cannot accept arbitrary inbound socket connections, may sit behind NAT/firewalls, and have restricted networking APIs. A publicly reachable service is therefore required for cross-device rooms.

## Proposed direction

Phase 2 should add a WebSocket-compatible dedicated server so both Windows and Web clients use the same transport. The service should provide:

- room creation/joining and short room codes;
- player identity, readiness, and disconnect/reconnect handling;
- authoritative validation of input and DOF constraints;
- synchronized position, rotation, health, score, timers, collectibles, and hazards;
- interpolation and reconciliation for responsive client presentation;
- deployment configuration, TLS, observability, and protocol version checks.

## Boundary already present

`NetworkManager` exposes connection, disconnection, room, and player lifecycle signals without pretending a transport exists. `DOFPlayer` owns reusable movement constraints and has an explicit `player_id`; temporary arena scoring and hazards are isolated from it. `GameManager` owns only session selection, while saves and settings have separate managers.

Phase 2 must implement the WebSocket protocol and server, change live players from direct local input to input-command sources, add snapshot serialization/reconciliation, make arena spawning authoritative, and decide account/reconnect policy. No tokens, URLs, paid services, or deployment secrets are included in Phase 1.
