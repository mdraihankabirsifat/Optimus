# Credits

## Team Optimus

- Md. Raihan Kabir Sifat
- Estiak Zaman Atul
- Sadman Sakib
- Ashraf Hossain Chowdhury

## Engine and tools

| Dependency | Licence | Used for |
|---|---|---|
| **Godot Engine 4.7.2** | MIT, <https://godotengine.org/license> | The game, the dedicated server, exports |
| Godot 4.7.2 Linux binary, downloaded at Docker build time from <https://github.com/godotengine/godot/releases> | MIT | Running the headless server in the container. Not stored in the repository. |
| Debian `bookworm-slim` Docker image | Debian free software licences, <https://www.debian.org/legal/licenses/> | Container base for the server. Not stored in the repository. |
| `ca-certificates`, `wget`, `unzip`, `libfontconfig1` Debian packages | Their Debian licences | Installed in the container to fetch and run Godot |

No Godot plugins, addons or third-party GDScript are used.

## Assets

None. Every asset in the game is generated at runtime by project code:

| Asset | Source |
|---|---|
| Cave geometry and stone textures | `scripts/cave/cave_builder.gd` (noise textures, primitive meshes) |
| Fire, pistons, spiders, mystery boxes, crystals, torches, racers | `scripts/gameplay/*.gd`, `scripts/player/racer_rig.gd`, `scripts/cave/cave_builder.gd` |
| Music, ambience, all sound effects | `autoload/audio_manager.gd` (synthesised from sine waves and noise) |
| Logo and UI | `scripts/ui/ui_kit.gd`; Godot's built-in default font |
