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

## Daphnia's trait-binned population (§4). `daphnia` is the scalar total
## across every bin — kept for anything that only needs total biomass
## (mass-conservation checks, the old Phase 2/3 harness prints).
## `daphnia_mean_size` is the population-weighted mean body size — the
## quantity §4.2's acceptance criterion is actually measured on: does it
## fall when fish are present and recover when they're removed?
## `daphnia_bins` is a plain copy of the per-bin densities, for anything
## that needs the full distribution (e.g. confirming it hasn't collapsed
## onto a single bin). All three are derived from the sim's internal
## TraitBinPopulation each tick — this snapshot never holds that live
## object itself, matching the no-live-references rule above.
var daphnia: float = 0.0
var daphnia_mean_size: float = 0.0
var daphnia_bins: Array[float] = []

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
	copy.daphnia_mean_size = daphnia_mean_size
	copy.daphnia_bins = daphnia_bins.duplicate()
	copy.fish = fish
	copy.respired = respired
	return copy
