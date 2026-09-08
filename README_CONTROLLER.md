# Gorilla Character Controller Prototype

This prototype uses the supplied gorilla pixel-art sprite sheets. The source art is arranged in 96x96 cells (48x48 artwork exported at 2x scale).

## Controls

### Keyboard
- Move: A / D or Left / Right
- Run: hold Shift
- Jump: Space, W, or Up
- Attack 1: J
- Attack 2: K
- Slam: L
- Roll: Ctrl or C
- Test death: Backspace
- Respawn: R

### Gamepad
- Move: Left Stick or D-pad
- Run: hold Right Trigger or press Left Stick (L3)
- Jump: A / Cross
- Attack 1: X / Square
- Attack 2: Y / Triangle
- Slam: Right Shoulder (RB / R1)
- Roll: B / Circle
- Test death: View / Back
- Respawn: Start / Options

## Controller features
- Acceleration/deceleration instead of instant horizontal velocity
- Separate walk and run speeds
- Coyote time
- Jump buffering
- Variable jump height
- Air control and max fall speed
- Dedicated jump, fall, landing, roll and slam states
- Primary and secondary attack states with active hitbox windows
- Death and debug respawn
- Training target with health for testing attack timing
- Automatic horizontal-strip frame detection for 96x96 animation cells

## Animation mapping in this archive
- Idle: 8 frames
- Walk: 8 frames
- Run: 8 frames
- Jump: 8 frames
- Fall: 6 frames
- Land: 4 frames
- Attack 1: 8 frames
- Slam: 12 frames
- Roll: 16 frames
- Death: 8 frames

Attack 2 still reuses `attack.png` with alternate/heavier timing.

## Changes in this patch
- Updated the controller to use all 6 frames in the new `fall.png`.
- Updated the controller to use all 16 frames in the new `roll.png`.
- Removed hard-coded full-strip frame lists. Full sprite strips are now detected from `texture width / 96`, so future longer strips are picked up automatically.
- Action animation FPS is calculated from the real frame count while preserving the intended gameplay duration. Adding frames makes the action smoother instead of silently truncating it or making the move unexpectedly longer.
- Restored visual sprite rotation during the roll. The `AnimatedSprite2D` completes one full rotation over the roll while the CharacterBody2D and collision shape remain upright.
- Roll duration is 0.50 seconds so the 16-frame animation remains responsive while every frame is displayed.
- Jump now plays naturally during ascent instead of being manually paused on velocity-selected frames; the dedicated fall animation takes over near the apex.
- Landing continues to use its dedicated 4-frame recovery while movement remains responsive.
- Slam uses all 12 supplied frames with its damage window expressed as a percentage of the full animation.

## Main files
- `Scenes/game.tscn` - test arena and HUD
- `Scenes/player.tscn` - CharacterBody2D and collision/hitbox setup
- `Scripts/player.gd` - movement/state/animation controller
- `Scripts/game.gd` - keyboard + gamepad InputMap setup and HUD
- `Scripts/training_dummy.gd` - simple combat target
