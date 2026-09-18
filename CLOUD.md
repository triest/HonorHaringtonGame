# CLOUD.md - Honorverse 3D Tactical Combat Simulator Core Specs

## 1. PROJECT MISSION
Create a standalone Windows 3D tactical combat simulator set in the Honor Harrington / Honorverse universe. The final application MUST NOT require external AI APIs or cloud architectures at runtime.

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
  * Mark 23 MDM (multi-drive missile), half-acceleration mode:
    ~48,000 G, powered envelope ~63,000,000 km.
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

### 2.3. SENSORS AND ELECTRONIC WARFARE (ECM)
* **Detection Pipeline:** Active Wedge Radiance -> Gravitic Sensor Threshold -> Track Identification.
* **ECM Interference:** Decreases the convergence accuracy of incoming missile tracking paths and introduces vector variance in the opponent's sensor contacts.

### 2.4. SUBSYSTEM DAMAGE MATRIX
* **Hit Allocation:** Attacks penetrating defensive layers hit discrete internal cells corresponding to internal weapon rooms, engine rings, or sensor arrays.

### 2.5. FORMATION COMMAND & AI ARCHITECTURE
* **Spatial Hierarchies:** Task forces move as unified coordinate matrices. Individual overrides occur when local threats force defensive maneuvers away from the primary group vector.

### 2.6. REPLAY & SCENARIO ENGINE
* **State Snapshotting:** The system records initial constraints, periodic state vector deltas, and timestamped player/AI orders to reconstruct the entire 3D map accurately during playback.
