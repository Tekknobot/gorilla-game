# Gorilla Brawler Feel Pass

This pass keeps the existing gorilla/human animation workflow and adds combat
feedback systems that do not require new sprite art.

## Added

- Attack-specific enemy reactions:
  - Jab: short hitstun / small push.
  - Hook: stronger horizontal shove.
  - Uppercut: light pop when used early in the random combo, full launcher when
    it lands as hit 3.
  - Attack 2: heavier knockback.
  - Slam: large stagger and launch.
- Authored attack root motion. The gorilla stays committed to attacks but makes
  short controlled forward drives instead of sliding freely.
- Different hitbox sizes/offsets for jab, hook, uppercut, attack 2 and slam.
- Global hit-stop with different freeze lengths per strike.
- Camera shake scaled by impact strength.
- Procedural impact-burst visual effect.
- Red enemy hit flash (existing system retained).
- Player hitstun / interruption when the human connects.
- On-screen multi-hit counter.
- Placeholder impact audio generated for light, heavy, slam and enemy hits.
- Existing random-start combo retained.
- Existing roll invulnerability retained.
- Existing death / corpse hold / respawn retained.
- Existing automatic sprite-strip frame counting retained.

## Key tuning points

Player attack timing is near the top of `Scripts/player.gd`:

- `JAB_TIME`
- `HOOK_TIME`
- `UPPERCUT_TIME`
- `SLAM_TIME`

Enemy reaction tuning is near the top of `Scripts/enemy.gd`:

- `JAB_STUN`
- `HOOK_STUN`
- `UPPERCUT_STUN`
- `ATTACK_2_STUN`
- `SLAM_STUN`

Global feel is in `Scripts/game.gd` inside `request_combat_impact()`:

- `hit_stop`
- `shake`
- `burst_power`

The generated WAV files are placeholders in `Audio/` and can be replaced later
without changing the combat code if you keep the same filenames.

## Combo note

Because the combo can begin on a random attack, an uppercut that happens on hit
1 or 2 uses a smaller pop reaction so it does not throw the enemy out of range.
An uppercut on hit 3 becomes the full launcher. This preserves random animation
variety while keeping a complete three-hit string viable.
