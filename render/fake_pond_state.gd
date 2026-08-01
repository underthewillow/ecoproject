extends RefCounted

## Shared fake pond-state generator (§8). The renderer (look_study.gd)
## and the audio system (audio/pond_audio.gd) each read this
## independently and write nothing back - neither depends on the other,
## both just stand in for real Track A sim state until Phase 6 merges
## them. Keeping the formula in one place means both consumers agree on
## what "the pond" is doing at a given moment without talking to each
## other directly.

static func population_to_count(t: float, amplitude: float, freq: float, phase: float, max_particles: int) -> int:
	var raw_population := amplitude * (1.0 + sin(t * freq + phase))
	var scaled := log(raw_population + 1.0) * 8.0
	return clampi(int(scaled), 0, max_particles)

static func algae_count(t: float, max_particles: int = 150) -> int:
	return population_to_count(t, 40.0, 0.05, 0.0, max_particles)

static func daphnia_count(t: float, max_particles: int = 60) -> int:
	return population_to_count(t, 20.0, 0.11, 2.0, max_particles)

static func fish_count(t: float, max_particles: int = 10) -> int:
	return population_to_count(t, 5.0, 0.04, 4.5, max_particles)

## 0-1 "ecosystem health" proxy - how populated all three species are
## relative to their own caps, averaged. Purely a cosmetic/audio-flavor
## signal, same as everything else in Track B - not a real sim metric.
static func health(t: float, algae_max: int = 150, daphnia_max: int = 60, fish_max: int = 10) -> float:
	var a := float(algae_count(t, algae_max)) / float(algae_max)
	var d := float(daphnia_count(t, daphnia_max)) / float(daphnia_max)
	var f := float(fish_count(t, fish_max)) / float(fish_max)
	return clampf((a + d + f) / 3.0, 0.0, 1.0)
