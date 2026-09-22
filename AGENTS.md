# CLOUD.md

# Honorverse 3D Tactical Combat Simulator

## 1. Project Mission

Create a standalone Windows 3D tactical combat simulator set in the Honor Harrington / Honorverse universe.

The project is intended to become a finished, playable local application rather than a prototype, mockup, technical demonstration, or collection of disconnected systems.

Claude is a development tool only.

The final application MUST NOT require Claude, an LLM, AI API, cloud service, external game server, API key, or internet connection at runtime.

The application must run locally on Windows.

---

# 2. Core Design Goals

The simulator must provide:

* true 3D simulation;
* inertial high-speed space combat;
* Honorverse-style impeller wedge;
* sidewalls;
* missile combat;
* counter-missiles;
* laserheads;
* point defense;
* sensors;
* ECM;
* subsystem damage;
* tactical AI;
* formation command;
* individual ship command;
* command hierarchy;
* limited battlefield information;
* replay;
* scenarios;
* deterministic simulation;
* data-driven ships and weapons.

The game should feel like commanding a military space force, not like flying an arcade space fighter.

---

# 3. Runtime Independence

The finished application must NOT require:

* Claude;
* ChatGPT;
* any LLM;
* generative AI;
* cloud AI;
* external AI APIs;
* external game servers;
* account authentication;
* matchmaking;
* internet access;
* API keys.

Any development-time AI tooling is irrelevant to runtime.

---

# 4. Honorverse Canon

The simulator must follow the Honorverse books as closely as practical.

Every important rule must be classified as one of:

* `CANON`
* `INTERPRETATION`
* `ASSUMPTION`
* `UNKNOWN`

Do not present an assumption as canon.

If exact information is unavailable:

1. do not invent false precision;
2. make the value configurable where appropriate;
3. document the decision in `ASSUMPTIONS.md`;
4. explain why the assumption was required.

Source priority:

1. Honorverse books;
2. official David Weber / publisher materials;
3. confirmed reference material;
4. careful interpretation;
5. fan-created material only as supplementary reference.

Fan art is NOT authoritative evidence for ship geometry.

The project must maintain:

* `CANON_RULES.md`
* `ASSUMPTIONS.md`

## 4.1 Where canon is silent: logic and common sense, not invention

Canon comes first, always. Every mechanic MUST be checked against the
source priority above before anything else happens to it. This
subsection governs only the case canon genuinely does not cover --
it is not a license to skip checking canon first, and it does not
downgrade anything canon already settles.

When the books, official materials, and careful interpretation
(source priority levels 1-4 above) genuinely have nothing to say about
a specific numeric value or mechanic, the gap MUST be filled with
real-world engineering, physical, and tactical logic -- not an
arbitrary "whatever feels right" number, and not silently left broken
or stubbed. Concretely:

* start from real physics (Newtonian mechanics, F=ma, conservation of
  momentum/energy, thermodynamics where relevant) and real engineering
  constraints (structural limits, power/heat budgets, sensor physics)
  -- the Honorverse setting is itself built to be physically grounded
  hard SF, so "what would actually be true/necessary given the physics
  already established" is a legitimate, non-arbitrary source of
  numbers, not a cop-out;
* for tactics, doctrine, and command structure specifically, ground
  the choice in real historical naval warfare -- AGENTS.md §61
  ("Combat Philosophy -- Nelson in a Skirt") and §62 (mass/inertia/
  compensator canon) are the existing worked examples of this: Honor
  Harrington is explicitly written as Age-of-Sail warfare translated to
  space, so filling a genuine tactical/doctrinal gap by reasoning from
  historical squadron combat is following the setting's own internal
  logic, not deviating from it;
* prefer the simplest mechanism that is still internally consistent
  with everything already established (existing CANON facts,
  previously logged ASSUMPTIONs, the current codebase's existing
  conventions) over a novel, unrelated invention -- do not solve the
  same kind of gap two different ways in two different places;
* still classify the result honestly as `INTERPRETATION` or
  `ASSUMPTION` per §4 above (never as `CANON`), still document it in
  `ASSUMPTIONS.md`/`CANON_RULES.md` with the reasoning that produced
  it, and still make it configurable where §4 already requires that --
  this subsection changes HOW a gap gets filled, not the classification/
  documentation discipline §4 already mandates.

The standing rule stays: never invent false precision, and never
present a logic-filled gap as if it were a confirmed book fact.

---

# 5. Required Documentation

The repository must contain:

```text
README.md
BUILD.md
ARCHITECTURE.md
CANON_RULES.md
ASSUMPTIONS.md
CHANGELOG.md
CLOUD.md
AGENTS.md
```

Documentation must be updated when implementation changes materially.

---

# 6. True 3D Simulation

3D is mandatory.

The simulation itself must operate in full:

```text
X
Y
Z
```

There must NOT be a hidden 2D combat simulation rendered in 3D.

Full 3D entities include:

* ships;
* missiles;
* counter-missiles;
* laserheads;
* sensor contacts;
* weapon trajectories;
* defensive systems;
* impeller wedges;
* tactical vectors.

Simulation state must support:

* position;
* velocity;
* acceleration;
* orientation;
* angular velocity;
* angular acceleration;
* relative position;
* relative velocity;
* distance;
* closure velocity.

Use `Vector3`/equivalent for spatial state and `Quaternion`/equivalent for orientation where appropriate.

---

# 7. Ship Representation

Ships must correspond to Honorverse ships rather than generic science-fiction vessels.

Ship implementation should reflect, where canon information exists:

* hull shape;
* proportions;
* dimensions;
* mass;
* impeller wedge geometry;
* sidewall geometry;
* weapon placement;
* missile tubes;
* point-defense systems;
* sensors;
* communications;
* defensive systems;
* propulsion;
* technological era;
* faction-specific differences.

Textual descriptions from the books take priority over fan art.

Unknown visual details may be interpreted, but the interpretation must be documented.

---

# 8. Ship Database

Ship data must be data-driven.

A ship class should be able to define:

* canonical name;
* class;
* faction;
* era;
* dimensions;
* mass;
* acceleration;
* propulsion;
* compensator;
* wedge;
* sidewalls;
* armament;
* missile tubes;
* missile capacity;
* counter-missile capability;
* point-defense;
* sensors;
* ECM;
* communications;
* subsystem layout;
* visual description;
* canonical references;
* confidence/uncertainty.

Do not invent exact numerical values when the source does not establish them.

---

## 8.1 Concrete canon reference data -- example ship classes, missiles, energy weapons

§8 says "do not invent exact numerical values" but does not itself supply
any -- this subsection gives concrete, sourced example values to seed the
Ship/Weapon/Missile Database (§8/§48) with, verified 2026-09-19 against
Honorverse Wiki technical/class pages (WebFetch, factual numeric data
extracted -- not book prose, no verbatim passages reproduced). These are
EXAMPLES for specific classes/generations, not universal constants --
same caveat as §21.2's missile rod-count/warhead-type table. Honorverse
technology (missile generations, compensator strength, warhead yield)
canonically improves across the book series' internal timeline; a real
implementation needs numbers tagged by ERA, not one fixed table.

**Ship classes (CANON, source: Honorverse Wiki class articles):**

* Medusa-class (superdreadnought): length 1383 m; mass 8,554,750 tons;
  acceleration 402.3 G (502.8 G maximum); broadside armament 26 missile
  tubes / 13 large energy mounts / 15 grasers / 54 capital missile
  launchers / 52 point-defense; fore 9 missile tubes / 4 large energy
  mounts / 5 grasers / 18 capital missile launchers / 22 point-defense;
  aft 6 missile tubes / 4 large energy mounts / 5 grasers / 14 capital
  missile launchers / 20 point-defense; missile pod capacity 492.
  Medusa-B refit: missile pod capacity 2000; crew 1,025 (incl. 125
  Marines); energy battery 50 grasers. Compensator rating and Medusa-B
  length/mass/acceleration: UNKNOWN (not given in the source article).
* Agamemnon-class (battlecruiser or similar wall unit -- class role not
  re-verified this pass): mass 1,750,750 tons; length 815 m; beam 118 m;
  draught 110 m; acceleration at 80% compensator load 554.1 G (5.434
  km/s^2); broadside 10 graser mounts / 30 Cherenkov missiles / 30
  point-defense; fore 4 graser mounts / 12 point-defense; aft 4 missile
  pods / 4 graser mounts / 12 point-defense; magazine capacity 360 pods
  of Mk 16 DDMs. Crew and compensator rating: UNKNOWN (not given).

**Missiles (CANON, source: Honorverse Wiki "Manticoran missile
technology"):**

* Mark 13 (single-drive, laser head, heavy-cruiser/battlecruiser era):
  88,000 G acceleration; 12 m long; 78 tons; Mark 86 warhead, 15
  megaton hydrogen-fusion yield.
* Mark 19: introduced 1870 PD -- first laser-head-armed impeller-drive
  missile (era marker, not a full spec set found this pass).
* Mark 23 MDM (multi-drive missile, three-stage, wall-of-battle
  standard): 96,000 G maximum acceleration; 48,000 G sustained
  ("half") acceleration; 15,000,000 km powered envelope at full
  thrust; 63,000,000 km powered envelope at half acceleration; 0.83c
  terminal velocity; 94 tons mass; warhead option 6 lasing rods (500cm
  x 40cm), capital-weight configuration.
* Mark 25 MDM: four-stage system-defense variant (role marker; detailed
  spec set not found this pass -- UNKNOWN).
* Mark 30 (RMN standard counter-missile until ~1920 PD): spec set not
  found this pass beyond its role/service-life dates -- UNKNOWN.
* Mark 31 (counter-missile, successor to Mark 30): 130,000 G
  acceleration; 75 second burn time; 3,600,000 km effective range from
  rest.
* Viper (Grayson anti-LAC missile): 130,000 G acceleration; 3,600,000
  km powered envelope; 75 second endurance.
* Warheads: Mark 16 Mod E 15 megaton yield (cruiser weight); Mark 16
  Mod G 40 megaton yield (improved gravity-lensing variant); Mistletoe
  (offensive drone) 500 megaton option.

**Energy weapons (CANON, source: Honorverse Wiki "Space Weapons
Technology"):**

* Grav lance: 100,000 km maximum range under optimal conditions --
  gravitic weapon that disaligns the target's impeller wedge to
  overload its sidewall (a distinct effect from a direct-damage
  weapon, see §21.25's existing sidewall-damage-character CANON entry).
* Energy torpedo: up to 300,000 km effective range -- self-sustaining
  plasma mass traveling at near-light speed.
* Graser torpedo: warhead power roughly 100x a standard laser warhead;
  graser effect duration ~3 seconds vs. milliseconds for a laser
  warhead.
* Laser (direct-fire mount) and graser (direct-fire mount, distinct
  from graser TORPEDO above) numeric range/damage figures: UNKNOWN --
  not given as concrete numbers in the source article; §22 Point
  Defense and §17/§21 energy-mount rules should keep treating these as
  ASSUMPTION-tier placeholders (see PointDefenseMount's own documented
  ASSUMPTION constants) until a numeric source is found.
* Autocannon caliber, rate of fire, and any concrete damage/penetration
  figures for any energy or projectile weapon: UNKNOWN -- not found
  this pass for any weapon type.

**How to use this table:** seed §8 Ship Database / §48 Data-Driven
Design entries for a small number of NAMED example classes (Medusa,
Agamemnon, missile Marks above) with these exact numbers, tagged with
their source and era, rather than inventing round numbers. For any
class/weapon/missile NOT in this list, §8's own rule still applies --
do not invent exact numerical values; use logic/consistency with these
known reference points (§4.1) and mark the result ASSUMPTION, not
CANON. This table is a first pass, not exhaustive -- see ASSUMPTIONS.md
for what remains UNKNOWN and would need further sourcing.

---

## 8.2 Ship type hierarchy and named example classes -- Manticore and Haven

Extends §8.1 with the general type/tonnage hierarchy every ship class
sits in, plus a small set of named example classes on both sides of
the main Manticore-Haven conflict, sourced 2026-09-19 (Honorverse Wiki
"Ship Types" article, class articles, and the independent long-running
fan reference "Honorverse Ships List" (cs.cmu.edu/~tpope) -- factual
numeric/categorical data extracted, no book prose reproduced).

**CANON ship type hierarchy (by mass, ascending):**

* Light Attack Craft (LAC): 11,000-21,000 tons; intrasystem only,
  cannot enter hyperspace; traditional roles picket/customs.
* Frigate: smaller than a destroyer; picket/convoy-escort roles;
  increasingly obsolete by the late 1800s PD internal timeline.
* Destroyer (DD): traditionally 65,000-80,000 tons; picket/escort/
  reconnaissance. NOTE: the Manticoran Roland-class destroyer reached
  light-cruiser-equivalent mass by the Second [Havenite] War -- the
  tonnage BAND above is a traditional/earlier-era reference, not a
  hard rule for every era (consistent with §8.1's own era caveat).
* Light Cruiser (CL): 90,000-150,000 tons average; armed with grasers
  rather than lasers; reconnaissance/commerce protection/raiding.
* Heavy Cruiser (CA): 160,000-350,000 tons; independent picket duty,
  heavy commerce protection, capital-ship screening.
* Battlecruiser (BC): 780,000 tons to 2.5 million tons; smallest ship
  formally classed as a capital ship; commerce raiding, heavy
  screening, light task-group combat element.
* Dreadnought (DN): 5-6.5 million tons; ship of the wall; first-rate
  navies only.
* Superdreadnought (SD): 7-9 million tons; largest warships built;
  ship of the wall.

**Named example classes, Manticoran Royal Navy (RMN):**

* Medusa-class (SD) and Agamemnon-class -- full specs already in §8.1.
  Both consistent with the SD/wall-of-battle tonnage bands above
  (Agamemnon at 1,750,750 tons sits well above the general BC band,
  consistent with §8.1's note that these are specific,
  possibly-later-generation examples, not the type-average number).

**Named example classes, People's Republic of Haven (People's Navy /
later Republic of Haven Navy):**

* Sultan-class (battlecruiser): mass 859,250 tons; length 707 m;
  acceleration 489.2 G.
* Warlord-class (battlecruiser): mass 918,750 tons; length 723 m;
  acceleration 389.9 G (487.4 G maximum).
* Nevada-class: role/type not re-verified with full specs this pass --
  present in the source material as a named class; treat as UNKNOWN
  until specs are pulled.

**Named example classes, Grayson Space Navy (for later cross-faction
consistency, since §43.1 already requires identical physics/damage
rules for every side):**

* Raoul Courvosier-class (battlecruiser); Jason Alvarez-class (heavy
  cruiser); Nathan-class (light cruiser); Jackalope-class (dreadnought,
  LAC carrier); Manticore's Gift-class (superdreadnought); Benjamin
  the Great-class (superdreadnought); Honor Harrington-class (pod-layer
  superdreadnought); Ararat-class (pre-Alliance-era destroyer).
  Numeric specs (mass/length/acceleration) NOT pulled for any of these
  this pass -- names/types only, UNKNOWN otherwise.

**HONEST GAP:** none of the above (type hierarchy or named classes) is
wired into `project/simulation` as actual `ShipClass`/database data
yet -- §8's Ship Database is still not implemented as data-driven
records for named classes. This subsection is reference material to
seed that database from, not a description of anything currently in
the codebase. §8.1's caveat applies here too: tonnage bands are
type-average references, not universal per-ship constants, and any
class/faction not listed here still falls under §8's "do not invent
exact numbers" rule.


## 8.3 Per-class armament detail

Extends §8.1/§8.2 with full weapon-mount breakdowns for the two
Havenite classes already named in §8.2, sourced 2026-09-19 (Honorverse
Wiki class articles -- factual armament counts only, no book prose
reproduced). Individual named hulls are NOT tracked here -- per
explicit user direction, ship NAMES do not matter for this ТЗ, only
CLASSES and their characteristics. The Ship Database (§8/§48) needs
class records with full armament/performance data; it does not need a
roster of specific canon-named individual vessels. A player/AI/
scenario ship instance gets a scenario-assigned name/hull number like
any other data record, never a name presented as a canon vessel.

**Sultan-class (Haven, battlecruiser) armament:**
46 LMF-5(d) missile tubes (3 in chase armament, 20 per broadside); 4
L/130 capital-ship lasers; 12 L/118 anti-ship lasers; 12 G/125 grasers;
40 LMC-8(g) counter-missile tubes; 36 P/18x6 anti-missile lasers; 1
tractor beam. Magazine: 1,528 F17 impeller-drive missiles, 3,640 C2
counter-missiles, 10 LAD-15 tethered ECM decoys.

**Warlord-class (Haven, battlecruiser) armament:**
64 missile tubes total (broadside 26M/6L/6G/16CM/12PD, chase fore+aft
6M/2G/6CM/6PD); 12 lasers; 16 grasers; 44 counter-missile tubes; 36
point-defense clusters total.

**HONEST GAP:** none of the above is implemented as `ShipClass`
database records in `project/simulation` yet. See §8.1/§8.2 for the
same caveat -- this is seed reference material.


## 8.4 Logical extrapolation method for missing characteristics

Extends §4.1 ("logic where canon is silent") with a concrete,
repeatable METHOD for filling a class/weapon field that §8.1-8.3 (or a
future sourced addition) does not cover -- instead of picking an
arbitrary round number. Every value produced this way is ASSUMPTION,
never CANON, and must record which anchor(s) and ratio were used, so a
later real citation can replace it cleanly.

**Step 1 -- pick an anchor.** Prefer the closest already-sourced class
of the SAME type band (§8.2) and the SAME era/technology generation
(same rough missile Mark generation, same compensator generation --
not just "any battlecruiser ever mentioned"). If no same-type anchor
exists, use the nearest adjacent type band (one step up or down in
§8.2's hierarchy) and scale explicitly rather than borrowing its raw
numbers unchanged.

**Step 2 -- mass/dimensions.** If tonnage is missing, prefer a
same-era analog's number over the type band's raw midpoint (§8.2's
bands are wide and mix eras -- a specific analog is a better estimate
than the band center). If no analog exists, the band midpoint is the
fallback.

**Step 3 -- acceleration.** For ships sharing the SAME compensator
generation/era, acceleration scales roughly inversely with mass
(same compensator strength pushing more or less mass). Estimate:
`unknown_accel ~= anchor_accel * (anchor_mass / unknown_mass)`.
CROSS-ERA WARNING, demonstrated by data already in §8.1/§8.3: Sultan
(859,250t, 489.2G), Warlord (918,750t, 389.9G) and Agamemnon
(1,750,750t, 554.1G) do NOT follow one simple inverse curve across
each other -- because compensator technology itself improves between
these classes' eras (a later, more massive ship can still out-
accelerate an earlier, lighter one). This inverse-scaling estimate is
only valid WITHIN one same-era anchor, never across classes from
visibly different tech generations -- if the era of the unknown class
is itself uncertain, this method does not apply; mark UNKNOWN instead
of guessing an era.

**Step 4 -- weapon mount counts.** Missile-tube/energy-mount/PD counts
scale roughly with hull mass/length within the same type band. Use the
closest same-era anchor's own count-per-ton or count-per-meter ratio
(§8.1/§8.3 already give several real ratios to calibrate against) and
round to an even, broadside-symmetric integer -- real warships mount
weapons in symmetric banks/pairs, not odd scattered counts.

**Step 5 -- weapon PERFORMANCE is never per-ship-extrapolated.** A
missile Mark's acceleration/range/warhead, or an energy mount's
range/power, belongs to that WEAPON's own record (§8.1), inherited
unchanged by whichever ship class mounts it -- never re-derived from
the carrying ship's own mass or class. Only mount COUNT and magazine
CAPACITY are per-hull; weapon performance numbers are per-weapon-Mark.

**Step 6 -- record the method, don't just record the number.** Every
extrapolated field must note, next to the value: which anchor class(es)
it came from, which step above was used, and the ASSUMPTION tag. A
number with no recorded method is indistinguishable from an invented
one and violates §8's "do not invent exact numerical values" as much
as a number with no source at all.

**Step 7 -- when estimates disagree.** If two independently-derived
estimates for the same field diverge widely, do not average them or
pick arbitrarily -- widen to UNKNOWN and use a conservative
placeholder consistent with §4.1, flagged for a future real citation,
rather than manufacturing false precision.


# 9. Impeller Wedge

The impeller wedge is a fundamental part of both movement and combat.

It is NOT:

* a visual effect;
* a generic energy shield;
* an HP pool;
* a cosmetic mesh.

The wedge must be represented by real 3D geometry and orientation.

For the standard model, the wedge creates extremely strong / effectively impenetrable protected planes above and below the ship.

This leaves important attack directions associated with:

* bow;
* stern;
* port broadside;
* starboard broadside.

Broadside protection must additionally account for sidewalls.

The implementation must therefore distinguish:

```text
Wedge
    ↓
Top / Bottom protection

Ship geometry
    ↓
Bow / Stern

Sidewalls
    ↓
Broadside protection
```

Do NOT reduce all of this to `shieldHP`.

---

# 10. Wedge Orientation

The wedge is attached to the ship's orientation.

When ship orientation changes:

* wedge orientation changes;
* protected planes change;
* vulnerable directions change;
* weapon engagement geometry changes;
* tactical opportunities change.

For every attack, calculate the 3D attack vector relative to the target's orientation.

Determine whether the attack approaches from:

* top;
* bottom;
* bow;
* stern;
* port;
* starboard.

The combat system must then apply the appropriate rules.

---

# 11. Spacecraft Kinematics

Honorverse ships are high-performance inertial spacecraft.

The simulation must support:

* enormous acceleration;
* accelerations on the order of hundreds of g where appropriate;
* very high velocities;
* velocities representing significant fractions of the speed of light;
* enormous engagement distances;
* high relative velocities.

Exact values must be tied to the particular ship, technology, and available canonical information.

Do not use a universal arcade value such as:

```text
MAX_SPEED = 100
```

for all ships.

---

# 12. Inertial Movement

Movement must follow:

```text
Thrust
→ Acceleration
→ Velocity
→ Position
```

Stopping thrust must not automatically stop the ship.

The physical model must account for:

* mass;
* thrust;
* acceleration;
* current velocity;
* orientation;
* propulsion condition;
* compensator;
* damage.

Ships must not behave like aircraft in atmosphere.

---

# 13. Relative Velocity

Relative velocity is fundamental to combat.

For two objects:

```text
relativeVelocity = targetVelocity - attackerVelocity
```

Use relative velocity for:

* missile interception;
* target prediction;
* time-to-intercept;
* threat evaluation;
* evasive maneuvering;
* tactical AI;
* engagement analysis.

Distance alone is insufficient.

---

# 14. High-Speed Simulation

The simulation must support velocities representing significant fractions of `c`.

The implementation must be designed with:

* large velocities;
* large accelerations;
* large distances;
* floating-point precision;
* fixed timestep;
* deterministic calculation

in mind.

Use double precision where appropriate.

If origin rebasing or local reference frames become necessary, implement them rather than artificially shrinking the simulation scale.

---

# 15. Speed of Light

The speed of light is a fundamental physical constant.

The numerical implementation must not accidentally produce uncontrolled speeds above `c` because of integration errors.

If an approximation is required, document it in `ASSUMPTIONS.md`.

Do not introduce a fake arbitrary speed cap simply because the engine is easier to implement that way.

---

# 16. Sidewalls

Sidewalls are a real defensive system.

They must have:

* 3D geometry;
* orientation;
* operational state;
* damage state;
* interaction with incoming attacks.

Sidewalls must not simply be:

```text
shieldHP = 1000
```

They must interact with the direction and geometry of an attack.

---

# 17. Weapons

Weapons must be data-driven.

Possible systems include:

* energy weapons;
* missiles;
* laserheads;
* point-defense;
* counter-missiles.

Weapon resolution must consider:

* range;
* relative geometry;
* target orientation;
* wedge;
* sidewalls;
* sensors;
* tracking;
* ECM;
* damage;
* weapon state.

---

# 18. Missiles

Every missile is a real 3D simulation entity.

Minimum missile state:

```text
Position
Velocity
Acceleration
Orientation
Target
GuidanceState
SensorState
TerminalState
ECMState
Lifetime
WarheadState
```

A missile must NOT simply animate from launcher to target.

It must participate in simulation.

## 18.1. Flight physics (CANON, verified against Honorverse Wiki "Missile", 2026-09-18)

Missile flight is a THREE-PHASE model, not a single constant-acceleration
burn to a fixed range:

```text
1. POWERED FLIGHT -- drive burns at its configured acceleration for its
   configured burn time. A cited capital-ship example: 46,000 G for
   ~180 seconds, giving a powered flight RANGE (not just duration) of
   "over six million kilometers". (Sanity check: 0.5 * a * t^2 with
   a = 46,000 * 9.80665 m/s^2, t = 180s gives ~7.3 million km, consistent
   with the cited "over six million" -- this formula is a reasonable
   engineering check for any class's numbers, not itself a canon
   citation.)
2. THROTTLED / STEPPED-DOWN OPERATION -- drives are "frequently
   adjustable": acceleration can be reduced to extend powered burn time
   (trading peak acceleration for powered range/endurance), at the cost
   of giving the target more time to react and throw up defenses. This
   is a genuine tactical trade-off the AI/player should be able to make,
   not just a flavor detail.
3. BALLISTIC PHASE -- once the drive burns out (or is never re-lit),
   the missile coasts with NO further maneuver capability. It is "very
   easy to avoid a missile which could no longer maneuver" -- a
   ballistic missile past its powered range is a known, exploitable
   weakness, not a bug if a target evades it.
```

Multi-drive missiles (MDMs) additionally use STAGING: independent drive
sections that fire sequentially, optionally coasting between stages, to
extend the total powered envelope beyond what a single drive/single burn
could achieve. Manticoran designs used up to three stages; Havenite
designs were limited to two stages by capacitor-ring bulk. STAGING IS NOT
YET IMPLEMENTED in the codebase (single-burn model only) -- this is a
documented gap, not silently ignored; see ASSUMPTIONS.md.

Additional CANON flight details:
* A missile must activate its own wedge without interference from its
  launching ship's wedge -- this is WHY mass drivers/launch tubes exist:
  to fling the missile clear of the ship's own wedge before the missile's
  drive/wedge activates.
* Missiles SPIN in flight specifically to make it harder for point-defense
  lasers to get a clear shot past their own impeller wedge (a missile's
  wedge, like a ship's, blocks top/bottom axes -- spinning denies PD a
  stable non-wedge-protected angle). This is a concrete mechanical reason
  for missile spin, not a cosmetic animation choice, and should inform
  point-defense hit-chance modeling in that Milestone.
* Missiles carried externally in pods (not yet inside a launch sequence)
  are NOT protected by the carrying ship's armor, sidewalls, or wedge --
  they are vulnerable to "proximity kills" in that state. Relevant for a
  future Milestone modeling pod/magazine damage, not yet implemented.

---

# 19. Missile Guidance

Missile guidance must use actual simulation information.

It should account for:

* target position;
* estimated target position;
* target velocity;
* relative velocity;
* sensor update interval;
* tracking quality;
* ECM;
* target maneuver;
* loss of contact;
* terminal phase;
* countermeasures.

Do not implement guidance as merely:

```text
direction = target.position - missile.position
```

---

# 20. Counter-Missiles

Counter-missiles are real 3D entities.

They must:

* launch from ships;
* receive target information;
* track incoming missiles;
* calculate interception;
* maneuver;
* account for sensor information;
* interact with ECM;
* produce a real intercept result.

---

# 21. Laserheads

Laserheads must be represented as actual combat entities/events consistent with the implemented Honorverse model.

Do not treat a laserhead as an arbitrary generic sci-fi projectile without documenting the chosen interpretation.

## 21.1. Detonation sequence (CANON, verified against Honorverse Wiki "Missile" and "Manticoran missile technology", 2026-09-18)

A laserhead engagement is a distinct multi-step event, not an instant "missile touches ship -> damage" collision:

```text
1. Missile reaches final attack bearing (terminal course established)
2. Lasing rods EJECT from bays on the missile's sides
3. Each rod maneuvers independently (own thrusters + sensors) to align
   with the target -- rods are NOT rigidly fixed to the missile body
4. Rods settle roughly 100 meters ahead of the warhead, between the
   warhead and the target
5. A ring of gravity generators mounted behind the warhead activates
6. The ring's gravitic lenses focus the nuclear detonation into a
   Gaussian-shaped pulse aimed at the rods
7. The nuclear x-ray pulse pumps each rod, producing a focused
   gamma-ray/X-ray laser beam per rod
8. Each rod's beam is independently aimable at the target's exposed
   vector (this is the mechanism behind the "hits from a specific
   sector" resolution already implemented in ship_defense_state.gd /
   attack_geometry.gd)
```

Implementation consequence: a laserhead hit is not one instantaneous ray
from the missile's own position (the current MVP implementation in
`missile_resolution.gd` uses the missile's position directly as an
INTERPRETATION-level simplification, explicitly documented as such in
ASSUMPTIONS.md). A more accurate simulation would spawn the ejected rods
as short-lived entities ~100m ahead of the warhead and resolve each rod's
beam from ITS OWN position/aim vector. This refinement is not required for
the MVP milestone but should be tracked as a documented TODO, not silently
skipped.

## 21.2. Rod count and warhead types (CANON, examples from specific missile classes -- NOT universal constants, ТЗ §11/§48)

* Mark 23 capital missile warhead: 6x lasing rods, each 500cm x 40cm.
* Mark 13 submunition warhead: 6x Mark 73 independently targetable laser
  submunition vehicles (3m each) -- a DIFFERENT, distributed warhead
  design where each submunition can engage a distinct point/target rather
  than all rods focusing on one ship.

These are documented examples for specific missile classes/eras. Do not
hardcode "every missile has exactly 6 rods" -- rod count, rod dimensions,
and warhead type (single-target multi-rod vs multi-target submunition)
must be data-driven per missile class (ТЗ §8, §48), defaulting to UNKNOWN
where a specific class's data is not established.

## 21.25. Damage character vs. sidewalls (CANON, verified this session)

The laserhead beam is explicitly "more effective at penetrating sidewalls
than a pure fusion explosive." This is a CANON statement that laserheads
are NOT a generic damage number -- they have a specific advantage against
the sidewall defense layer specifically, as opposed to other warhead/
damage types (a pure kinetic or fusion warhead would be relatively WORSE
against sidewalls, by implication). Implementation consequence: when a
data-driven damage-type system is introduced (a later Milestone, per
§8/§48), sidewall attenuation in `ship_defense_state.gd` should vary by
attacker damage TYPE, not just by sidewall condition -- laserhead hits
should attenuate less through a sidewall than an equivalent-yield
non-laser warhead would. NOT YET IMPLEMENTED: the current
`ship_defense_state.gd` attenuation model is damage-type-agnostic (one
formula for all attackers). This is a documented, honest gap, not a
silent inaccuracy -- see ASSUMPTIONS.md.

## 21.3. Effective range (CANON)

Meaningful damage can be dealt to anything within 25,000 km of the
detonation point; longer rods produce less beam divergence and allow
greater stand-off engagement range. This is the AREA-EFFECT radius after
detonation, not the terminal detonation TRIGGER range (the distance at
which the missile decides to detonate) -- those are two different
parameters and must not be conflated in code. The current MVP's
`terminal_detonation_range_m` (50 km placeholder, see ASSUMPTIONS.md) is
the trigger range and remains UNKNOWN/ASSUMPTION; the 25,000 km figure is
CANON but describes a different thing and is not yet used anywhere in the
implementation.

## 21.4. What is still UNKNOWN (do not invent)

* Exact detonation trigger logic (closing rate threshold? fixed range?
  target-selected optimum range against known defenses?) -- not specified
  in the sources checked this session.
  * Beam energy/damage yield per rod, and how it should map to a
  simulation "damage" number.
* Whether/how ECM affects rod targeting accuracy specifically (as opposed
  to missile guidance in general, ТЗ §19/§24).

---

# 22. Point Defense

Point-defense systems must operate based on:

* sensor information;
* detection;
* tracking;
* weapon availability;
* geometry;
* range;
* reaction time;
* target state;
* ship damage;
* ECM/countermeasures where applicable.

---

## 22.1 Formation mutual defensive coverage -- PD/sidewall gaps are real, and breaking formation exposes them

Point defense and sidewall coverage are NOT uniform in every direction
for a single ship. This is already established elsewhere in this ТЗ:
§41.1 documents a concrete bow/stern acute-angle gap in a ship's own
wedge coverage (`ShipDefenseState.BOW_STERN_ACUTE_ANGLE_HALF_WIDTH_RAD`),
and §33.1 already uses the language of one ship "covering/screening a
neighboring ship with its own wedge/position." §22.1 makes that
mutual-coverage idea an explicit, general rule rather than something
implied only for the succession-window case:

* a single ship's own PD arcs and wedge/sidewall geometry have real
  gaps (bow/stern acute angle per §41.1, and any future PD mount
  firing-arc restriction, see the honest gap below) -- this is a
  physical consequence of geometry, not a balance knob;
* keeping close formation station lets a neighboring ship's PD fire
  and wedge/sidewall aspect cover an arc that the first ship's own
  systems cannot reach -- this is a large part of WHY "wall of
  battle" formation fighting (§61) is the doctrine instead of
  dispersing every ship independently: a formation is a mutual
  defensive structure, not merely a firing-line convenience;
* consequently, when formation integrity breaks -- a ship is
  destroyed, falls out of station, straggles, loses the guide (see
  §33/§33.1 for the succession case specifically), or is ordered into
  a dispersed/open formation -- the mutual coverage those neighbors
  were providing for each other's gaps is genuinely lost, not just
  cosmetically. A ship (or a formation position) that loses its
  covering neighbor becomes exploitable through exactly the gap that
  neighbor used to cover, and enemy targeting/AI (§26/§34) SHOULD be
  able to recognize and exploit this rather than treating every ship
  in a broken formation as equally defended as one still in station.

Classification: CANON, now directly source-confirmed (2026-09-19,
third and final verification pass -- see CANON_RULES.md "Шестнадцатая
сверка", all iterations). Source: the free official Baen sample
chapter (Prologue) of *Field of Dishonor* (HH4),
baen.com/Chapters/0743435745/0743435745___0.htm -- fetched and
confirmed directly in this session, not taken on trust. The Prologue
depicts a tactical reconstruction/simulation of the First Battle of
Hancock (the underlying event is HH3's *The Short Victorious War*;
Field of Dishonor's Prologue replays it). Confirmed present in that
text: Honor Harrington's "Formation Reno" order to draw the cruisers
into tighter station, immediately making the formation's missile
defenses "far more effective"; Captain Pavel Young's panicked "all
ships scatter" order; the resulting "chaos" striking the "fine-meshed,
interlocking network" of the task group's missile defenses; and the
returning ships "socketing back into" the formation's point defense
net. Short phrase-level citation only, per copyright practice for this
ТЗ -- not a full reproduction of the passage.

This is the mechanic in its clearest, most direct form: point defense
and missile defense across a whole task group are explicitly ONE
interlocking network, tightening formation measurably strengthens it,
and an unauthorized scatter breaks it for the entire group, not just
the ship that broke station -- exactly the phenomenon the user
originally asked to formalize. CANON for both the event AND the
"single interlocking network" framing of the mechanism. The specific
per-ship DIRECTIONAL gap/coverage model this ТЗ implements it with
(bow/stern wedge gaps per §41.1, one ship's arc covering a neighbor's
per §33.1's language) remains this ТЗ's own INTERPRETATION of HOW to
build that confirmed CANON principle into concrete, testable geometry
-- the books establish that the network effect is real, not the exact
per-ship arc mechanics this simulator needs to compute it.

IMPLEMENTED (first slice, 2026-09-22): the WEDGE bow/stern gap half of
this is now real. `SimulationWorld._formation_bow_stern_coverage()`
checks whether a living, non-wreck formation neighbor (guide or member,
same formation, formation cohesion required -- no coverage while the
guide is lost) sits within `FORMATION_COVERAGE_MAX_DISTANCE_M` and
`FORMATION_COVERAGE_CONE_HALF_WIDTH_RAD` of a ship's own bow (resp.
stern) axis, reusing `AttackGeometry`'s own "classify a direction in my
local frame" idea rather than a new formula. `ShipDefenseState.resolve_
attack()` takes the result as two new optional bool params and, when a
ship's bow/stern has NO functioning sidewall of its own (not raised, or
burned out) AND a neighbor is covering it, attenuates the hit
(`ResolutionKind.FORMATION_COVERED`, ASSUMPTION multiplier 0.5) instead
of transmitting in full -- wired into both `WeaponResolution.fire()`
(via `SimulationWorld.fire_weapon()`) and `MissileResolution.
resolve_detonation()` (via `SimulationWorld._update_missiles()`). See
CHANGELOG.md/ARCHITECTURE.md/ASSUMPTIONS.md (2026-09-22) for the full
mechanism and honest scope limits.

STILL HONESTLY OPEN, same numbering as before: (1) PD firing-arc model
-- `PointDefenseMount`/`PointDefenseResolution` remain fully
omnidirectional, so this pass adds NO coverage concept for PD at all,
only for the pre-existing wedge bow/stern gap; (2)/(3) done for wedge
only, as above -- the RAISED-sidewall acute-angle-bypass case (§41.1's
other bow/stern mechanic) is deliberately untouched by formation
coverage in this first slice, a narrower reading than "a covered gap is
harder to hit through than an uncovered one" in full generality; (4)
AI/targeting (§26/§34) still does not prefer currently-uncovered gaps --
`_formation_bow_stern_coverage` is read by defense resolution only, not
by any targeting/AI pass. See ASSUMPTIONS.md for per-step cost notes on
what a PD arc model and AI-side gap-seeking would each still require,
same pattern as the §33.1/§34.1/§34.2/§41.1 entry.

---

# 23. Sensors

The battlefield must NOT automatically be fully visible.

Sensor contacts must have states such as:

```text
UNKNOWN
DETECTED
TRACKED
ESTIMATED
UNCERTAIN
LOST
```

A contact can contain:

* estimated position;
* estimated velocity;
* estimated angular velocity;
* estimated orientation;
* uncertainty;
* last update;
* sensor source;
* confidence.

## 23.1 Active vs. Passive Sensing

Sensors operate in two primary modes:

1. **Passive Sensing**:
   * Detects emissions (heat, gravitic signatures from impeller wedges).
   * Does NOT reveal the observer's position.
   * Lower detection range; cannot detect "silent" ships (those with impellers powered down/wedges down).

2. **Active Scanning**:
   * Emits a high-energy pulse to actively probe space.
   * Can detect "silent" ships and provides higher precision/range.
   * **BROADCASTS the observer's position**: An active scan creates a massive, unmistakable signature that allows any observer in range to immediately detect and track the scanner.

The player and AI must manage this trade-off: stay silent and potentially blind, or scan and be revealed.

The player sees what their forces know.
AI sees what its forces know.

Neither side gets automatic access to hidden world state.

---

# 24. ECM

ECM must be a real system.

It must affect, where appropriate:

* detection;
* tracking;
* targeting;
* missile guidance;
* sensor confidence;
* countermeasures.

ECM must NOT simply be:

```text
hitChance -= 20%
```

unless such a modifier is the documented consequence of a deeper simulation model.

---

# 25. Damage

Damage must be subsystem based.

Minimum systems:

* propulsion;
* maneuvering;
* sensors;
* communications;
* weapons;
* missile systems;
* counter-missile systems;
* point defense;
* power;
* structural integrity;
* defensive systems.

Subsystem damage must change actual ship capabilities.

Examples:

```text
sensor damage
→ degraded tracking

communications damage
→ degraded command/reporting

propulsion damage
→ degraded acceleration

missile system damage
→ reduced missile capability
```

## 25.1 No health bars -- damage is combat capability, not a number

Damage MUST NOT be represented, to the player or in the simulation's
own player-facing model, as a single abstract "health" quantity with a
bar/percentage that drains toward zero. This applies to both the UI
(§38/§50) and to what the simulation exposes as a ship's condition:

* the player-facing measure of "how hurt is this ship" MUST be its
  actual, visible combat capability -- which subsystems (§25 list
  above) are damaged/disabled, what that concretely costs it (fewer
  working weapons, degraded tracking, slower turns, garbled comms),
  and visible hull/structural damage (scorching, breaches, venting,
  eventually the §63 wreck state) -- not a green-to-red bar with no
  mechanical meaning of its own;
* a single scalar hit-point pool is acceptable only as a genuinely
  TEMPORARY internal placeholder during development (this is exactly
  what `HullState` already is, per its own class doc and §58 Temporary
  Simplifications) -- it must never become the permanent or
  player-visible representation of damage, and must be replaced by the
  full per-subsystem model before §59 Definition of Done;
* this does not forbid displaying a numeric readout of an individual
  subsystem's condition (e.g. "SENSORS: 40%") where that is the most
  readable way to show real, mechanically-consequential state -- the
  prohibition is specifically on a single undifferentiated "ship
  health" bar that abstracts away which systems are actually hit and
  what that does to the ship's ability to fight, sense, move, or
  communicate.

---

# 26. Tactical AI

AI must be tactical, not a collection of scripted animations.

AI should be able to:

* detect contacts;
* evaluate threats;
* select targets;
* manage formations;
* maneuver;
* select distance;
* use weapons;
* launch missiles;
* use counter-missiles;
* use point defense;
* respond to damage;
* respond to destroyed ships;
* reform formations;
* retreat;
* disengage.

AI must use the same basic information restrictions as the player.

No cheat vision.

---

# 27. Tactical Command System

The central gameplay model uses two command levels.

## Level 1

Command formations:

* element;
* division;
* squadron;
* task force;
* fleet.

## Level 2

Direct command of an individual ship.

The player should feel like a commander rather than someone manually piloting dozens of ships.

---

# 28. Command Hierarchy

Default hierarchy:

```text
Fleet
 └── Task Force
      └── Squadron
           └── Division
                └── Element
                     └── Ship
```

The hierarchy must be configurable because organizational structures can differ by faction and era.

---

# 29. Formation Orders

Formation-level orders include:

* change course;
* change speed;
* accelerate;
* decelerate;
* hold formation;
* change formation;
* approach;
* withdraw;
* attack;
* select target;
* target distribution;
* missile use;
* counter-missile posture;
* defensive posture;
* evasive maneuver;
* disengage;
* reform.

These are intentions.

The Formation AI translates them into ship-level actions.

---

# 30. Individual Ship Orders

Individual ship orders include:

* course;
* acceleration;
* speed;
* orientation;
* target;
* target priority;
* weapon mode;
* missile launch;
* counter-missile policy;
* point-defense policy;
* sensor mode;
* ECM mode;
* defensive posture;
* retreat;
* disengage;
* return to formation.

---

# 31. Individual Override

An individual ship can temporarily override its formation's order.

Example:

```text
Formation:
    Hold Formation

Ship A:
    Intercept Incoming Missile
```

After completion:

```text
Ship A:
    Return To Formation Control
```

The override must be represented in simulation state.

---

# 32. Formation AI

Formation AI must maintain:

* relative position;
* formation geometry;
* velocity matching;
* collision avoidance;
* command hierarchy;
* leader status;
* reforming;
* response to damaged ships;
* response to destroyed ships.

A formation is not simply a group of ships sharing the same position or velocity.

Each ship remains an independent physical entity.

---

# 33. Formation Leader

Each formation may have a leader.

If the leader is destroyed or incapacitated:

1. determine successor;
2. transfer command;
3. update formation state;
4. account for communication limitations;
5. continue according to doctrine/orders.

Do not magically transfer information unavailable to subordinate ships.

## 33.1 Autonomous behavior during the succession window

Between a leader being lost and a successor actually taking command
(the recognition delay this requires -- currently
`COMMAND_TRANSFER_DELAY_S` -- is a distinct, engineering-only constant
from light-speed communication lag, and the two MUST stay documented
as separate mechanisms, not conflated: see CANON_RULES.md/
ASSUMPTIONS.md on this exact distinction), a subordinate ship is not
without orders. Per §61 Nelsonian doctrine ("Initiative within the
plan"), each ship's own local AI MUST, for that window:

* hold its current tactical vector rather than going idle/ballistic or
  reverting to some default behavior;
* keep engaging its last AI-assigned target (§26/§34) rather than
  dropping fire;
* keep covering/screening a neighboring ship with its own wedge/
  position where that is already what it was doing, rather than
  abandoning the formation's shape mid-transition.

This is explicitly INTERPRETATION grounded in §61, not a book
citation about this exact mechanic -- the point is that "leaderless"
must not mean "brainless": a subordinate captain who has lost contact
with the flag keeps fighting the plan they already understood, per
§33's own point 5 ("continue according to doctrine/orders"). This
subsection makes that point concrete enough to implement and test
against, rather than leaving it as a general aspiration.

---

# 34. Target Assignment

Support:

### Group target

The formation receives a target.

### Automatic target distribution

AI assigns targets across ships.

### Manual assignment

Example:

```text
Ship A → Target X
Ship B → Target Y
Ship C → Target X
```

Target assignment must account for:

* available information;
* weapon capability;
* distance;
* geometry;
* threat;
* ship state.

## 34.1 Doubling -- deliberate concentration, not coincidental pile-on

"Automatic target distribution" above must be more than every ship
independently picking its own nearest usable contact (the current
Tactical AI first slice, §26 -- honestly documented as a known
limitation in ASSUMPTIONS.md, not a design endpoint). A formation-level
assignment pass, run by the guide ship's side of the command hierarchy
(§27/§28/§33), should be able to deliberately mass several ships' fire
onto ONE chosen enemy unit at a time ("doubling" -- concentrating a
local firepower advantage the way a Nelsonian line-of-battle ship
doubled on part of an enemy line) rather than each attacker
independently converging on whatever looks nearest to itself, which
can accidentally overkill an escort while a more valuable or more
dangerous enemy unit goes unengaged. Concretely: target assignment
should weigh EXPECTED CONTRIBUTION per ship-target pairing (would this
ship's fire actually still matter against this target, or is the
target already being overkilled by others already assigned to it) --
not treat "already 4 ships shooting at it" and "nobody shooting at it"
as equally good assignments just because both are within range.

## 34.2 Missile time-on-target -- coordinated arrival, not a ragged trickle

When multiple missiles from one or more launching ships are assigned
to detonate against the same target at roughly the same time, their
LAUNCH should be staggered (not necessarily simultaneous) so that
their ARRIVAL is coordinated -- overwhelming the target's point
defense (§22) with more simultaneous threats than it can engage in its
own reaction-time window, rather than presenting them as a ragged,
individually-interceptable trickle. This is a direct, mechanically
necessary consequence of point defense already having a real reaction
time and per-mount recharge cycle (§22/`PointDefenseMount`) -- a
salvo's tactical value depends on its members arriving close enough
together to saturate that capacity, not just on the total missile
count fired over the course of an engagement.

§34.1 (formation-coordinated target assignment) and §34.2 (this
staggered-launch coordination) are both now implemented as first
slices -- see `TacticalAI.select_formation_target_for_member` /
`SimulationWorld._resolve_formation_target_assignment` (§34.1) and
`SimulationWorld._resolve_missile_tot_coordination` (§34.2), with
tests in `test_formation.gd` and `test_missile_launch_ai.gd`. Honest
scope of the §34.2 first slice: coordinates only members of the SAME
formation sharing a §34.1-assigned target (not a manual §30
designation, and not two different formations independently picking
the same hostile), and estimates flight time with a straight-line
boost-coast approximation that ignores the target's own motion during
the flight (a true intercept-time solve needs the same still-missing
intercept-vector solver as §41.1 Crossing the T). See CHANGELOG.md/
ARCHITECTURE.md/ASSUMPTIONS.md for the implementation pass.

---

# 35. Command Queue

Orders can be queued:

```text
Change Course
→ Accelerate
→ Form Line
→ Approach Target
→ Missile Salvo
→ Turn Away
→ Reform
```

Orders are intentions executed by AI.

They are not scripted teleportation or animation sequences.

---

# 36. Information and Communications

The commander knows only information available through:

* own sensors;
* subordinate sensors;
* communications;
* formation reports;
* command chain;
* received battle reports.

Communication loss must matter.

A formation must not receive instantaneous omniscient updates.

---

# 37. Battle Reports

Reports can include:

* contact detected;
* missile launch detected;
* incoming missile;
* target destroyed;
* subsystem damaged;
* ship damaged;
* ship lost;
* formation broken;
* command lost;
* retreat initiated.

Reports should have simulation timestamps.

---

# 38. Tactical UI

Provide:

* Fleet View;
* Task Force View;
* Squadron View;
* Division View;
* Ship View;
* Free/Cinematic Camera.

Display where information is known:

* ships;
* formations;
* movement vectors;
* velocity;
* acceleration;
* orientation;
* range;
* missile tracks;
* counter-missiles;
* sensor contacts;
* threats;
* system status -- per-subsystem condition and concrete combat
  consequences (§25.1: no single "health bar," ever -- show what is
  actually damaged and what that costs the ship);
* commands;
* battle reports.

---

# 39. Selection

Support:

* single selection;
* multi-selection;
* formation selection;
* by type;
* by side;
* by state;
* by role.

---

# 40. Direct Ship Command

Direct ship command remains tactical.

It must allow the player to issue:

* course;
* acceleration;
* speed;
* target;
* weapon mode;
* missile launch;
* counter-missile policy;
* point-defense policy;
* sensor mode;
* ECM mode;
* defensive posture;
* retreat;
* disengage.

The system must not force the player to manually steer every individual ship.

---

# 41. Tactical AI and Geometry

AI must consider:

```text
enemy position
enemy velocity
enemy orientation
enemy wedge
enemy sidewalls
relative velocity
weapon geometry
missile geometry
own acceleration capability
own damage
sensor uncertainty
```

Distance alone is insufficient.

## 41.1 Crossing the T -- a concrete geometric objective, not just "consider geometry"

Age-of-Sail "crossing the T" (§61) has a direct, already-implemented
geometric vocabulary in this simulator and Tactical AI SHOULD pursue it
as an explicit maneuvering objective, not just passively benefit from
it when it happens to occur:

* the objective is to maneuver so that the ENEMY's attack-geometry
  sector (`AttackGeometry.Sector`, as computed against the enemy's own
  local axes) toward this ship classifies as `BOW` or `STERN` --
  meaning the enemy can only bring bow/stern-arc weapons (`bow_arc()`/
  `stern_arc()`) to bear, not its full broadside -- while simultaneously
  keeping THIS ship's own sector toward the enemy classified as `PORT`
  or `STARBOARD`, so its `broadside_arc()` mounts (§17, PORT+STARBOARD)
  are live;
* the enemy's own bow/stern acute-angle wedge vulnerability
  (`ShipDefenseState.BOW_STERN_ACUTE_ANGLE_HALF_WIDTH_RAD`, currently
  15 degrees, ASSUMPTION -- see ASSUMPTIONS.md) is the geometric reason
  this matters mechanically, not just flavor: a ship caught bow/stern-on
  is not just weapon-disadvantaged, it is also more exposed through
  that acute-angle gap in its own wedge coverage;
* this is an INTERPRETATION of §41's existing "AI must consider... weapon
  geometry... own acceleration capability" requirement, made concrete
  using the sector vocabulary this codebase already has (`attack_geometry.gd`),
  not a new, separately-invented mechanic. Honor Harrington herself, per
  §61, is explicitly Age-of-Sail tactics translated to space; this is
  that translation applied to a specific, already-coded piece of
  geometry, which is exactly what §4.1 (canon/logic for genuine gaps)
  calls for.

This is OPEN, not yet implemented -- current Tactical AI target
selection (§26) has no maneuvering/intercept-vector component at all
(it only selects among contacts already in range/arc; it does not
compute a course to REACH a favorable arc). A future pass implementing
this should compute an intercept vector toward a `PORT`/`STARBOARD`
firing solution against the enemy's `BOW`/`STERN`, not just react to
whatever geometry the ships already happen to be in.

---

# 42. Simulation Architecture

Logical subsystems:

```text
Simulation
Physics
Combat
Weapons
Missiles
Sensors
Damage
AI
Commands
Scenarios
Replay
Data
UI
Rendering
```

Simulation must be independent from UI and rendering.

Rendering must display simulation state rather than define combat rules.

---

# 43. Deterministic Simulation

Given identical:

* initial state;
* seed;
* commands;
* timestep;

the simulation should produce the same result.

Randomness must be seeded.

## 43.1 One set of rules for every ship -- no faction/side special-casing

Physics (§6/§11-§15: mass, thrust, inertia, relative velocity, speed-
of-light constraints) and damage (§25, §25.1, §63: subsystem damage,
hull/structural damage, mission-kill degradation, destruction/wreck
state) MUST be computed by the exact same code path and formulas for
EVERY ship in the simulation -- player-controlled, AI-controlled,
allied, hostile, or neutral. There is no "player's side" branch and no
"AI's side" branch in physics or damage resolution; a ship's team/
ownership (`SimulationWorld.teams`, §26) is bookkeeping for targeting/
hostility decisions ONLY, never an input to how much damage a hit does,
how a ship accelerates, or whether/how it becomes a wreck.

This follows directly from §43's determinism requirement above (a
simulation that treats sides differently cannot be side-neutral-
deterministic in any meaningful sense) and from §26's existing "AI must
use the same basic information restrictions as the player. No cheat
vision." -- that rule is about SENSING; this rule is the same principle
applied to PHYSICS and DAMAGE: no side gets easier math, softer hits,
faster regeneration, or gentler mass/inertia than any other. Difficulty
or balance, if ever wanted, belongs in scenario/ship-database
DATA (§8/§46/§48 -- e.g. deliberately fielding a weaker OPFOR loadout),
never in a hidden multiplier keyed on which side a ship belongs to.

---

# 44. Time Control

Support:

* pause;
* single-step;
* 1x;
* 2x;
* 5x;
* 10x;
* 25x;
* 100x.

Changing simulation speed must not change physical rules.

---

# 45. Replay

Replay records simulation rather than video.

Store as practical:

* initial state;
* random seed;
* commands;
* events;
* timestamps;
* snapshots.

Support:

* play;
* pause;
* speed;
* event navigation;
* trajectories;
* missile tracks;
* hits;
* damage;
* destruction.

Seek should be implemented through snapshots if practical.

---

# 46. Scenarios

Minimum scenarios:

1. Duel
2. Missile Duel
3. Squadron Engagement
4. Fleet Engagement
5. Custom Scenario

Development should progress:

```text
1v1
→ 2v2
→ small groups
→ squadron
→ large fleet
```

---

# 47. Scenario Editor

After the core MVP:

* add ship;
* select class;
* select faction;
* set position;
* set velocity;
* set orientation;
* assign formation;
* assign orders;
* save;
* load.

---

# 48. Data-Driven Design

Do not hardcode ship characteristics into combat code.

Data should define:

* ships;
* weapons;
* missiles;
* factions;
* formations;
* scenarios;
* technology;
* AI parameters.

---

# 49. Performance

Architecture must support potentially large numbers of:

* ships;
* missiles;
* counter-missiles;
* laserheads;
* sensor contacts.

Use where appropriate:

* fixed timestep;
* spatial partitioning;
* object pooling;
* LOD;
* batching;
* event-driven updates.

Do not prematurely optimize without profiling.

---

# 50. Visual Style

The visual style should be:

* serious;
* military;
* hard science-fiction;
* large scale;
* cinematic;
* realistic;
* readable.

Avoid:

* Star Wars-like dogfighting;
* arcade flight;
* cartoon aesthetics;
* tiny arena-like battles;
* video-game health bars/HP percentages as the way damage is shown
  (§25.1) -- damage reads through subsystem status and visible
  structural damage, not an abstracted bar.

The scale of space should feel enormous.

---

# 51. Assets

Do not introduce runtime dependence on generative AI services.

Use:

* original assets;
* procedural assets;
* free assets;
* properly licensed assets.

Check licenses before inclusion.

---

# 52. Testing

Tests must cover at minimum:

* vector math;
* physics;
* inertial movement;
* high acceleration;
* wedge geometry;
* sidewalls;
* weapon geometry;
* missile guidance;
* counter-missile interception;
* sensors;
* ECM;
* point defense;
* subsystem damage;
* deterministic simulation;
* command hierarchy;
* formation AI;
* individual overrides;
* scenario loading;
* replay.

---

# 53. Debug Tools

Debug mode may expose:

* true battlefield state;
* wedge planes;
* sidewalls;
* velocity vectors;
* acceleration vectors;
* relative velocity;
* attack vectors;
* missile trajectories;
* sensor truth;
* AI decisions;
* command state.

Debug information must not be available as omniscient information in normal gameplay.

---

# 54. External Dependencies

Runtime dependencies must be local and distributable.

Do not require:

* Claude;
* LLM;
* cloud AI;
* internet;
* external API;
* API keys;
* external game server.

Third-party libraries must have compatible licenses.

---

# 55. No Premature MMO

Do not implement unless separately required:

* multiplayer;
* accounts;
* backend;
* matchmaking;
* cloud saves;
* online services;
* MMO infrastructure.

The initial product is a local single-player tactical simulator.

---

# 56. Development Milestones

Recommended order. PRIORITY NOTE (user decision, 2026-09-22): Milestone
12 (Replay) is DEPRIORITIZED for now -- do not pick it up next just
because it is next in numeric order. Work Milestones 13-17 (and any
honestly-logged debt from 1-11, per ASSUMPTIONS.md/CHANGELOG.md) before
returning to Milestone 12. The existing first-slice Replay code
(`replay_log.gd` -- command/event recording only, no snapshots/seek/UI)
stays as-is; it is paused, not reverted. Revisit Milestone 12 once
13-17 are underway or done, or if the user says otherwise.

### Milestone 1

Engine skeleton + 3D world + simulation loop.

### Milestone 2

Two ships + inertial physics.

### Milestone 3

Wedge + sidewalls + ship orientation.

### Milestone 4

Energy weapons.

### Milestone 5

Missiles + guidance.

### Milestone 6

Counter-missiles + point defense.

### Milestone 7

Sensors + ECM.

### Milestone 8

Subsystem damage.

### Milestone 9

Tactical AI.

### Milestone 10

Formation command.

### Milestone 11

Individual ship command + overrides.

### Milestone 12

Replay. DEPRIORITIZED -- see priority note above. First slice already
exists (`replay_log.gd`: command/event recording, no snapshots/seek/
UI); do not extend it until 13-17 are addressed first.

### Milestone 13

Scenarios.

### Milestone 14

2v2 + squadron.

### Milestone 15

Large fleet engagements.

### Milestone 16

Scenario editor.

### Milestone 17

Performance + polish + final Windows build.

---

# 57. First Working Combat Milestone

The first meaningful combat milestone must become a real 1v1 tactical engagement.

It must eventually contain:

```text
3D world
+
2 independent ships
+
inertial physics
+
high acceleration
+
orientation
+
impeller wedge
+
sidewalls
+
sensors
+
targeting
+
energy weapons
+
missiles
+
missile guidance
+
counter-missiles
+
point defense
+
ECM
+
subsystem damage
+
AI
+
tactical commands
+
pause
+
step
+
time scaling
+
battle log
+
replay
```

Do not declare the project complete because a ship mesh is visible in a 3D scene.

---

# 58. Temporary Simplifications

Temporary simplifications are allowed during intermediate milestones only if:

1. they are explicitly identified;
2. they do not masquerade as finished functionality;
3. they are tracked;
4. they are replaced before the relevant Definition of Done.

Do not permanently replace important Honorverse mechanics with generic placeholders.

---

# 59. Definition of Done

The final project is complete only when:

* Windows build works;
* application launches;
* true 3D simulation works;
* inertial movement works;
* high-speed movement works;
* wedge geometry works;
* sidewalls work;
* weapons work;
* missiles are real simulation entities;
* counter-missiles work;
* point defense works;
* sensors work;
* ECM works;
* subsystem damage works;
* tactical AI works;
* formation command works;
* individual ship command works;
* command overrides work;
* replay works;
* scenarios work;
* automated tests exist;
* documentation is present;
* no critical TODOs remain;
* runtime does not depend on Claude, LLM, cloud AI, external APIs, or internet.

A UI element existing is not proof that its underlying functionality is complete.

---

# 60. Product Goal

The final experience should follow:

```text
Observe
→ Decide
→ Issue Orders
→ Monitor
→ Adapt
→ Take Direct Control When Necessary
```

The player should feel like the commander of a large military space force rather than the pilot of an arcade spacecraft.

The central goal is:

**A complete autonomous 3D tactical Honorverse combat simulator with formation-level and individual-ship command.**

---

# 61. Combat Philosophy — “Nelson in a Skirt”

Honor Harrington was deliberately written as a spiritual successor to Horatio Nelson.  
The simulator must therefore reproduce the *feel* of Nelsonian naval warfare translated into the Honorverse, not generic space-opera dogfighting.

### What this means in practice

1. **Decisive battle mindset**  
   The system should reward seeking and forcing a decisive engagement under favourable geometric conditions, not endless skirmishing or hit-and-run as the default optimal strategy.

2. **Geometry is the weather gauge**  
   Relative position, closing vectors, wedge orientation and the ability to present or deny aspects are the space equivalent of the weather gauge. A commander who understands and exploits geometry should have a clear advantage.

3. **Wall of battle / formation fighting**  
   The primary mode of fleet combat is coordinated formation action (the “wall”). Individual ships exist inside a larger tactical plan. Breaking formation without reason should be costly; holding or reforming the wall under fire should be a meaningful skill.

4. **Concentration of force**  
   Bringing superior weight of fire onto a portion of the enemy line (crossing the T, doubling, local superiority) must be a viable and powerful tactic, just as it was for Nelson.

5. **Aggressive but calculated risk**  
   The best results come from bold decisions taken with incomplete information, not from perfect knowledge or from pure caution. The information model (limited sensors, delayed reports, communication limits) exists to force the player into this space.

6. **Commander, not pilot**  
   The player’s primary loop is observation → decision → order → monitoring. Direct control of a single ship is an occasional, deliberate exception, not the default mode of play.

7. **Initiative within the plan**  
   Subordinate ships and formations should be able to exercise limited initiative (especially under loss of communications or when local conditions demand it) without the entire force dissolving into chaos. This mirrors the Nelsonian expectation that captains understand the admiral's intent.

### Design consequences

- Formation AI and command hierarchy are not secondary features; they are core to the intended experience.
- Sensor and communication limits are not “realism chrome”; they are what create the decision space Nelson operated in.
- Missile and energy-weapon geometry must make positioning and aspect matter.
- The UI and camera should support the commander's view (fleet / task-force / squadron) more naturally than the fighter-pilot view.

If a proposed feature or simplification moves the game toward arcade dogfighting or toward perfect-information real-time strategy, it is working against the project's intended character.

---

# 62. Inertia, Ship Mass, and Time Scale

## 62.1 Mass must matter, not just be a stored number

Every warship carries a real `mass_kg` (ТЗ §8 Ship Database). Mass MUST
be a load-bearing part of the physics, not decoration:

* the same impeller/compensator technology generation produces LOWER
  attainable acceleration for a more massive hull, all else equal --
  this is a direct consequence of thrust-to-mass ratio, not an
  arbitrary per-class dial;
* heavier ships must feel correspondingly more sluggish to accelerate,
  decelerate, and change heading than lighter ones of the same
  generation;
* a lighter, stripped-down hull built purely for speed (a courier or
  dispatch boat, sacrificing armor/weapons/crew space for a smaller,
  cheaper impeller/compensator load) is canonically able to reach much
  higher acceleration than a comparably-generation warship -- see
  §62.3.

CANON basis for ship mass by class (Honorverse Wiki "Ship Types",
verified 2026-09-18):

| Class                  | Typical mass range        |
|------------------------|----------------------------|
| Destroyer (DD)         | ~65,000-80,000 tons (later classes, e.g. Roland, reach light-cruiser range) |
| Light Cruiser (CL)     | ~90,000-150,000 tons       |
| Heavy Cruiser (CA)     | ~160,000-350,000 tons      |
| Battlecruiser (BC)     | ~780,000-2,500,000 tons    |
| Battleship (BB)        | ~2,000,000-4,000,000 tons  |
| Superdreadnought (SD)  | ~7,000,000-9,000,000 tons  |

Exact mass MUST remain per-ship-class data (ТЗ §8/§48 Data-Driven
Design), not a hardcoded constant, and MUST be tied to a specific ship
class definition when the ship database exists, not invented per-ship.

## 62.2 Inertial compensator -- why acceleration is limited, and by what

CANON basis (Honorverse Wiki "Inertial compensator", verified
2026-09-18): the inertial compensator reduces the acceleration a crew
and internal equipment experience by turning the ship's own impeller
wedge into what the source calls an "inertial sump." This is the
mechanism that makes survivable high-g combat maneuvering possible at
all -- without it, the true accelerations warships achieve would kill
their crews instantly.

Canon figures to ground the model:

* gravity generators ALONE (i.e. without an impeller wedge to use as
  the sump) can only handle up to ~50 G, limiting achievable ship
  acceleration to roughly 51 G under that degraded mode;
* without a wedge, compensation is much less effective: a cited example
  states a 150 G acceleration could only be reduced to an apparent 5 G
  felt by the crew (illustrating how much of the "sump" effect depends
  on having the wedge active, i.e. `defense.wedge_up`);
* pre-war Manticoran/Havenite doctrine mandated operating at no more
  than 80% of maximum compensator effectiveness as a safety margin;
  both sides abandoned this conservative margin during the First
  Manticoran-Havenite War in favor of more aggressive acceleration
  profiles -- i.e. accepting more risk for more combat performance is
  itself a canonical DOCTRINE CHOICE, not a fixed constant;
* compensator failure during significant acceleration is lethal to the
  crew immediately -- there is no "soft" failure mode.

Design consequences for this simulator:

* `ShipPhysicsState.compensator_condition` (already implemented) is the
  right place to model degraded compensator performance from damage;
  `defense.wedge_up` gating the compensator's effectiveness (per the
  "50G without wedge vs. much higher with wedge" canon figure above) is
  an explicit, citable design target for a future pass, not yet wired.
* A "safety margin" slider/doctrine choice (operate at e.g. 80% of
  rated compensator capability for safety vs. closer to 100% for combat
  performance, at increased catastrophic-failure risk) is a legitimate,
  canon-grounded future mechanic for Tactical AI (§26) and/or player
  doctrine options -- NOT implemented yet, tracked as an open item.
* Missiles are NOT subject to this constraint the same way (no crew to
  protect) -- this is exactly why missile drives can run at tens of
  thousands of G (see §18/missile_state.gd, CANON ~46,000 G / ~96,000 G
  examples) while crewed warships cannot: the compensator problem is a
  CREWED-hull-specific limitation, not a universal drive limitation.

## 62.3 Acceleration figures by hull type

CANON basis (Honorverse Wiki "Ship Types", verified 2026-09-18):
dispatch boats/couriers are explicitly documented as reaching up to
~800 G -- consistent with §62.1 (minimal mass, no combat load, built
purely for speed). No specific canonical G figures were found in this
pass for destroyer-through-superdreadnought classes specifically; those
remain UNKNOWN pending further source-checking and MUST stay
configurable per ship class (§8/§48), not hardcoded, until real figures
are found and logged in ASSUMPTIONS.md/CANON_RULES.md.

## 62.4 Time scale

Two distinct notions of "time" apply to this simulator, and they MUST
NOT be confused:

1. **Simulation tick rate** (ТЗ §42/§43): a fixed, deterministic
   timestep (currently 60Hz, see `SimClock`) that every physics/combat
   calculation advances by. This rate is an ENGINEERING choice, not
   canon, and must never vary based on frame rate, load, or player
   input -- determinism (§43) depends on it staying fixed.
2. **Playback/observation speed** (ТЗ §44 Time Control: pause, single-
   step, 1x/2x/5x/10x/25x/100x): a PURELY presentational multiplier on
   how many fixed ticks are advanced per real second of wall-clock time
   shown to the player. Changing this multiplier MUST NOT change
   physical rules, combat outcomes, or determinism (§44 already states
   this) -- it changes how fast the player WATCHES a deterministic
   simulation unfold, never what that simulation computes.

Scope boundary (clarifying an area §44/§45 leave implicit): this
simulator models TACTICAL combat time -- real seconds to at most a few
hours of in-universe time, at fixed 60Hz resolution. It does NOT model
the much larger-scale time compression of interstellar hyper transit
(days/weeks between star systems in the books). Compressed strategic/
transit time, if ever wanted (e.g. for a campaign layer), is UNKNOWN/
out of scope for this simulator and would need its own design pass --
it must not be implemented by just cranking the §44 playback multiplier
to extreme values, which would silently break tactical-scale physics
assumptions (missile burn times, sensor detection windows, etc. are all
tuned for real-time-scale tactical engagements).

---

# 63. Ship Destruction, Wrecks, and Progressive Combat Damage

## 63.1 A destroyed ship must NOT disappear

When a ship is destroyed, it MUST NOT be deleted or vanish from the
simulated world. It becomes a **wreck**: an inert object that:

* keeps its last position/velocity/orientation and continues to obey
  inertial physics (ТЗ §12 -- "stopping thrust must not automatically
  stop the ship" applies equally to a dead hull: nothing is thrusting,
  but momentum does not vanish either);
* is no longer a ship for any combat/command/AI purpose -- it has no
  weapons, no sensors, no crew, cannot be given orders, is never a
  member of a formation, and Tactical AI (§26) must never select it as
  a firing platform or a formation guide;
* REMAINS a valid sensor contact and a valid target reference for
  everything that still makes sense against an inert mass (e.g. "avoid
  debris," after-action battle damage assessment, a future salvage/
  scenario mechanic) -- it is data that persists, not data that is
  thrown away;
* remains VISIBLE in the tactical picture and in the 3D view once
  rendering exists (§7/§38) -- a battle's aftermath (a debris field, a
  drifting hulk) is part of what the player should be able to see and
  assess, not something the engine quietly erases.

This directly fixes a previously-honest gap: the current
`_resolve_ship_destruction()` implementation calls `remove_ship()`,
which deletes the ship entirely from `SimulationWorld.ships` --
`is_destroyed()` "removal" today means "ceases to exist," not "becomes
a wreck." That is now a documented spec violation, not an acceptable
simplification, and must be corrected by a future pass (see
ASSUMPTIONS.md for the open implementation gap).

## 63.2 Wreck retention is not eternal, but it is not instant either

A long engagement can destroy many ships; keeping every wreck as a
fully simulated object forever is a legitimate performance concern
(ТЗ §49 Performance). The requirement is only that a wreck:

* persists for at least the remainder of the tactical engagement it
  died in, and through any immediate post-battle assessment/replay
  (§45) of that engagement;
* is never removed simply because "the ship died" -- any later pruning
  (e.g. after a long real-world time, after leaving all sensor range,
  or at scenario/replay boundaries) must be a SEPARATE, explicit,
  documented decision, not a side effect of the destruction code path
  itself.

Exact retention policy (how long, under what conditions a wreck may
eventually be pruned) is UNKNOWN/ASSUMPTION -- no canonical figure
exists for this, and it is intentionally left open for a later
performance-tuning pass rather than invented now.

## 63.3 Progressive damage must matter BEFORE destruction, not just at it

Combat damage must not be a binary "fully combat-capable" vs "gone"
state. Subsystem damage (§25) is explicitly for this: a ship's actual
fighting ability MUST degrade continuously and visibly as its
subsystems take damage, well before hull integrity reaches zero. This
was already a §25 requirement ("subsystem damage must change actual
ship capabilities") -- this section makes the COMBAT CONSEQUENCE of
that requirement explicit:

* a ship with a disabled or badly degraded WEAPONS/MISSILE_SYSTEMS/
  COUNTER_MISSILE_SYSTEMS/POINT_DEFENSE subsystem must actually deal
  less damage, launch fewer/no missiles, or intercept fewer incoming
  threats -- not just display a lower number while fighting exactly as
  effectively;
* a ship with disabled/degraded SENSORS or COMMUNICATIONS must
  actually see less and coordinate worse (§23/§31, already partly
  implemented: sensor range scaling, order transmission delay);
* a ship with disabled/degraded PROPULSION/MANEUVERING must actually
  maneuver worse (already implemented: `effective_max_acceleration()`);
* accumulating subsystem damage, independent of the single hull-
  integrity scalar, should be able to produce a ship that is
  effectively **mission-killed** -- unable to meaningfully fight back,
  sensor-blind, unable to maneuver -- while still nominally "alive"
  (hull integrity > 0). A mission-killed ship remains a real object in
  the simulation (still a target, still subject to further damage,
  still eventually destroyable) -- it is a DEGRADED combat state, not
  a third bookkeeping category bolted on beside "alive"/"destroyed".
  Tactical AI (§26) retreat/disengage logic (§26, `is_critically_damaged`)
  is one existing example of behavior keying off degraded state; further
  such consequences (e.g. an AI that recognizes a mission-killed hostile
  poses little threat) are open future work, not required by this
  section on their own.

## 63.4 Relationship to the existing HullState simplification

`HullState` is already documented (see its own class doc, §58 Temporary
Simplifications) as a TEMPORARY single-scalar placeholder for the full
per-subsystem damage model required by §25. This section does not
change that plan -- wrecks and progressive mission-kill behavior must
eventually be judged by the same richer, per-subsystem damage state
that replaces `HullState`, not by a parallel system. Implementing §63.1
(wrecks) does not require waiting for that replacement -- a wreck is
simply "no HullState-equivalent left to keep the ship alive," whatever
that state ends up being -- but implementing §63.3 to its full extent
(a genuine, systemic mission-kill determination across all subsystem types)
does depend on closing the remaining §25 gaps (STRUCTURAL_INTEGRITY/
POWER/DEFENSIVE_SYSTEMS still without a consumer, see ASSUMPTIONS.md).
