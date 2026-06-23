class_name Combat extends RefCounted
## CG-grounded combat math. Structure mirrors CrossGate (ATK/DEF derived stats
## + an elemental rate, per Battle.CalcAttributeDmgRate). Constants are tunable;
## swap in exact CG coefficients here if you later reverse-engineer them.
const VARIANCE_MIN := 0.875
const CRIT_MULT := 1.5

static func physical_damage(a: UnitData, d: UnitData, power := 100, rng := RandomNumberGenerator.new()) -> Dictionary:
	var base: float = max(1.0, (a.atk * 2 - d.def) * power / 100.0)
	var dmg := base * attribute_rate(a, d) * rng.randf_range(VARIANCE_MIN, 1.0)
	var is_crit := rng.randi_range(0, 99) < a.crit_pct
	if is_crit:
		dmg *= CRIT_MULT
	return {"damage": int(max(1, dmg)), "crit": is_crit}

static func magic_damage(a: UnitData, d: UnitData, power := 100, rng := RandomNumberGenerator.new()) -> int:
	var base: float = max(1.0, (a.matk * 2 - d.mdef) * power / 100.0)
	return int(max(1, base * attribute_rate(a, d) * rng.randf_range(VARIANCE_MIN, 1.0)))

static func hits(a: UnitData, d: UnitData, rng := RandomNumberGenerator.new()) -> bool:
	var chance := clampf(0.75 + float(a.hit - d.agi) / 256.0, 0.05, 1.0)
	return rng.randf() <= chance

## Elemental multiplier: attacker's dominant element vs defender's matching one.
static func attribute_rate(a: UnitData, d: UnitData) -> float:
	var ae := [a.earth, a.water, a.fire, a.wind]
	var de := [d.earth, d.water, d.fire, d.wind]
	var idx := 0
	for i in range(1, 4):
		if ae[i] > ae[idx]:
			idx = i
	return clampf(1.0 + float(ae[idx] - de[idx]) / 200.0, 0.5, 2.0)

## Turn order: higher 敏捷 acts first (CG uses Quick/agility).
static func sort_by_speed(units: Array) -> Array:
	units.sort_custom(func(x, y): return x.agi > y.agi)
	return units
