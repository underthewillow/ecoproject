extends RefCounted

## Snapshot type exposed to the renderer (§3.1). Renderers must only ever
## hold a duplicate_state() copy, never the sim's live instance, so nothing
## outside the sim can mutate it.
##
## No class_name here: a self-referential class_name return-type hint (on
## duplicate_state below) needs the editor-built global class cache, which
## doesn't exist on a fresh checkout or CI runner. Everything that needs
## this type reaches it via preload instead (see sim_core.gd).

var tick: int = 0
var time: float = 0.0

## Placeholder scalar standing in for algae biomass until Phase 1 (§3.3)
## replaces it with real growth/uptake math. It only needs to exist so
## Phase 0 has something to drive through the RNG and chart.
var sample: float = 0.0

func duplicate_state() -> RefCounted:
	var copy = get_script().new()
	copy.tick = tick
	copy.time = time
	copy.sample = sample
	return copy
