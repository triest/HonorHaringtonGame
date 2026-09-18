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
## correctness fix, not just a new feature: `SimulationWorld`'s earlier
## placeholder PD target-selection scanned `world.missiles` by TRUE
## position/identity, which was itself a "cheat vision" violation of §26
## -- this module replaces that with contact-based selection.
##
## HONEST SCOPE: this is deliberately the SIMPLEST tactical layer that
## satisfies "select targets" from the §26 checklist for PD and weapons --
## nearest usable contact, deterministic (no RNG, §43), ties broken by
## Dictionary iteration order.
##
## Second slice (this pass) adds a first "respond to damage"/"retreat"/
## "disengage" rule: `is_critically_damaged()` + `select_retreat_vector_world()`.
## Still NOT implemented: threat WEIGHTING beyond nearest-contact (salvo
## size, time-to-impact, ship value), formation management, maneuvering/
## distance selection independent of retreat, missile launch decisions,
## "respond to destroyed ships"/"reform formations" -- all still-open
## items from the §26 checklist, honestly left for later passes (see
## ASSUMPTIONS.md).
class_name TacticalAI

const MissileState = preload("res://simulation/missile_state.gd")
const ContactState = preload("res://simulation/contact_state.gd")

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
