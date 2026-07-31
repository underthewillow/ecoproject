extends RefCounted

## The single seeded RNG source for all sim randomness (§3.1). Sim code must
## never call the engine's global randf()/randi() — only through an instance
## of this class — or two runs of the same seed can diverge.

var _rng := RandomNumberGenerator.new()

func _init(seed_value: int) -> void:
	_rng.seed = seed_value

func randf() -> float:
	return _rng.randf()

func randf_range(from: float, to: float) -> float:
	return _rng.randf_range(from, to)

func randfn(mean: float = 0.0, deviation: float = 1.0) -> float:
	return _rng.randfn(mean, deviation)

func randi_range(from: int, to: int) -> int:
	return _rng.randi_range(from, to)
