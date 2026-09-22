# Honorverse dev state (updated every pass)
Phase: §56.1 vertical slice (fast visible-result mode)
Checklist:
  [x] 1. Camera (OrbitCamera, scripts/orbit_camera.gd)
  [~] 2. Placeholder ship geometry (hull+wedge done; sidewall panels done; canon shapes/materials explicitly OUT of scope for this slice)
  [~] 3. Weapon-fire visualization (energy/missile) -- rendering capability DONE (SimulationWorld.last_tick_weapon_shots + scripts/weapon_fx.gd energy beams + missile marker sync, unit-tested); NOT YET visible live because the demo scene in main.gd assigns no teams so nothing fires yet -- that wiring is explicitly item 6's job, not re-done here <- CURRENT (verify once item 6 wires teams/AI that beams/markers actually appear)
  [ ] 4. Minimal HUD (subsystems/targets/contacts state)
  [ ] 5. Order input wiring (hotkeys + Input Map -> FormationOrder/IndividualOrder/ShipCombatDirective)
  [ ] 6. Hardcoded 1v1/2v2 scenario vs TacticalAI
  [ ] 7. Win/lose screen (existing §63 destruction state)
  [ ] 8. Draft Windows export
Next concrete step: item 6 -- wire a hardcoded 1v1 (or 2v2) scenario into main.gd: world.set_team() for both sides, TacticalAI controlling the opposing side, weapon_mounts/missile_tubes actually registered on `world` (not just main.gd's own separate `mounts` dict as today) so _resolve_weapons_ai/_resolve_missile_launch_ai actually fire -- this is also what will make item 3's weapon_fx visually testable live for the first time. Keep it the SIMPLEST hardcoded setup that gets ships shooting at each other; do not build the general Scenario system (Milestone 13, still out of scope).
Blockers: none currently.
Last pass finished: 2026-09-22T21:23Z (weapon_fx + last_tick_weapon_shots, commit pending push this pass)
