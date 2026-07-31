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

## Abiotic pond state that evolves each tick (§3.2). `light` and
## `temperature` are run parameters, not evolving state, so they live on
## SimConfig instead.
var algae: float = 0.0
var nutrients: float = 0.0
var detritus: float = 0.0

## Single-body-size population for Phase 2 (§8) - a scalar, not yet the
## trait-binned distribution §4 introduces in Phase 4.
var daphnia: float = 0.0

## Fish population for Phase 3 (§8) - a scalar; fish never evolve (§3.3).
var fish: float = 0.0

## Cumulative biomass lost to fish metabolic maintenance (§3.3's "starves
## if intake falls below maintenance"). Unlike every other flow in this
## sim, maintenance cost is respired out of the system rather than routed
## to detritus, so it's tracked here purely so mass-conservation checks
## can verify algae+nutrients+detritus+daphnia+fish+respired stays
## constant instead of silently "leaking".
var respired: float = 0.0

func duplicate_state() -> RefCounted:
	var copy = get_script().new()
	copy.tick = tick
	copy.time = time
	copy.algae = algae
	copy.nutrients = nutrients
	copy.detritus = detritus
	copy.daphnia = daphnia
	copy.fish = fish
	copy.respired = respired
	return copy
