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
## Dictionary iteration order. It does NOT yet do threat WEIGHTING (salvo
## size, time-to-impact, ship value), formation management, maneuvering,
## distance selection, missile launch decisions, damage/loss response, or
## retreat/disengage logic -- all still-open items from the §26 checklist,
## honestly left for later passes (see ASSUMPTIONS.md).
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
