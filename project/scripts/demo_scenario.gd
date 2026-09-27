extends RefCounted
## DemoScenario
##
## 2026-09-27 LIVE USER REPORT (after running the .exe): "no missiles
## visible, some incomprehensible laser brawl, although per the spec and
## the book it should open with a long-range missile duel; no formation;
## doesn't look like the reference; no controls" / "this is not a squadron
## engagement from Weber's books". Root causes found in the old hardcoded
## main.gd scenario: sides started 10 KM apart (lasers with 500 km range
## -> instant point-blank laser brawl), missile tubes only on red with a
## 60,000 km launch range, no formation at start, and no HullState passed
## to world.add_ship (so no ship could ever actually be destroyed).
##
## This builder replaces that with a canon-shaped opening (Honorverse
## squadron engagement): two 4-ship squadrons, each in line-abreast
## formation (a real FormationState with the flagship as guide, red's also
## a player-commandable CommandEchelon "Squadron 1"), approaching bow-on
## from ~5.3 million km. Both sides carry multi-tube missile broadsides
## that open fire at ~5 million km, point defense, and energy weapons whose
## range only matters if the squadrons actually close.
##
## All figures are labelled ASSUMPTION (see ASSUMPTIONS.md "canon-shaped
## demo scenario"): the missile drive itself (46,000 g x 180 s, ~7.3M km
## powered envelope) is the project's existing MissileState default, NOT
## changed here; everything else is scenario tuning so the engagement
## plays out like the books' opening phase rather than a claim of exact
## canon numbers.
##
## Kept as a pure, scene-free builder so it is headless-testable
## (simulation/tests/test_demo_scenario.gd) -- main.gd only calls build()
## and then attaches views to whatever ships exist.
class_name DemoScenario

const SEPARATION_M: float = 5.3e9            # 5.3 million km between squadron centres at t=0
const INITIAL_CLOSING_SPEED_MPS: float = 3.0e5  # each side already moving 300 km/s toward the other
const LINE_SPACING_M: float = 20_000.0       # 20 km between ships abreast
const SENSOR_RANGE_M: float = 1.0e10         # 10 million km: gravitic detection of impeller wedges + missile telemetry link (ASSUMPTION)

const TUBES_PER_SHIP: int = 4
const MISSILE_ROUNDS_PER_TUBE: int = 40
const MISSILE_RELOAD_S: float = 20.0
const MISSILE_LAUNCH_RANGE_M: float = 5.0e9  # 5 million km

## Laserhead terminal envelope: MissileState arms at 10% of this, i.e. a
## 3,000 km standoff detonation -- canon laserheads fire their rods from
## thousands of km out rather than needing a near-contact hit (the
## project default 50 km / 5 km arm radius is essentially unreachable at
## 60,000+ km/s closing speeds). ASSUMPTION.
const LASERHEAD_TERMINAL_RANGE_M: float = 3.0e7
## Drive burn is 180 s; a missile still coasting a minute after burnout
## has missed and self-destructs rather than cluttering the plot.
const MISSILE_MAX_LIFETIME_S: float = 240.0
## Fraction of a laserhead that penetrates even an intact sidewall (books:
## sidewalls degrade laserheads, they do not stop them). ASSUMPTION.
const LASERHEAD_SIDEWALL_FLOOR: float = 0.35
const PD_MOUNTS_PER_SHIP: int = 3
const PD_RANGE_M: float = 2.0e8              # 200,000 km
const PD_REACTION_S: float = 0.7
const PD_RECHARGE_S: float = 0.5

## Hull points (HullState default is 10,000). Lowered so a leaking missile
## broadside visibly hurts within a few salvos -- pacing ASSUMPTION.
const HULL_INTEGRITY: float = 6000.0
const ENERGY_RANGE_M: float = 4.0e8          # 400,000 km
const ENERGY_DAMAGE: float = 150.0
const ENERGY_RECHARGE_S: float = 6.0

const PLAYER_ECHELON_ID: String = "red_squadron"
const PLAYER_FORMATION_ID: String = "red_line"
const ENEMY_FORMATION_ID: String = "blue_line"

## Ship ids: "alpha"/"beta" stay the flagships/guides (HUD_POV_SHIP_ID,
## PlayerInput and older tests all refer to exactly these ids).
const RED_IDS: Array = ["alpha", "alpha_2", "alpha_3", "alpha_4"]
const BLUE_IDS: Array = ["beta", "beta_2", "beta_3", "beta_4"]

## Lateral (X) slot per index: flagship centre-left, line abreast.
static func _slot_x(i: int) -> float:
	return (float(i) - 1.5) * LINE_SPACING_M

static func build(world: SimulationWorld) -> void:
	world.sensor_range_m = SENSOR_RANGE_M
	world.player_controlled_teams["red"] = true
	world.missile_sensor_update_interval_ticks = 6
	world.missile_detonation_range_override_m = LASERHEAD_TERMINAL_RANGE_M
	world.missile_max_lifetime_override_s = MISSILE_MAX_LIFETIME_S
	world.missile_zem_guidance = true
	# Combat attitude (see SimulationWorld.ship_attitude): everyone starts
	# on "auto" -- broadside to fire, rolling the wedge toward incoming
	# salvos. The player can override per ship from the command bar.
	var att: String = OS.get_environment("DEMO_ATTITUDE") if OS.get_environment("DEMO_ATTITUDE") != "" else "auto"
	for sid in RED_IDS + BLUE_IDS:
		world.set_ship_attitude(sid, att)
	# Player squadron starts at the world origin (not symmetric about it):
	# float32 positions are most precise near 0, and the player zooms into
	# their own ships far more than the enemy's (see RenderOrigin).
	_build_side(world, RED_IDS, "red", 0.0, false)
	_build_side(world, BLUE_IDS, "blue", -SEPARATION_M, true)
	_make_formation(world, PLAYER_FORMATION_ID, RED_IDS)
	_make_formation(world, ENEMY_FORMATION_ID, BLUE_IDS)
	world.add_command_echelon(PLAYER_ECHELON_ID, "Squadron 1")
	world.attach_formation_to_echelon(PLAYER_ECHELON_ID, PLAYER_FORMATION_ID)

static func _build_side(world: SimulationWorld, ids: Array, team: String, z: float, flipped: bool) -> void:
	# Red sits at +Z facing -Z (identity orientation: bow is -Z, see
	# AttackGeometry); blue at -Z rotated PI about Y so its bow faces +Z.
	# Both therefore approach bow-on, the classic opening geometry.
	var toward_enemy: Vector3 = Vector3(0, 0, 1) if flipped else Vector3(0, 0, -1)
	for i in range(ids.size()):
		var ship_id: String = ids[i]
		var phys := ShipPhysicsState.new()
		phys.position = Vector3(_slot_x(i), 0.0, z)
		if flipped:
			phys.orientation = Quaternion(Vector3.UP, PI)
		phys.velocity = toward_enemy * INITIAL_CLOSING_SPEED_MPS
		# Accelerating toward the enemy at 80% of rated max -- canon
		# squadrons hold back a margin below the slowest ship's maximum so
		# members have thrust left over to keep station (ASSUMPTION).
		phys.commanded_thrust_local = Vector3(0.0, 0.0, -0.8)
		phys.defense = ShipDefenseState.new()
		phys.defense.laserhead_sidewall_floor = LASERHEAD_SIDEWALL_FLOOR
		phys.subsystems = ShipSubsystems.new()
		var hull := HullState.new()
		hull.max_integrity = HULL_INTEGRITY
		hull.integrity = HULL_INTEGRITY
		world.add_ship(ship_id, phys, hull)
		world.set_team(ship_id, team)

		for _t in range(TUBES_PER_SHIP):
			var tube := MissileTube.new()
			tube.ammo_count = MISSILE_ROUNDS_PER_TUBE
			tube.reload_time_s = MISSILE_RELOAD_S
			tube.max_range_m = MISSILE_LAUNCH_RANGE_M
			world.add_missile_tube(ship_id, tube)

		for _p in range(PD_MOUNTS_PER_SHIP):
			var pd := PointDefenseMount.new()
			pd.max_engagement_range_m = PD_RANGE_M
			pd.reaction_time_s = PD_REACTION_S
			pd.recharge_time_s = PD_RECHARGE_S
			pd.hits_required_to_kill = 1
			world.add_pd_mount(ship_id, pd)

		var laser := WeaponData.new()
		laser.id = "energy_mount"
		laser.max_range_m = ENERGY_RANGE_M
		laser.damage_per_hit = ENERGY_DAMAGE
		laser.recharge_time_s = ENERGY_RECHARGE_S
		world.add_weapon_mount(ship_id, WeaponMount.new(laser, WeaponMount.broadside_arc()))
		var chaser := WeaponData.new()
		chaser.id = "bow_chaser"
		chaser.max_range_m = ENERGY_RANGE_M
		chaser.damage_per_hit = ENERGY_DAMAGE
		chaser.recharge_time_s = ENERGY_RECHARGE_S
		world.add_weapon_mount(ship_id, WeaponMount.new(chaser, WeaponMount.bow_chaser_arc()))

static func _make_formation(world: SimulationWorld, formation_id: String, ids: Array) -> void:
	var guide_id: String = ids[0]
	var guide: ShipPhysicsState = world.ships[guide_id]
	var formation: FormationState = world.add_formation(formation_id, guide_id)
	var inv: Quaternion = guide.orientation.inverse()
	var succession: Array = []
	for i in range(1, ids.size()):
		var member_id: String = ids[i]
		var offset_world: Vector3 = world.ships[member_id].position - guide.position
		formation.set_station(member_id, inv * offset_world)
		succession.append(member_id)
	formation.set_succession_order(succession)
