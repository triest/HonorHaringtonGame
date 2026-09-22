extends RefCounted
## TacticalAI
##
## ТЗ §26 Tactical AI: "AI must be tactical, not a collection of scripted
## animations... AI must use the same basic information restrictions as
## the player. No cheat vision."
##
## First slice implemented here: threat evaluation + target SELECTION for
## point defense and for ship-to-ship weapons fire. Every decision reads
## ONLY from a `SensorContact` (estimated_position, state) -- never from
## a target's real `.position`/`.velocity` directly, exactly like the
## player would be limited to their own sensor picture. This is also a
## correctness fix, and new feature: `SimulationWorld`'s earlier
## placeholder PD target-selection scanned `world.missiles` by TRUE
## position/identity, which was itself a "cheat vision" violation of §26
## -- this module replaces that with contact-based selection.
##
## HONEST SCOPE: this is deliberately the SIMPLEST tactical layer that
## satisfies "select targets" from the §26 checklist for PD and weapons --
## nearest usable contact, deterministic (no RNG, §43), ties broken by
## Dictionary iteration order.
##
## Second slice adds a first "respond to damage"/"retreat"/"disengage"
## rule: `is_critically_damaged()` + `select_retreat_vector_world()`.
## This pass adds `compute_crossing_t_maneuver()` (§41.1): a desired
## world velocity + facing that puts this ship on the enemy's bow/stern
## axis with this ship's own beam toward the enemy. Still NOT
## implemented: threat WEIGHTING beyond nearest-contact, formation-level
## (wall) crossing-the-T as a formation order, intercept-time solving
## against a maneuvering target (same idealization as §34.2).
class_name TacticalAI

const MissileState = preload("res://simulation/missile_state.gd")
const ContactState = preload("res://simulation/contact_state.gd")
const AttackGeometry = preload("res://simulation/attack_geometry.gd")

## ASSUMPTION (engineering, not canon): time horizon over which the
## crossing-the-T translator tries to close a lateral offset onto the
## enemy's bow/stern axis. No Honorverse source gives a "how fast to
## slide onto the T" number; 10 s is long enough that a ship uses a
## fraction of its rated acceleration rather than slamming to the
## geometric point in one tick.
const CROSSING_T_HORIZON_S: float = 10.0

static func _is_usable(state: int) -> bool:
	return (
		state == ContactState.Type.DETECTED
		or state == ContactState.Type.TRACKED
		or state == ContactState.Type.ESTIMATED
	)

## Point defense target selection (§26 "select targets" / "use point
## defense"): among `contacts` (a ShipSubsystems-owner-agnostic
## Dictionary[contact_key -> SensorContact], as stored in
## `SimulationWorld.sensor_contacts[ship_id]`), find the nearest usable
## contact whose underlying object is an active MissileState currently
## targeting `ship`. Distance is measured from the SHIP's own (known)
## position to the CONTACT's estimated position -- not the missile's true
## position -- so a stale/dead-reckoned contact is judged on what the
## ship's sensors actually believe, same as a human player would see.
##
## Returns {"missile": MissileState|null, "contact": SensorContact|null}.
static func select_pd_target(ship, contacts: Dictionary) -> Dictionary:
	var best_missile = null
	var best_contact = null
	var best_distance: float = INF

	for contact_id in contacts.keys():
		var contact = contacts[contact_id]
		if not _is_usable(contact.state):
			continue
		var candidate = contact.target
		if not (candidate is MissileState):
			continue
		if not candidate.is_active():
			continue
		if candidate.target != ship:
			continue

		var distance: float = ship.position.distance_to(contact.estimated_position)
		if distance < best_distance:
			best_distance = distance
			best_missile = candidate
			best_contact = contact

	return {"missile": best_missile, "contact": best_contact}

## Weapon target selection (§26 "evaluate threats" / "select targets" /
## "use weapons"): among `contacts`, find the nearest usable contact
## whose underlying object is one of `hostile_ship_ids` (a caller-supplied
## list -- team/hostility assignment is NOT this module's job, see
## SimulationWorld.teams). Returns {"ship_id": String|null, "ship":
## ShipPhysicsState|null, "contact": SensorContact|null}.
static func select_weapon_target(ship, contacts: Dictionary, hostile_ship_ids: Array) -> Dictionary:
	var best_ship_id = null
	var best_ship = null
	var best_contact = null
	var best_distance: float = INF

	for contact_id in contacts.keys():
		if not hostile_ship_ids.has(contact_id):
			continue
		var contact = contacts[contact_id]
		if not _is_usable(contact.state):
			continue

		var distance: float = ship.position.distance_to(contact.estimated_position)
		if distance < best_distance:
			best_distance = distance
			best_ship_id = contact_id
			best_ship = contact.target
			best_contact = contact

	return {"ship_id": best_ship_id, "ship": best_ship, "contact": best_contact}


## §30 "target"/"target priority" -- directed target selection
## (Milestone 11, second slice). Same return shape as
## select_weapon_target ({"ship_id", "ship", "contact"}, all null on
## failure), but picks `target_ship_id` specifically -- a commander's
## standing designation (see ShipCombatDirective) -- instead of nearest-
## hostile, honoring the exact same "no cheat vision" contact-usability
## rule (must still be a USABLE contact, not merely "still exists" --
## an order to fire on a contact this ship's own sensors have lost track
## of is not something any crew could execute on). Returns the all-null
## shape when `target_ship_id` is empty, not in `hostile_ship_ids`, or
## not currently a usable contact -- this function makes NO fallback
## decision itself; SimulationWorld._resolve_weapon_target decides
## whether to fall back to automatic nearest-hostile selection.
static func select_directed_weapon_target(ship, contacts: Dictionary, hostile_ship_ids: Array, target_ship_id: String) -> Dictionary:
	if target_ship_id == "" or not hostile_ship_ids.has(target_ship_id):
		return {"ship_id": null, "ship": null, "contact": null}
	var contact = contacts.get(target_ship_id)
	if contact == null or not _is_usable(contact.state):
		return {"ship_id": null, "ship": null, "contact": null}
	return {"ship_id": target_ship_id, "ship": contact.target, "contact": contact}


## §26 "respond to damage" / "retreat" / "disengage" -- first slice.
##
## ASSUMPTION (no canonical figure found for a Honorverse "break off"
## threshold): a ship is treated as critically damaged, and should
## disengage/retreat, once its HullState integrity fraction drops to or
## below `threshold` (default 0.3 = 30%). This is a deliberately simple,
## single-scalar rule riding on HullState (itself already documented as a
## TEMPORARY SIMPLIFICATION pending full subsystem-based damage, see
## hull_state.gd) -- NOT a canonical retreat doctrine. `hull` may be null
## (undefended/no-hull-tracked ships never retreat under this rule).
static func is_critically_damaged(hull, threshold: float = 0.3) -> bool:
	if hull == null:
		return false
	if hull.max_integrity <= 0.0:
		return false
	return (hull.integrity / hull.max_integrity) <= threshold

## Retreat direction, in WORLD space, for `ship` given its own sensor
## `contacts` and a caller-supplied `hostile_ship_ids` list (same
## contract as `select_weapon_target` -- hostility bookkeeping is not
## this module's job). Reads ONLY `SensorContact.estimated_position` for
## every usable hostile contact -- never a hostile's true `.position` --
## same "no cheat vision" rule as target selection. Averages the
## away-from-each-hostile unit vectors (not just the nearest one, unlike
## target selection) so a ship boxed in by several hostiles retreats
## roughly away from the group rather than fixating on one.
##
## Returns Vector3.ZERO when there are no usable hostile contacts to
## retreat from (caller should leave `commanded_thrust_local` unchanged
## in that case, not zero it -- see SimulationWorld._resolve_damage_response).
static func select_retreat_vector_world(ship, contacts: Dictionary, hostile_ship_ids: Array) -> Vector3:
	var away_sum := Vector3.ZERO
	var count := 0

	for contact_id in contacts.keys():
		if not hostile_ship_ids.has(contact_id):
			continue
		var contact = contacts[contact_id]
		if not _is_usable(contact.state):
			continue

		var to_hostile: Vector3 = contact.estimated_position - ship.position
		if to_hostile.length_squared() <= 0.0:
			continue
		away_sum -= to_hostile.normalized()
		count += 1

	if count == 0:
		return Vector3.ZERO
	return away_sum.normalized()

## §33 Formation Leader, "destroyed or incapacitated". A formation guide
## (or any candidate successor -- this is used for both) is considered
## LOST if it no longer physically exists in the simulation's `ships`
## (destroyed and removed, see SimulationWorld.remove_ship) OR its
## tracked HullState (if any) is fully destroyed OR it is critically
## damaged by the SAME threshold already used for §26 "respond to
## damage"/retreat (`is_critically_damaged`) -- deliberately reusing one
## "too hurt to function normally" definition rather than inventing a
## second, unrelated one for command purposes. A ship with no HullState
## tracked (`hulls.get()` returns null) is treated as never incapacitated
## by this rule, same convention as `is_critically_damaged` itself.
static func is_guide_lost(guide_ship_id: String, ships: Dictionary, hulls: Dictionary, critical_threshold: float = 0.3) -> bool:
	if guide_ship_id == "" or not ships.has(guide_ship_id):
		return true
	var hull = hulls.get(guide_ship_id)
	if hull == null:
		return false
	if hull.is_destroyed():
		return true
	return is_critically_damaged(hull, critical_threshold)

## §33 step 1, "determine successor". Walks `formation.succession_order`
## (or, if that is empty, `formation.member_offsets.keys()` in their
## existing deterministic order -- see FormationState class docs) and
## returns the first candidate that is not the formation's own current
## (lost) guide, and is itself not lost by `is_guide_lost` above. Returns
## "" if nobody currently in the formation is fit to lead -- callers must
## handle that case explicitly (§33: "do not magically transfer
## information unavailable to subordinate ships" -- there being no valid
## successor is a real, honestly-representable outcome, not an error).
## Reads ONLY `ships`/`hulls` true state, never SensorContact -- this is
## intra-formation bookkeeping between FRIENDLY ships assumed to share a
## tactical link (see FormationState class docs "not a 'no cheat vision'
## situation"), not detection of a potentially hostile contact under §26.
## Does NOT mutate `formation` -- the caller applies the actual transfer.
static func select_formation_successor(formation, ships: Dictionary, hulls: Dictionary, critical_threshold: float = 0.3) -> String:
	var candidates: Array = formation.succession_order
	if candidates.is_empty():
		candidates = formation.member_offsets.keys()

	for candidate_id in candidates:
		if candidate_id == formation.guide_ship_id:
			continue
		if not ships.has(candidate_id):
			continue
		if is_guide_lost(candidate_id, ships, hulls, critical_threshold):
			continue
		return candidate_id

	return ""


## §34.1 Doubling -- formation-coordinated target selection (first
## slice), used by SimulationWorld._resolve_formation_target_assignment
## in place of plain `select_weapon_target` for ships whose formation is
## running a coordinated assignment pass this tick. Same underlying
## information as `select_weapon_target` (only USABLE contacts among
## `hostile_ids`, same "no cheat vision" contract, distance measured to
## the CONTACT's estimated position) PLUS two additional, deliberately
## simple coordination signals the caller maintains across this same
## formation's members for this tick:
##
## * `hulls` (ship_id -> HullState, may be null/missing per id): a
##   candidate whose tracked hull integrity is at or below
##   `critical_fraction` (same threshold `is_critically_damaged` already
##   uses for a ship's OWN retreat decision -- deliberately reused rather
##   than inventing a second "how damaged is too damaged" number, see
##   ASSUMPTIONS.md) is treated as already effectively neutralized for
##   further concentration purposes. A candidate with no tracked hull is
##   never treated as neutralized this way (nothing to judge it against).
## * `assigned_counts` (target_ship_id -> int, how many OTHER formation-
##   mates were already assigned to each candidate earlier THIS tick): a
##   candidate already claimed by `max_useful_attackers` or more
##   formation-mates is treated as already sufficiently committed.
##   ASSUMPTION (no canon "how many ships' fire usefully concentrates on
##   one hull" figure exists): max_useful_attackers defaults to 2. This is
##   the concrete mechanism behind §34.1's "don't treat 'already 4
##   ships shooting at it' and 'nobody shooting at it' as equally good" --
##   it does not attempt to model real expected damage/kill probability
##   (weapon damage resolution is also probabilistic per mount/range/
##   wedge, see weapon_resolution.gd, far too complex to duplicate here
##   as a look-ahead heuristic), just a simple, deterministic commitment
##   cap.
##
## Selection is tiered, so a ship is NEVER left without a target purely
## because every visible hostile happens to be neutralized/over-
## committed (honest scope note, same convention this module uses
## everywhere else -- no fallback decision is ever "give up"):
##   Tier 0 -- not neutralized, not over-committed;
##   Tier 1 -- not neutralized, over-committed (used only if Tier 0 empty);
##   Tier 2 -- neutralized (used only if Tiers 0 and 1 are both empty).
## Within a tier, nearest CONTACT distance wins, same tie-break rule as
## `select_weapon_target`. With `assigned_counts` empty and no candidate
## neutralized, this degenerates EXACTLY to `select_weapon_target`'s
## result -- a formation of one (or a member with no formation-mates
## assigned anything yet this tick) behaves identically to before this
## pass existed.
##
## Returns the same {"ship_id", "ship", "contact"} shape as
## `select_weapon_target` (all null if no usable hostile contact exists
## at all).
static func select_formation_target_for_member(ship, contacts: Dictionary, hostile_ids: Array, hulls: Dictionary, assigned_counts: Dictionary, max_useful_attackers: int = 2, critical_fraction: float = 0.3) -> Dictionary:
	var best_contact_id_by_tier: Array = [null, null, null]
	var best_distance_by_tier: Array = [INF, INF, INF]

	for contact_id in contacts.keys():
		if not hostile_id_list_has_contact(hostile_ids, contact_id):
			continue
		var contact = contacts[contact_id]
		if not _is_usable(contact.state):
			continue

		var neutralized := false
		var hull = hulls.get(contact_id)
		if hull != null and hull.max_integrity > 0.0 and (hull.integrity / hull.max_integrity) <= critical_fraction:
			neutralized = true
		var over_committed: bool = assigned_counts.get(contact_id, 0) >= max_useful_attackers

		var tier: int = 0
		if neutralized:
			tier = 2
		elif over_committed:
			tier = 1

		var distance: float = ship.position.distance_to(contact.estimated_position)
		if distance < best_distance_by_tier[tier]:
			best_distance_by_tier[tier] = distance
			best_contact_id_by_tier[tier] = contact_id

	for tier in range(3):
		var chosen_id = best_contact_id_by_tier[tier]
		if chosen_id != null:
			var chosen_contact = contacts[chosen_id]
			return {"ship_id": chosen_id, "ship": chosen_contact.target, "contact": chosen_contact}

	return {"ship_id": null, "ship": null, "contact": null}

static func hostile_id_list_has_contact(list: Array, id: String) -> bool:
	return list.has(id)

## §41.1 Crossing the T.
##
## Pure geometry from THIS ship's sensor picture (estimated position /
## velocity / orientation -- never the hostile's true `.orientation`).
## Returns:
##   desired_velocity_world -- world-space velocity to command
##   desired_facing_world   -- world-space bow direction to turn toward
## Both ZERO when there is no usable hostile contact.
##
## Objective, using the existing AttackGeometry sectors:
##   enemy's sector toward us -> BOW or STERN (chase weapons only,
##     bow/stern wedge gap exposed)
##   our sector toward them  -> PORT or STARBOARD (broadside live)
## That means sitting on the enemy's bow/stern AXIS and presenting
## OUR beam to them, not sliding onto their flank (their flank is
## where THEIR broadside lives -- the opposite of crossing the T).
static func compute_crossing_t_maneuver(ship, contacts: Dictionary, hostile_ship_ids: Array) -> Dictionary:
	var empty := {
		"desired_velocity_world": Vector3.ZERO,
		"desired_facing_world": Vector3.ZERO,
	}
	var target_data = select_weapon_target(ship, contacts, hostile_ship_ids)
	var contact = target_data["contact"]
	if contact == null:
		return empty

	var target_pos: Vector3 = contact.estimated_position
	var from_enemy: Vector3 = ship.position - target_pos
	if from_enemy.length_squared() <= 0.0:
		return empty

	var range_m: float = from_enemy.length()
	var los: Vector3 = -from_enemy / range_m  # ship -> target

	var enemy_bow: Vector3 = contact.estimated_orientation * Vector3.FORWARD
	if enemy_bow.length_squared() <= 0.000001:
		enemy_bow = Vector3.FORWARD
	else:
		enemy_bow = enemy_bow.normalized()

	# Prefer remaining on whichever end of the bow-stern axis we already
	# sit on; if we are on the beam (along ~ 0), prefer the BOW -- that
	# is the classic crossing-ahead geometry.
	var along: float = from_enemy.dot(enemy_bow)
	var axial_sign: float = 1.0 if along >= 0.0 else -1.0
	var desired_pos: Vector3 = target_pos + enemy_bow * (axial_sign * range_m)

	var max_accel: float = ship.effective_max_acceleration()
	var to_desired: Vector3 = desired_pos - ship.position
	var close_vel := Vector3.ZERO
	if to_desired.length_squared() > 1.0:
		var close_speed: float = minf(to_desired.length() / CROSSING_T_HORIZON_S, max_accel * CROSSING_T_HORIZON_S)
		close_vel = to_desired.normalized() * close_speed

	# Bar of the T: a heading perpendicular to LOS so the target sits
	# on our beam. Sign follows current bow so we do not reverse for
	# no reason.
	var bar: Vector3 = los.cross(Vector3.UP)
	if bar.length_squared() <= 0.000001:
		bar = los.cross(Vector3.RIGHT)
	if bar.length_squared() <= 0.000001:
		return empty
	bar = bar.normalized()
	var current_fwd: Vector3 = ship.orientation * Vector3.FORWARD
	if current_fwd.dot(bar) < 0.0:
		bar = -bar

	var lateral: Vector3 = from_enemy - enemy_bow * along
	var on_axis: bool = lateral.length() <= range_m * 0.25
	var desired_vel: Vector3 = contact.estimated_velocity + close_vel
	if on_axis:
		desired_vel += bar * (max_accel * CROSSING_T_HORIZON_S)

	return {
		"desired_velocity_world": desired_vel,
		"desired_facing_world": bar,
	}

## Convenience for callers that only need the velocity half.
static func select_crossing_t_velocity(ship, contacts: Dictionary, hostile_ship_ids: Array) -> Vector3:
	return compute_crossing_t_maneuver(ship, contacts, hostile_ship_ids)["desired_velocity_world"]
