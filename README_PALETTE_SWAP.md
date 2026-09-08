# Human Enemy Palette-Swap System

The human enemy now uses `Shaders/human_palette_swap.gdshader` on its
`AnimatedSprite2D`. The shader is keyed to the actual colors used by the
exported dude sprite sheets, so it works across idle, walk, attack, hurt and
death without generating duplicate sprite art.

## What changes

Three ramps are recolored independently:

- skin / exposed flesh
- upper clothing + compatible hat/cool clothing shades
- pants / khaki clothing ramp

Black outlines, facial definition, white details and unrelated accent colors
are intentionally preserved.

## Automatic variants

`Scripts/enemy.gd` contains 7 skin tones, 8 upper-clothing colors and 8 pants
colors. By default the enemy chooses a random combination on spawn and again
when it respawns.

Each enemy duplicates its ShaderMaterial at runtime, so if you later spawn
multiple enemies they can each use different colors without changing the
others.

## Inspector controls on HumanEnemy

Appearance:

- `randomize_palette_on_spawn`
- `randomize_palette_on_respawn`
- `skin_variant` (-1 = random)
- `top_variant` (-1 = random)
- `pants_variant` (-1 = random)
- `palette_strength`

Set any variant index to a fixed value if you want a particular enemy type to
always use the same appearance.

## Prototype test key

Press `P` while running the test arena to reroll the current human enemy's
appearance instantly.

## Adding more colors

Add another `Color8(...)` entry to `SKIN_TONES`, `TOP_COLORS` or
`PANTS_COLORS` in `Scripts/enemy.gd`. The shader does not need to be changed
when adding target colors.

If the original dude artwork itself gains new source palette shades, add those
source RGB values to the corresponding matching section in
`Shaders/human_palette_swap.gdshader`.

`Docs/dude_palette_preview.png` shows several example combinations generated
from the same original sprite.
