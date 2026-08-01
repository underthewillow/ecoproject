extends Node

## Lightweight one-way event bus (§8), autoloaded (see project.godot).
## Lets the renderer (look_study.gd) announce a cosmetic event without
## holding a reference to the audio system, and lets the audio system
## react without holding a reference to the renderer - same decoupling
## principle as everything else in Track B, just for events instead of
## polled state. Nothing ever listens back the other way.

## trophic_level: 0 = daphnia ate algae, 1 = fish ate daphnia. Purely a
## cosmetic signal - the real predation is fake/cosmetic-only itself
## (see look_study.gd's _try_eat), so this carries no simulation weight.
signal predation(trophic_level: int)
