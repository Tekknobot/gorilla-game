# Enemy Crowd / Reinforcement Spawner

Defaults:
- 6 enemies start inside the arena, split across left and right.
- Up to 10 living enemies at once.
- 2 reinforcements per wave.
- Reinforcements arrive every 3.5–5.5 seconds while below the cap.
- Reinforcements walk in from x=-88 and x=1240.
- Defeated wave enemies finish their death/corpse-hold animation, then are removed.
- Palette randomization still applies to every new enemy.
- P rerolls all living enemy palettes.

Crowd rule:
- Only 2 enemies can actively attack at once by default.
- Others wait briefly for an attack slot, reducing unreadable dog-piling.

Select the Game root node to tune:
initial_enemy_count, max_active_enemies, enable_reinforcements,
enemies_per_reinforcement, reinforcement_min_delay,
reinforcement_max_delay, first_reinforcement_delay,
max_simultaneous_attackers.

The ground and side walls are extended beyond the camera so off-screen entrants
can physically walk into view instead of teleporting at the edge.
