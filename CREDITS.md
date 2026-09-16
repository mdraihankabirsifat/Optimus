# Credits

## Team Optimus

- Md. Raihan Kabir Sifat
- Estiak Zaman Atul
- Sadman Sakib
- Ashraf Hossain Chowdhury

## Engine

- **Godot Engine 4.7.2**, MIT licence, <https://godotengine.org/license>

## Assets

None. Every asset in the game is generated at runtime by project code:

| Asset | Source |
|---|---|
| Cave geometry and stone textures | `scripts/cave/cave_builder.gd` (noise textures, primitive meshes) |
| Fire, mystery boxes, crystals, torches | `scripts/gameplay/*.gd`, `scripts/cave/cave_builder.gd` |
| Music, ambience, all sound effects | `autoload/audio_manager.gd` (synthesised from sine waves and noise) |
| UI | Godot's built-in default font; styles in `scripts/ui/ui_kit.gd` |
