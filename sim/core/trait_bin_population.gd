extends RefCounted

## Generic trait-binned population (§4.1) — a discretised allele-frequency
## model. Population is a density (fractional "population count", not a
## headcount) spread across a fixed number of bins along one continuous
## trait axis (e.g. body size).
##
## Deliberately generic and species-agnostic: this module only knows about
## bins, densities, and offspring redistribution. It has no opinion about
## what the trait represents or what governs growth/death/reproduction
## rates — that's species-specific ecology, computed elsewhere (currently
## sim_core.gd's daphnia section) and handed in via apply_tick(). Built
## this way — rather than daphnia-specific bin logic inlined into
## sim_core.gd — so that if trait-based evolution is ever extended to
## another species (deferred for now, see docs/pond-prototype-plan.md §9),
## only a new set of rate functions is needed, not a rewrite of the bin
## mechanics themselves.
##
## Kept fully deterministic like the rest of the sim (§11.1, §11.3):
## offspring spread is a fixed convolution kernel, not a per-individual
## random draw, so trait bins introduce no new RNG dependency — a given
## seed (which today drives nothing at all, since this sim has no
## stochastic terms — see sweep_phase3.gd's header) still produces
## bit-identical output.

var bin_count: int
var trait_min: float
var trait_max: float
var densities: Array[float]

## Offspring spread kernel, symmetric around the parent bin. Index 0 is
## the weight kept in the parent's own bin; index i is the weight sent to
## each of the two bins i steps away. Must satisfy
## kernel[0] + 2*sum(kernel[1:]) == 1.0 — that's what "small mutational
## variance" (§11.1) means mechanically: most offspring land in the
## parent's bin, a smaller fraction drift one bin over, fewer still two
## bins over. Offspring that would spread past the trait range's edge are
## reflected back onto the boundary bin instead of discarded, so total
## offspring mass is conserved exactly (see apply_tick).
var spread_kernel: Array[float]


func _init(p_bin_count: int, p_trait_min: float, p_trait_max: float, p_spread_kernel: Array[float] = [0.6, 0.18, 0.02]) -> void:
	bin_count = p_bin_count
	trait_min = p_trait_min
	trait_max = p_trait_max
	spread_kernel = p_spread_kernel
	densities = []
	densities.resize(bin_count)
	densities.fill(0.0)


## The trait value (e.g. body size) at the center of bin i. Bins are
## linearly spaced across [trait_min, trait_max] — a reasonable default
## given daphnia body size spans less than an order of magnitude; a
## species with a much wider trait range might want log spacing instead,
## which would need a second constructor mode, not a change to the rest
## of this class.
func bin_trait_value(i: int) -> float:
	if bin_count <= 1:
		return (trait_min + trait_max) * 0.5
	return trait_min + (trait_max - trait_min) * float(i) / float(bin_count - 1)


func total_population() -> float:
	var total := 0.0
	for d in densities:
		total += d
	return total


## Population-weighted mean trait value — this is what "mean daphnia body
## size" (§4.2's acceptance criterion) actually is: mean_trait() of the
## daphnia population.
func mean_trait() -> float:
	var total := total_population()
	if total <= 0.0:
		return (trait_min + trait_max) * 0.5
	var weighted := 0.0
	for i in bin_count:
		weighted += densities[i] * bin_trait_value(i)
	return weighted / total


## Seeds the population across bins as a Gaussian-shaped distribution
## centered on center_trait, with std-dev width_fraction * trait_range,
## replacing whatever was there before. This is the founder-bottleneck
## mechanic (§6.2): a small founder should seed with a narrow width_fraction
## (little variation for selection to act on — evolves sluggishly no matter
## the pressure applied), a large founder with a wide one (full spread,
## adapts readily). Used for a run's initial population.
func seed_population(total_count: float, center_trait: float, width_fraction: float) -> void:
	densities.fill(0.0)
	add_population(total_count, center_trait, width_fraction)


## Same Gaussian-shaped distribution as seed_population, but added on top of
## whatever's already in each bin rather than replacing it. This is the
## runtime version of the founder-bottleneck mechanic (§6.2/§6.1) — a
## mid-run "introduce more of this species" action, which shouldn't erase
## individuals already selected for by prior ecology.
func add_population(total_count: float, center_trait: float, width_fraction: float) -> void:
	var width := maxf(width_fraction, 0.0001) * (trait_max - trait_min)
	var weights: Array[float] = []
	weights.resize(bin_count)
	var weight_sum := 0.0
	for i in bin_count:
		var distance := (bin_trait_value(i) - center_trait) / width
		var weight: float = exp(-distance * distance)
		weights[i] = weight
		weight_sum += weight
	for i in bin_count:
		densities[i] += total_count * weights[i] / weight_sum


## Applies one tick of population change.
## - net_survival_delta[i]: population change from every non-reproductive
##   flow (growth, death, predation, etc.) for bin i, already scaled by
##   whatever timestep the caller uses — added directly to bin i, no
##   redistribution, since these individuals don't change trait value.
## - offspring[i]: new individuals produced by bin i this tick, already
##   timestep-scaled. These get redistributed across neighbouring bins via
##   spread_kernel rather than landing back in bin i outright — that
##   redistribution *is* the mutation/heritability step (§11.1).
func apply_tick(net_survival_delta: Array[float], offspring: Array[float]) -> void:
	var next: Array[float] = []
	next.resize(bin_count)
	for i in bin_count:
		next[i] = maxf(densities[i] + net_survival_delta[i], 0.0)

	var max_offset := spread_kernel.size() - 1
	for i in bin_count:
		var produced: float = offspring[i]
		if produced <= 0.0:
			continue
		next[i] += produced * spread_kernel[0]
		for offset in range(1, max_offset + 1):
			var weight: float = produced * spread_kernel[offset]
			# Reflect at the boundary rather than discard, so total
			# offspring mass is conserved exactly even for bins near the
			# edge of the trait range.
			next[clampi(i - offset, 0, bin_count - 1)] += weight
			next[clampi(i + offset, 0, bin_count - 1)] += weight

	densities = next
