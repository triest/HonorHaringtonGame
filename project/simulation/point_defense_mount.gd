extends RefCounted
## PointDefenseMount
##
## Ship-mounted laser-cluster defense against incoming missiles (ТЗ §22
## Point Defense), distinct from counter-missiles (§20, own launched
## interceptor entity) -- CANON confirms PD and counter-missiles are
## separate, LAYERED defenses used together (CANON_RULES.md, sixth check:
## "thickened the defensive envelope" alongside CMs and ECM), not
## alternatives to each other.
##
## Unlike a single-shot weapon resolution, PD tracks ongoing engagement
## state PER INCOMING MISSILE: reaction time before it can fire at all,
## then repeated shots (gated by its own recharge cycle) until either the
## missile is destroyed or it leaves engagement range/reaches the ship.
##
## ASSUMPTION (no canonical numbers found for any of these -- see
## ASSUMPTIONS.md): engagement range, reaction time, recharge time, and
## hits-required-to-kill are all placeholders. The STRUCTURE (reaction
## time gate + multiple shots + own recharge cycle, meaning a large enough
## missile salvo can outrun a single mount's kill rate) reflects the CANON
## "layered, saturable defense" concept although the exact numbers
## do not come from the books.
class_name PointDefenseMount

const MissileState = preload("res://simulation/missile_state.gd")
const AttackGeometry = preload("res://simulation/attack_geometry.gd")

## ТЗ §22.1 explicitly names "any future PD mount firing-arc restriction"
## as an anticipated, not-yet-built gap alongside the already-implemented
## bow/stern wedge gap (§41.1). This closes it: a mount can be restricted
## to the subset of AttackGeometry.Sector values it can physically bear
## on, IN THE MOUNTING SHIP'S OWN LOCAL FRAME -- identical convention to
## WeaponMount.arc_sectors (see weapon_mount.gd), reusing the same
## 6-sector coarse granularity rather than a continuous firing cone
## (same documented simplification, ASSUMPTIONS.md).
##
## CANON basis for mounts actually being positional rather than
## omnidirectional: CLOUD.md §2.2 class examples list separate broadside
## PD counts and chase PD counts for the same ship (e.g. "broadside
## ...12PD, chase ...6PD") -- point defense is built into a hull exactly
## like energy weapons, along the broadside and chaser zones, not a
## single ship-wide floating turret.
##
## Deliberately DIFFERENT DEFAULT from WeaponMount: WeaponMount.arc_sectors
## defaults to an empty Array, which means "can bear on nothing" until a
## scenario author explicitly assigns an arc, because every existing
## weapon mount construction already does so. PointDefenseMount predates
## this arc concept entirely -- every existing scenario/test constructs
## PointDefenseMount.new() with no arc assigned and expects it to
## engage regardless of bearing (the pre-this-change behavior for the
## whole life of the class). To avoid silently disarming every mount in
## every existing scenario the moment this field exists, an EMPTY
## arc_sectors here means OMNIDIRECTIONAL (can bear on every sector) --
## the historical behavior -- and only a non-empty Array restricts
## engagement to those sectors specifically. A scenario/ship-loadout
## author who wants a positional broadside/chaser PD battery (matching
## the CLOUD.md class data above) sets arc_sectors explicitly via the
## static helpers below.
static func broadside_arc() -> Array:
	return [AttackGeometry.Sector.PORT, AttackGeometry.Sector.STARBOARD]

static func bow_chaser_arc() -> Array:
	return [AttackGeometry.Sector.BOW]

static func stern_chaser_arc() -> Array:
	return [AttackGeometry.Sector.STERN]

var arc_sectors: Array = []  # Array[AttackGeometry.Sector]; empty = omnidirectional, see doc comment above.
var max_engagement_range_m: float = 20_000.0    # ASSUMPTION: shorter-ranged than a counter-missile intercept (which closes actively); PD is a fixed-mount beam weapon.
var reaction_time_s: float = 1.5                 # ASSUMPTION: time a contact must be tracked before PD can engage it.
var recharge_time_s: float = 0.75                # ASSUMPTION: rapid-fire compared to a main energy mount.
var hits_required_to_kill: int = 2               # ASSUMPTION: a single laser hit is not automatically a kill (missile body is small/tough/maneuvering).
var condition: float = 1.0                       # 1.0 = fully functional; synced each tick from POINT_DEFENSE subsystem condition (§25, see SimulationWorld._sync_subsystem_driven_conditions()).


var cooldown_remaining_s: float = 0.0
var _tracking_target = null       # the MissileState currently being engaged, if any
var _tracking_time_s: float = 0.0
var _hits_scored: int = 0

## ТЗ §25 continuous subsystem-damage falloff (closes the "hard on/off,
## not continuous" gap this mount's `condition` field previously had --
## see ASSUMPTIONS.md/CHANGELOG.md). Two degradation shapes, both already
## established elsewhere in this codebase rather than invented fresh
## here: EFFECTIVE RANGE scales linearly with `condition` (same model as
## `ECMState.jamming_range_multiplier` and
## `CounterMissileResolution.check_intercept()`'s condition-scaled
## intercept radius); reaction/recharge TIMING scales inversely with
## `condition` (a damaged fire-control/tracking system takes
## proportionally longer to acquire a lock and cycle between shots, not
## merely a shorter reach). `condition <= 0.0` is unreachable through
## these getters in the live sim -- `is_ready()` already hard-gates
## engagement at `condition <= 0.0` before `PointDefenseResolution` ever
## reads them -- but each getter still floors `condition` defensively so
## a direct/test call never divides by zero or returns a negative range.
## INTERPRETATION, not canon: no canonical source describes HOW PD
## degrades under partial damage, only that damage matters (§22/§25).
const _MIN_CONDITION_FOR_TIMING: float = 0.05

func effective_reaction_time_s() -> float:
	return reaction_time_s / maxf(condition, _MIN_CONDITION_FOR_TIMING)

func effective_recharge_time_s() -> float:
	return recharge_time_s / maxf(condition, _MIN_CONDITION_FOR_TIMING)

func effective_engagement_range_m() -> float:
	return max_engagement_range_m * maxf(condition, 0.0)

func tick_cooldown(dt: float) -> void:
	if cooldown_remaining_s > 0.0:
		cooldown_remaining_s = maxf(0.0, cooldown_remaining_s - dt)

func is_ready() -> bool:
	return cooldown_remaining_s <= 0.0 and condition > 0.0

## Empty arc_sectors == omnidirectional (see field doc comment above).
func can_bear_on(sector) -> bool:
	return arc_sectors.is_empty() or arc_sectors.has(sector)

## Resets engagement state, e.g. when a missile is destroyed by another
## defense layer or leaves range -- PD must reacquire (reaction_time_s
## again) rather than retaining a free instant shot on a new contact.
func _reset_tracking() -> void:
	_tracking_target = null
	_tracking_time_s = 0.0
	_hits_scored = 0
