extends RefCounted
## ShipSubsystems
##
## ТЗ §25 Damage: container holding one SubsystemState per SubsystemType
## for a ship. This is the canonical, complete-per-ТЗ subsystem damage
## model going forward.
##
## HONEST STATUS (not overclaiming "done"): several subsystems already had
## their OWN pre-existing condition fields before this Milestone, added
## ad hoc as each earlier system was built -- `ShipPhysicsState.propulsion_condition`
## / `.compensator_condition` (§9/§18), `WeaponMount.condition` (§17),
## `PointDefenseMount.condition` (§22), `ShipDefenseState`'s sidewall
## conditions (§9). Those are NOT yet unified with this container (that
## would mean rewriting those modules to read from here instead of their
## own fields -- a real refactor, deliberately deferred rather than
## rushed to avoid destabilizing already-tested systems).
##
## Consumers now wired (7 of 11 SubsystemType entries actually change
## ship capability, up from 3 as of the previous pass):
## SENSORS (SensorResolution degrades detection range), PROPULSION and
## MANEUVERING (ShipPhysicsState.effective_max_acceleration), and, as of
## this pass, WEAPONS/POINT_DEFENSE/MISSILE_SYSTEMS (SimulationWorld.
## _sync_subsystem_driven_conditions() syncs condition into WeaponMount/
## PointDefenseMount/MissileTube's own `condition` field every tick, so a
## damaged WEAPONS subsystem now proportionally reduces weapon damage
## output and a fully disabled one stops the mount firing; POINT_DEFENSE/
## MISSILE_SYSTEMS combine a hard on/off at `condition <= 0.0` (mount/tube
## stops engaging entirely) WITH a continuous falloff at any condition in
## between -- `PointDefenseMount.effective_reaction_time_s()` /
## `effective_recharge_time_s()` / `effective_engagement_range_m()` and
## `MissileTube.effective_reload_time_s()` / `effective_max_range_m()`
## slow reaction/cycle time and shrink effective range as condition drops,
## closing the "hard on/off only" gap logged in a previous pass) and
## COUNTER_MISSILE_SYSTEMS (SimulationWorld._resolve_counter_missile_intercepts
## scales CounterMissileResolution's effective kill radius by the
## launching ship's own condition; see that module's class doc for the
## INTERPRETATION this represents).
##
## As of this pass, COMMUNICATIONS also has a real consumer: degraded
## COMMUNICATIONS condition lengthens
## `SimulationWorld._individual_order_transmission_delay_s()`, the delay
## a `transmit_*`-issued individual order/designation takes to reach this
## ship (§25's own worked example, "communications damage -> degraded
## command/reporting", and §31 "account for communication limitations"
## for individual orders -- see ARCHITECTURE.md/ASSUMPTIONS.md for the
## §25/§31 transmission-delay entry). Note this only affects orders
## issued through the new `transmit_*` API; the pre-existing immediate
## API (`issue_individual_order_now`/`set_ship_target`/etc.) is
## untouched and still instant, by design -- see that entry.
##
## Still with NO consumer wired (3 of 11, genuinely blocked on systems
## that do not exist yet, not merely unwired): POWER (no live
## power-budget model), STRUCTURAL_INTEGRITY (HullState is still the
## single-scalar §58 placeholder pool ТЗ §59 requires replacing before
## Definition of Done -- wiring STRUCTURAL_INTEGRITY meaningfully needs
## that replacement first, not a quick shim), and DEFENSIVE_SYSTEMS (no
## canonical mapping found distinguishing it from the wedge/sidewall
## systems ShipDefenseState already models separately -- what this
## subsystem would additionally represent is UNKNOWN, not merely
## unimplemented). See ASSUMPTIONS.md for the full record.
class_name ShipSubsystems

const SubsystemType = preload("res://simulation/subsystem_type.gd")
const SubsystemState = preload("res://simulation/subsystem_state.gd")

var _states: Dictionary = {}

func _init() -> void:
	for type_value in SubsystemType.Type.values():
		_states[type_value] = SubsystemState.new()

func get_state(type: int) -> SubsystemState:
	return _states[type]

func get_condition(type: int) -> float:
	return _states[type].integrity

func is_disabled(type: int) -> bool:
	return _states[type].is_disabled()

func apply_damage(type: int, amount: float) -> void:
	_states[type].apply_damage(amount)

func repair(type: int, amount: float) -> void:
	_states[type].repair(amount)
