# CLOUD.md - Honorverse 3D Tactical Combat Simulator Core Specs

## 1. PROJECT MISSION
Create a standalone Windows 3D tactical combat simulator set in the Honor Harrington / Honorverse universe. The final application MUST NOT require external AI APIs or cloud architectures at runtime.

## 1.1. CANON FIRST, LOGIC WHERE CANON IS SILENT (AGENTS.md §4.1)
Every mechanic checks canon first (books > official materials > confirmed reference > careful interpretation > fan material as supplementary only -- never authoritative for geometry). Only when canon genuinely has nothing to say: fill the gap with real physics/engineering logic and, for tactics/doctrine specifically, real historical naval warfare (see §61/§62) -- not arbitrary invention, and never presented as CANON. Still classify as INTERPRETATION/ASSUMPTION, still logged in CANON_RULES.md/ASSUMPTIONS.md with the reasoning.

## 1.2. NO HEALTH BARS (AGENTS.md §25.1)
Damage is shown as combat capability, not an abstract HP bar: which subsystems are damaged/disabled, what that concretely costs (fewer working weapons, degraded tracking, slower turns, garbled comms), plus visible hull/structural damage and eventual wreck state (§63). A single scalar pool (current `HullState`) is a TEMPORARY dev placeholder only, never the permanent or player-facing model -- must be replaced by the full per-subsystem model before §59 Definition of Done. Per-subsystem numeric readouts (e.g. "SENSORS: 40%") are fine; one undifferentiated "ship health" bar is not.

## 1.3. SAME RULES FOR EVERY SHIP (AGENTS.md §43.1)
Physics and damage run through the exact same code/formulas for every ship regardless of side (player/AI/allied/hostile/neutral) -- team/ownership is targeting-only bookkeeping (§26), never an input to accel/mass/inertia or to damage resolution. No hidden per-side multipliers; any deliberate difficulty/balance choice belongs in scenario/ship-database DATA (e.g. a weaker OPFOR loadout), not in special-cased code.

## 1.4. CONCRETE REFERENCE NUMBERS (AGENTS.md §8.1)
* Sourced example specs (Honorverse Wiki, verified 2026-09-19), for
  seeding §8/§48, NOT universal constants:
  Medusa-class SD: 1383m, 8,554,750t, 402.3G (502.8G max), 26 tubes/
  13 large mounts/15 grasers/54 capital-missile launchers/52 PD
  broadside, 492 pods (Medusa-B: 2000 pods, crew 1025).
  Agamemnon-class: 815m, 1,750,750t, 554.1G@80% (5.434 km/s^2), 10
  graser/30 Cherenkov/30 PD broadside, 360 pods of Mk16 DDM.
  Mark 13 missile: 88,000G, 12m, 78t, Mk86 warhead 15MT.
  Mark 23 MDM: 96,000G max/48,000G sustained, 15M km full-thrust
  envelope / 63M km half-accel envelope, 0.83c terminal, 94t.
  Mark 31 counter-missile: 130,000G, 75s burn, 3.6M km range.
  Grav lance: 100,000 km max range (disaligns wedge, overloads
  sidewall). Energy torpedo: 300,000 km. Graser torpedo: ~100x laser
  warhead power, ~3s effect duration.
  UNKNOWN/not found this pass: direct-fire laser/graser mount
  range-damage numbers, autocannon specs, several compensator ratings
  and crew counts -- see ASSUMPTIONS.md.


## 1.5. SHIP TYPE HIERARCHY AND NAMED CLASSES, RMN + HAVEN (AGENTS.md §8.2)
* CANON tonnage bands (ascending): LAC 11-21k t; Frigate (no band
  given); Destroyer 65-80k t (Roland-class RMN reached CL-equivalent
  mass by 2nd Havenite War -- band is traditional/era reference, not
  fixed); Light Cruiser 90-150k t avg; Heavy Cruiser 160-350k t;
  Battlecruiser 780k t-2.5M t (smallest formal capital ship); Dreadnought
  5-6.5M t; Superdreadnought 7-9M t (both = ship of the wall).
* RMN named classes: Medusa (SD), Agamemnon -- full specs in §1.4.
* Haven (People's Navy/RHN) named classes: Sultan-class BC (859,250t,
  707m, 489.2G); Warlord-class BC (918,750t, 723m, 389.9G/487.4G max);
  Nevada-class (type/specs not pulled -- UNKNOWN).
* Grayson named classes (types only, no specs pulled yet): Raoul
  Courvosier (BC), Jason Alvarez (CA), Nathan (CL), Jackalope (DN LAC
  carrier), Manticore's Gift (SD), Benjamin the Great (SD), Honor
  Harrington (pod-layer SD), Ararat (pre-Alliance DD).
* NOT implemented: no ShipClass/database records exist in code yet for
  any of these -- reference material to seed §8/§48 from.

## 1.6. PER-CLASS ARMAMENT (AGENTS.md §8.3)
* Sultan-class (Haven BC) armament: 46 missile tubes (3 chase/20 per
  broadside), 4 capital lasers, 12 anti-ship lasers, 12 grasers, 40
  counter-missile tubes, 36 anti-missile lasers, 1 tractor beam.
* Warlord-class (Haven BC) armament: 64 missile tubes total
  (broadside 26M/6L/6G/16CM/12PD, chase 6M/2G/6CM/6PD), 12 lasers, 16
  grasers, 44 counter-missile tubes, 36 PD clusters.
* Per user direction: individual ship NAMES don't matter for this ТЗ,
  only CLASSES and their characteristics -- no named-hull roster kept.
* NOT implemented in code yet -- seed reference material.

## 1.7. LOGICAL EXTRAPOLATION METHOD FOR MISSING CHARACTERISTICS (AGENTS.md §8.4)
* Extends §1.1 (canon-first/logic principle) with a concrete method
  for a class/weapon field §1.4-1.6 doesn't cover, instead of a round
  invented number. Every result stays ASSUMPTION, with its anchor(s)
  and method recorded next to the value.
* Anchor: closest already-sourced class of the SAME type band (§1.5)
  AND same era/tech generation -- not just any class of that type ever.
* Mass: prefer a same-era analog's number over the §1.5 band's raw
  midpoint.
* Acceleration: within ONE era, scales roughly inversely with mass
  (same compensator strength). CROSS-ERA WARNING (shown by our own
  data): Sultan (859,250t/489.2G), Warlord (918,750t/389.9G),
  Agamemnon (1,750,750t/554.1G) do NOT fit one inverse curve across
  each other -- compensator tech itself improves between eras. Only
  valid within one same-era anchor; if era is uncertain, mark UNKNOWN
  instead.
* Weapon mount counts: scale with hull mass/length via the closest
  same-era anchor's count-per-ton/-meter ratio, rounded to an even,
  broadside-symmetric integer.
* Weapon PERFORMANCE (missile accel/range/warhead, energy-mount
  range/power) is NEVER per-ship-extrapolated -- it belongs to the
  weapon's own §1.4 record, inherited unchanged by any ship mounting
  it. Only mount count/magazine capacity is per-hull.
* Every extrapolated value records its anchor + step used, not just
  the number. Disagreeing independent estimates -> UNKNOWN, not an
  average or arbitrary pick.
## 1.8. TOP PRIORITY: FASTEST PATH TO PLAYABLE (AGENTS.md §56.1)
* User priority (2026-09-22): a playable vertical slice now outranks
  Milestones 12-17 and further simulation-layer polish. Simulation
  core (Milestones 1-11) is strong and well-tested but there is ZERO
  visual/input/UI layer -- no camera, ship meshes, controls, or HUD.
* Minimum scope: camera + placeholder ship geometry (correct wedge/
  sidewall geometry, NOT canon-accurate hull art yet -- §7's
  documented-interpretation allowance, logged as a placeholder to
  replace later); simple weapon-fire visuals (rendering only, per
  §42); minimal §25.1-compliant HUD (subsystem condition readout,
  target, sensor contacts) pulled straight from existing state; input
  wired directly to existing `FormationOrder`/`IndividualOrder`/
  `ShipCombatDirective` APIs; ONE hardcoded starting scenario (not
  Milestone 13's general loader); simple win/lose using existing §63
  destruction state; a rough Windows export.
* Explicitly deferred until the slice works: hull art, sound, menu
  polish, the general Scenario system/editor, Replay (already
  deprioritized), large-fleet performance, further command-echelon UI,
  and any NEW simulation mechanic -- this is about surfacing what
  already exists, not adding backend features.

## 1.9. UI/CONTROL CORRECTION -- TACTICAL PLOT, MOUSE-FIRST, CANON SCALE (AGENTS.md §56.2, user decision 2026-09-23)
* REOPENS/PARTIALLY SUPERSEDES §56.1 items 1/4/5 after the user live-
  tested the first exported build: ships nearly touching, hotkey-heavy
  control, plain corner-text HUD -- rejected as looking like a generic
  space dogfight, not the Honorverse. Explicit genre statement: this
  is a TACTICAL STRATEGY game, command-and-control from a plot, not a
  piloted dogfight.
* Mouse-first control: click contacts on the plot to select, click/
  drag to set course or designate targets, mouse for weapons-free/hold
  and other `ShipCombatDirective` orders. Hotkeys stay as secondary
  accelerators, not the primary path. Existing orbit-camera mouse
  control (drag/wheel) is kept.
* Canon-scale distances: engagement ranges must read as hundreds of
  thousands to low millions of km, matching §8.1's already-logged
  numbers (energy weapons ~3,600,000 km effective range; missile
  powered envelopes 15,000,000-63,000,000 km) -- NOT a literal 1:1
  scaled scene (unrenderable), but a documented INTERPRETATION-tagged
  symbolic/icon convention where displayed range numbers and missile
  flight-time pacing are canon-scale even though ship icons are drawn
  at a fixed readable size.
* Tactical plot required: a top-down/God's-eye display (2D is fine)
  showing every sensor contact as an IFF-colored icon with a velocity
  vector, plus every live missile as its own distinctly-marked track
  -- separate from and in addition to the existing subsystem-condition
  text HUD, not a replacement for it.
* Definition of done requires a LIVE user confirmation, not headless
  tests alone -- §56.1 was reported closed on headless evidence only
  and failed the user's actual first run.

## 2. EXTENDED MECHANICS SPECIFICATION

### 2.1. IMPELLER WEDGE & SIDEWALLS
* **Wedge Geometry:** Modeled as two infinite planar barriers projected above and below the ship's longitudinal hull axis. The intersection of an incoming vector with these planes results in a 100% mitigation event.
* **Sidewall Mechanics:** Modeled as dual curved lateral zones (Port/Starboard). Incoming attacks are calculated against the sidewall's status and angle of incidence.

### 2.2. WEAPONS AND MISSILE WARHEADS
* **Laserheads (CORRECTED, verified against Honorverse Wiki 2026-09-18 --
  see AGENTS.md §21 for the full sequence and citations):** the missile
  does NOT simply "stop tracking and blast" as a single event. On reaching
  final attack bearing, lasing rods EJECT from bays on the missile's
  sides and independently maneuver (own thrusters/sensors) to a position
  roughly 100m ahead of the warhead, between it and the target. A ring of
  gravity generators behind the warhead then focuses the nuclear
  detonation's x-ray pulse into a Gaussian beam aimed at the rods, which
  each emit an independently-aimed gamma/X-ray laser at the target's
  exposed vector. Rod count/type is warhead-specific (CANON examples:
  Mark 23 capital warhead = 6x 500cm x 40cm rods aimed at one target;
  Mark 13 submunition warhead = 6x independently-targetable Mark 73
  submunitions, each able to engage a different point). Effective damage
  radius after detonation: ~25,000 km (longer rods = less beam
  divergence = greater stand-off range) -- this is CANON but is the
  post-detonation area-effect radius, NOT the missile's detonation
  trigger range, which remains UNKNOWN and is currently a game-design
  ASSUMPTION (see ASSUMPTIONS.md).
* **Energy Weapon Mounts:** Lasers and Graser mounts located along the ship's broadside and chaser zones, limited by weapon charging cycles and exact firing arcs.
* **Reference missile performance (CANON examples for SPECIFIC classes,
  NOT universal constants -- ТЗ §11 forbids one MAX_SPEED/acceleration for
  all missiles):**
  * Mark 23 MDM (multi-drive missile): full-acceleration mode ~96,000 G,
    powered envelope ~15,000,000 km; half-acceleration mode ~48,000 G,
    powered envelope ~63,000,000 km (both CANON, Honorverse Wiki
    "Manticoran missile technology", verified 2026-09-18 -- see
    CANON_RULES.md "Девятая сверка"). Full accel = faster/shorter reach,
    half accel = slower/longer reach -- same throttling trade-off already
    modeled by `MissileState.set_throttle()`.
  * Mark 31 counter-missile: ~130,000 G for ~75 seconds, effective range
    just under 3,600,000 km.
  * Viper anti-LAC missile: ~130,000 G, "fire and forget" with an
    enhanced onboard AI seeker (no ship-side telemetry link required).
  * Apollo fire-control concept: one Mark 23-E control missile (FTL
    telemetry link instead of a warhead) coordinates up to 8 standard
    Mark 23 MDMs in real time from the firing ship; if the control
    missile is destroyed, the salvo continues autonomously on its last
    guidance solution. Implementation consequence: this argues for a
    data-driven "salvo/control-node" concept distinct from a single
    missile's own MissileState, to be designed when Milestone work
    reaches multi-missile salvos -- not required for the current MVP
    single-missile implementation.

### 2.2.1. MISSILE FLIGHT PHYSICS (CORRECTED, verified against Honorverse
Wiki 2026-09-18 -- see AGENTS.md §18.1 for full detail/citations):
* **Three-phase flight, not a single constant burn:** (1) powered flight
  at a configured acceleration for a configured burn time -- CANON
  example 46,000 G / ~180s / "over six million km" powered range; (2)
  drives are throttleable -- acceleration can be stepped down to extend
  powered burn time/range, at the cost of giving the target more warning
  time; (3) ballistic coast once the drive burns out -- no further
  maneuver, "very easy to avoid" at that point.
* **Multi-drive staging (MDM):** independent drive sections fire
  sequentially or coast between stages to extend total powered envelope.
  Manticoran designs: up to 3 stages. Havenite designs: limited to 2
  stages (capacitor-ring bulk). NOT YET IMPLEMENTED in the codebase.
* **Missile spin:** missiles spin in flight specifically to deny
  point-defense a stable non-wedge-protected firing angle (same
  top/bottom wedge protection principle as ships, at missile scale).
* **Launch clearance:** missiles must clear the LAUNCHING SHIP's own
  wedge before activating their own drive/wedge -- this is the reason
  mass-driver launch tubes exist.

### 2.2.2. COUNTER-MISSILES
* **Kill mechanic:** mutual impeller-wedge overlap destroys BOTH the
  counter-missile and the incoming missile it intercepts -- NOT a
  collision or a warhead detonation (counter-missiles carry no warhead).
  Distinct from Point Defense (§2.2.3), which is a ship-mounted
  laser-cluster weapon requiring multiple hits.
* **Typical engagement ranges:** ~1-4 million km (CANON example range,
  Honorverse Wiki "Manticoran missile technology", verified 2026-09-18).
* Implementation: `CounterMissileResolution.check_intercept()`,
  `INTERCEPT_KILL_RADIUS_M` (ASSUMPTION placeholder, see ASSUMPTIONS.md).

### 2.2.3. POINT DEFENSE
* Ship-mounted laser-cluster defense, layered ALONGSIDE (not instead of)
  counter-missiles and ECM (CANON: "thickened the defensive envelope").
  Reaction time before engagement, multiple hits required to kill, own
  recharge cycle -- a large enough salvo can saturate a single mount.
  Implementation: `PointDefenseMount`/`PointDefenseResolution`.

### 2.3. SENSORS AND ELECTRONIC WARFARE (ECM)
* **Detection Pipeline:** Active Wedge Radiance -> Gravitic Sensor Threshold -> Track Identification.
* **ECM Interference:** Decreases the convergence accuracy of incoming missile tracking paths and introduces vector variance in the opponent's sensor contacts.

### 2.4. SUBSYSTEM DAMAGE MATRIX
* **Hit Allocation:** Attacks penetrating defensive layers hit discrete internal cells corresponding to internal weapon rooms, engine rings, or sensor arrays.

### 2.5. FORMATION COMMAND & AI ARCHITECTURE
* **Spatial Hierarchies:** Task forces move as unified coordinate matrices. Individual overrides occur when local threats force defensive maneuvers away from the primary group vector.

### 2.6. REPLAY & SCENARIO ENGINE
* **State Snapshotting:** The system records initial constraints, periodic state vector deltas, and timestamped player/AI orders to reconstruct the entire 3D map accurately during playback.
* **PRIORITY NOTE (user decision, 2026-09-22): Replay is DEPRIORITIZED
  for now.** Milestone 12 is paused -- current code
  (`replay_log.gd`) is command/event recording only, no snapshots/
  seek/UI, and stays that way until Milestones 13-17 (scenarios, 2v2/
  squadron, large-fleet, scenario editor, final build) are addressed.
  See AGENTS.md §56 priority note.

### 2.7. COMBAT PHILOSOPHY — "NELSON IN A SKIRT" (AGENTS.md §61)
* **Design mandate, not a mechanic in itself:** Honor Harrington is a deliberate spiritual successor to Horatio Nelson; the simulator should feel like Nelsonian naval warfare translated into space, not arcade dogfighting or perfect-information RTS.
* Decisive-engagement mindset; geometry (position/closing vectors/aspect) as the "weather gauge"; wall-of-battle formation fighting as the primary combat mode; concentration of force (crossing the T, doubling, local superiority) as a first-class viable tactic; bold decisions under incomplete information rewarded over perfect-knowledge caution; player as commander (observe -> decide -> order -> monitor), not pilot; subordinate initiative under loss of comms without the force dissolving into chaos.
* Practical steer for open §26/Milestone 10 gaps (formation command, threat weighting beyond nearest-contact, squadron coordination): resolve them in this direction when canon/ТЗ are silent, and mark such choices as design-mandate-driven, not canon.

### 2.8. INERTIA, SHIP MASS & TIME SCALE (AGENTS.md §62)
* **Mass by class (CANON, Honorverse Wiki):** DD ~65-80k t, CL ~90-150k t, CA ~160-350k t, BC ~780k-2.5M t, BB ~2-4M t, SD ~7-9M t. Dispatch boats up to ~800G (minimal mass/load -- explains the acceleration spread across classes).
* **Inertial compensator (CANON):** gravity generators alone cap ship acceleration at ~51G without an active wedge (150G without a wedge reduces to only ~5G felt); pre-war doctrine capped usage at 80% of max compensator effectiveness, abandoned for more aggressive profiles during the First Manticoran-Havenite War; compensator failure under acceleration is instantly lethal to the crew.
* **Known implementation gap:** `mass_kg` exists on ship state but is NOT yet wired into the acceleration formula (still a direct per-ship `max_acceleration_mps2`, not F=ma) -- open item, not yet done.
* **Time scale:** fixed 60Hz simulation tick (engineering choice, not canon) vs. presentational playback-speed multiplier (pause/1x..100x, §44) -- the multiplier never changes physics. Scope is tactical real-time combat only, not interstellar hyper-transit time compression.

### 2.9. SHIP DESTRUCTION, WRECKS & PROGRESSIVE DAMAGE (AGENTS.md §63)
* **Wrecks, not despawns:** a destroyed ship becomes an inert wreck (keeps position/velocity/orientation, obeys inertia, stays visible/trackable) -- it is never simply deleted. Current implementation gap: `_resolve_ship_destruction()` still calls `remove_ship()`, fully deleting the ship -- known, documented, open (see ASSUMPTIONS.md).
* **Retention is a separate decision from destruction:** a wreck persists at least through the rest of its engagement; any later pruning (time/distance/scenario-boundary based) must be its own explicit mechanic, not a side effect of the death code path. Exact retention policy is UNKNOWN/ASSUMPTION.
* **Damage must matter before death:** subsystem damage (§25) must produce continuously degrading combat effectiveness -- reduced offense, defense, sensing, coordination, maneuver -- well before hull integrity hits zero, up to a "mission-killed" state (still alive, effectively unable to fight). Not just a smaller number while fighting identically.

### 2.10. CONCRETE §61 TACTICS: CROSSING THE T, DOUBLING, TOT, SUCCESSION-WINDOW INITIATIVE (AGENTS.md §33.1/§34.1/§34.2/§41.1)
* **Crossing the T (§41.1):** maneuver so the enemy's sector toward us is BOW/STERN (only bow/stern-arc weapons live, plus its 15° bow/stern wedge gap exposed) while our sector toward them stays PORT/STARBOARD (full broadside live). IMPLEMENTED (first slice, 2026-09-22): `TacticalAI.compute_crossing_t_maneuver()` + `SimulationWorld._resolve_crossing_t_maneuver()`/`_steer_toward_world_facing()`, applied to any ship with no more specific §30 order and not a station-kept formation member. Honest first-slice limits: pure bow/stern-axis geometry, not a true intercept-vector solve against a maneuvering target (straight-line closing over a fixed `CROSSING_T_HORIZON_S` = 10 s, same idealization as §34.2); single-ship only, no formation-level ("wall") crossing-the-T order yet. See CHANGELOG.md/ASSUMPTIONS.md for the full boundary list.
* **Doubling (§34.1):** formation-level target assignment should deliberately mass fire on one chosen enemy unit at a time (weighing expected marginal contribution per ship-target pairing), not let every ship independently converge on its own nearest contact. IMPLEMENTED (first slice) -- `TacticalAI.select_formation_target_for_member` / `SimulationWorld._resolve_formation_target_assignment`.
* **Missile time-on-target (§34.2):** stagger launch so simultaneous arrival saturates target PD's reaction-time window, instead of a ragged trickle. IMPLEMENTED (first slice) -- `SimulationWorld._resolve_missile_tot_coordination`, scoped to formation-mates sharing a §34.1-assigned target, straight-line boost-coast flight-time estimate (ignores target motion, see ASSUMPTIONS.md).
* **Succession-window initiative (§33.1):** between leader loss and successor takeover (`COMMAND_TRANSFER_DELAY_S`, distinct from light-speed comm lag), a subordinate ship holds vector, keeps engaging its last assigned target, keeps covering a neighbor -- never goes idle. IMPLEMENTED -- see CHANGELOG.md 2026-09-19.
### 2.11. FORMATION MUTUAL DEFENSIVE COVERAGE (AGENTS.md §22.1)
* PD/wedge coverage has real directional gaps (bow/stern acute angle,
  §41.1); close formation lets a neighboring ship's PD/wedge cover an
  arc the first ship's own systems can't reach -- part of why "wall of
  battle" (§61) is the doctrine. Breaking formation (ship lost, out of
  station, straggling, dispersed order) genuinely loses that coverage
  and exposes the uncovered gap to exploitation.
* **CANON, directly source-confirmed (2026-09-19):** Baen's free
  Prologue sample of *Field of Dishonor* (HH4),
  baen.com/Chapters/0743435745/0743435745___0.htm -- fetched and
  checked directly. Depicts a reconstruction of the First Battle of
  Hancock (underlying event: HH3 *The Short Victorious War*). Honor
  Harrington's "Formation Reno" order tightens station and makes the
  formation's missile defenses measurably more effective; Pavel
  Young's panicked "all ships scatter" order then causes "chaos" in
  the "fine-meshed, interlocking network" of the task group's missile
  defenses; returning ships "socket back into" the point defense net.
* Classification: CANON for both the event and the "single
  interlocking network" framing of the mechanism itself.
  INTERPRETATION only for the per-ship DIRECTIONAL gap/coverage model
  (§41.1/§33.1/§61) this ТЗ uses to implement that confirmed
  principle as concrete geometry.
* IMPLEMENTED (first slice, 2026-09-22), wedge half only:
  `SimulationWorld._formation_bow_stern_coverage()` + `ShipDefenseState.
  resolve_attack()`'s new `FORMATION_COVERED` path -- a covering,
  cohesive-formation neighbor near a ship's bow/stern axis attenuates
  (0.5 ASSUMPTION multiplier) an otherwise-fully-UNPROTECTED bow/stern
  hit. NOT implemented: PD is still fully omnidirectional (no firing-arc
  model at all, so PD has no coverage concept yet); the raised-sidewall
  acute-angle-bypass case is untouched by formation coverage; AI/
  targeting does not yet prefer uncovered gaps. See AGENTS.md §22.1 /
  ASSUMPTIONS.md / CHANGELOG.md (2026-09-22) for the full picture.

