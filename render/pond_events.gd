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

## Unlike predation above, this one IS real: it fires when the real
## SimCore's collapse_count actually increments (§1 pillar 3 - "no hard
## fail state... a story, not a game over"), see look_study.gd's
## _step_sim_ticks. Nothing currently listens to it - pond_audio.gd still
## reads fake_pond_state.gd rather than real state - but the signal exists
## now so wiring a future audio reaction is additive, not a rewrite.
signal collapse
