extends RefCounted
## ECMState
##
## ТЗ §24 ECM: "ECM must be a real system... must affect detection;
## tracking; targeting; missile guidance; sensor confidence;
## countermeasures... must NOT simply be `hitChance -= 20%` unless such a
## modifier is the documented consequence of a deeper simulation model."
##
## CANON basis (Honorverse Wiki "Electronic warfare", secondary source —
## primary book-text verification for ECM specifically NOT done this pass,
## see CANON_RULES.md; ranked below a primary citation per §4 source
## priority, used here as the best available grounding): warships carry
## "a complex suite of electronic warfare systems" with three elements --
## (1) jammers/decoys used "to defeat or confuse incoming missiles";
## (2) stealth capability to "conceal ship emissions"; (3) heavy onboard
## computing driving emitters that "confuse incoming fire". Decoy drones
## are deployed OUTSIDE the ship but stay close on a tractor beam,
## receiving beamed power (their own power requirements are too high to
## be self-sufficient), which limits a ship to "only a handful of them at
## a time" -- a real resource constraint, not unlimited countermeasures.
##
## This class holds only DATA (ТЗ §8/§48 data-driven separation); the
## actual detection/guidance consequences are computed by
## SensorResolution / MissileGuidance, which read this state.
class_name ECMState

## Whether this unit's jammers are currently active. CANON: jamming is
## described as an active emission (computer suites + emitters), not a
## passive property -- a ship can choose to jam or not.
var jamming_active: bool = false

## ASSUMPTION (no canonical figure found): while jamming_active, an
## observer's EFFECTIVE detection range against this unit is multiplied
## by this factor (< 1.0 = harder to get/hold a lock through the jamming).
## This is the "deeper simulation model" the ТЗ requires -- jamming
## physically shrinks the range at which a firm track can be held, rather
## than subtracting a flat hit-chance percentage after the fact.
var jamming_range_multiplier: float = 0.4

## Decoy drones currently deployed near this unit (CANON: tethered close
## by tractor beam + beamed power, hence a small bounded list, not
## unlimited). World-space positions, updated by the owning ship/caller
## each tick (this class does not itself simulate decoy drone physics --
## an ASSUMPTION simplification; see ASSUMPTIONS.md).
var decoy_positions: Array = []

## ASSUMPTION (CANON confirms "only a handful ... at a time", no exact
## number found): maximum simultaneous decoys, enforced by callers that
## add to decoy_positions (not enforced inside this data class).
const MAX_DECOYS: int = 4

func add_decoy(position: Vector3) -> bool:
	if decoy_positions.size() >= MAX_DECOYS:
		return false
	decoy_positions.append(position)
	return true

func clear_decoys() -> void:
	decoy_positions.clear()
