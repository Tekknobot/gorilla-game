# Human Enemy Integration

The previous polygon training dummy has been replaced by a spawned human enemy.

## Human sprite sheets

All four supplied strips are used from `Sprites/Humans/Sheets/`:

- `dude_idle.png` — idle loop
- `dude_walk.png` — approach/chase loop
- `dude_attack.png` — close-range attack
- `dude_hurt.png` — damage reaction

Each strip is detected as 8 frames of 48x48 pixels. The enemy is displayed at
2x scale in the prototype to match the arena and gorilla presentation.

## New files

- `Scenes/enemy.tscn`
- `Scripts/enemy.gd`
- `Scripts/enemy_hurtbox.gd`

## Prototype behavior

- The game spawns one enemy at the old training-target position.
- The enemy idles when the gorilla is far away.
- It walks toward the gorilla inside its chase radius.
- It attacks when close enough, using `dude_attack.png`.
- Gorilla combo/secondary/slam hits trigger `dude_hurt.png` and knockback.
- Enemy health is shown in the existing lower-right HUD readout.
- At 0 health, the enemy finishes its hurt animation, disappears briefly, and
  respawns at its original spawn position because no death sheet was supplied.
- Enemy attacks interrupt/knock back the gorilla. Rolling ignores the enemy hit.

The existing gorilla controller, random-start jab/hook/uppercut combo, slam,
roll, jump/fall/land and gamepad mappings are preserved.
