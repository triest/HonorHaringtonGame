extends RefCounted
## MissileTube
##
## ТЗ §26 "launch missiles" data holder: one ship-mounted missile tube/
## launcher with a finite magazine and a cycle (reload) time between
## successive launches. This is deliberately the simplest possible
## representation that lets Tactical AI (§26) make a real launch
## decision instead of only firing already-mounted weapons.
##
## HONEST STATUS / ASSUMPTIONS (no canonical figures found for magazine
## size, launch cycle time, or tube engagement range per ship class --
## see ASSUMPTIONS.md): all defaults below are ENGINEERING PLACEHOLDERS,
## not canon, and are NOT tied to any specific Honorverse ship class.
## `max_range_m` intentionally defaults far beyond the energy-weapon
## `WeaponData.max_range_m` scale, consistent with missiles being the
## long-range strike weapon in the setting (CANON: capital missiles
## engage at ranges energy weapons cannot reach), but the exact figure is
## still an ASSUMPTION.
##
## ТЗ §25 Subsystem Damage: `condition` is synced every tick from the
## launching ship's own MISSILE_SYSTEMS subsystem condition by
## `SimulationWorld._sync_subsystem_driven_conditions()` -- same pattern
## as WeaponMount.condition/PointDefenseMount.condition, closing one of
## the "8 of 11 subsystems without a damage consumer" gaps recorded in
## ASSUMPTIONS.md/ship_subsystems.gd. A ship with no ShipSubsystems
## (subsystems == null) never touches this field, so it stays at its
## default 1.0 -- identical to pre-§25 behavior.
class_name MissileTube

var ammo_count: int = 10  ## ASSUMPTION magazine size placeholder.
var reload_time_s: float = 5.0  ## ASSUMPTION: minimum time between successive launches from this one tube.
var max_range_m: float = 60_000_000.0  ## ASSUMPTION engagement range placeholder (60,000 km).
var condition: float = 1.0  ## 1.0 = fully functional; degraded by MISSILE_SYSTEMS subsystem damage (§25).

## Ready immediately at scenario start (no artificial initial cooldown) --
## same convention as WeaponMount/PointDefenseMount's cooldown fields.
var time_since_last_launch_s: float = INF

## ТЗ §25 continuous subsystem-damage falloff, same model/rationale as
## PointDefenseMount's effective_* getters (see that class's doc comment):
## cycle time scales inversely with `condition` (a damaged launcher takes
## proportionally longer between shots), effective range scales linearly
## with `condition` (degraded guidance-uplink/targeting reach). Closes the
## "hard on/off, not continuous" half of the honest §25 gap recorded for
## POINT_DEFENSE/MISSILE_SYSTEMS in ASSUMPTIONS.md. `condition <= 0.0` is
## unreachable through these getters in the live sim -- `is_ready()`
## already hard-gates a spent tube at `condition <= 0.0` -- but each
## getter still floors `condition` defensively. INTERPRETATION, not canon.
const _MIN_CONDITION_FOR_TIMING: float = 0.05

func effective_reload_time_s() -> float:
	return reload_time_s / maxf(condition, _MIN_CONDITION_FOR_TIMING)

func effective_max_range_m() -> float:
	return max_range_m * maxf(condition, 0.0)

func is_ready() -> bool:
	return ammo_count > 0 and time_since_last_launch_s >= effective_reload_time_s() and condition > 0.0

func advance(dt: float) -> void:
	time_since_last_launch_s += dt

## Caller (SimulationWorld) is responsible for actually constructing and
## registering the MissileState; this only tracks the tube's own
## ammo/cooldown bookkeeping once a launch has been decided.
func mark_launched() -> void:
	ammo_count -= 1
	time_since_last_launch_s = 0.0
