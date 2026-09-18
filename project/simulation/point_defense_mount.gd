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
## "layered, saturable defense" concept even though the exact numbers do
## not come from the books.
class_name PointDefenseMount

const MissileState = preload("res://simulation/missile_state.gd")

var max_engagement_range_m: float = 20_000.0    # ASSUMPTION: shorter-ranged than a counter-missile intercept (which closes actively); PD is a fixed-mount beam weapon.
var reaction_time_s: float = 1.5                 # ASSUMPTION: time a contact must be tracked before PD can engage it.
var recharge_time_s: float = 0.75                # ASSUMPTION: rapid-fire compared to a main energy mount.
var hits_required_to_kill: int = 2               # ASSUMPTION: a single laser hit is not automatically a kill (missile body is small/tough/maneuvering).
var condition: float = 1.0                       # 1.0 = fully functional; synced each tick from POINT_DEFENSE subsystem condition (§25, see SimulationWorld._sync_subsystem_driven_conditions()).

var cooldown_remaining_s: float = 0.0
var _tracking_target = null       # the MissileState currently being engaged, if any
var _tracking_time_s: float = 0.0
var _hits_scored: int = 0

func tick_cooldown(dt: float) -> void:
	if cooldown_remaining_s > 0.0:
		cooldown_remaining_s = maxf(0.0, cooldown_remaining_s - dt)

func is_ready() -> bool:
	return cooldown_remaining_s <= 0.0 and condition > 0.0

## Resets engagement state, e.g. when a missile is destroyed by another
## defense layer or leaves range -- PD must reacquire (reaction_time_s
## again) rather than retaining a free instant shot on a new contact.
func _reset_tracking() -> void:
	_tracking_target = null
	_tracking_time_s = 0.0
	_hits_scored = 0
