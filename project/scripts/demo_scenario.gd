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
## squadron engagement): two squadrons, each in line-abreast formation (a
## real FormationState with the flagship as guide, red's also a
## player-commandable CommandEchelon "Squadron 1"), approaching bow-on
## from ~5.3 million km. Both sides carry multi-tube missile broadsides
## that open fire at ~5 million km, point defense, and energy weapons whose
## range only matters if the squadrons actually close.
##
## 2026-09-28 (user: "сделай редактор миссий, чтобы можно было выбирать
## соотношение и типы кораблей сторон"): `build()` now takes an optional
## `setup` -- {"red": [{"class_id","count"}, ...], "blue": [...]} (see
## ShipClasses) -- instead of a hardcoded 4-vs-4. Calling `build(world)`
## with NO setup (every existing headless caller: probes, tests) still
## gets exactly the old fixed 4x4 heavy-cruiser scenario, unchanged, via
## ShipClasses.default_setup().
##
## All figures are labelled ASSUMPTION (see ASSUMPTIONS.md "canon-shaped
## demo scenario"): the missile drive itself (46,000 g x 180 s, ~7.3M km
## powered envelope) is the project's existing MissileState default, NOT
## changed here; everything else is scenario tuning so the engagement
## plays out like the books' opening phase rather than a claim of exact
## canon numbers.
##
## Kept as a pure, scene-free builder so it is headless-testable -- main.gd
## only calls build() and then attaches views to whatever ships exist.
class_name DemoScenario

const SEPARATION_M: float = 5.3e9            # 5.3 million km between squadron centres at t=0
const INITIAL_CLOSING_SPEED_MPS: float = 3.0e5  # each side already moving 300 km/s toward the other
const LINE_SPACING_M: float = 20_000.0       # 20 km between ships abreast
const SENSOR_RANGE_M: float = 1.0e10         # 10 million km: gravitic detection of impeller wedges + missile telemetry link (ASSUMPTION)

const MISSILE_RELOAD_S_DEFAULT: float = 20.0  # unused directly -- per-class reload_s comes from ShipClasses; kept only as a doc anchor for that field's meaning
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
## Counter-missile launcher figures (ASSUMPTIONS.md "контрракеты"): a CM is
## launched when a hostile missile aimed at the fleet is within
## CM_ENGAGE_RANGE_M of the launching ship; a tube cycles every CM_RELOAD_S.
const CM_ENGAGE_RANGE_M: float = 1.6e9       # 1.6 million km
const CM_RELOAD_S: float = 3.0
static var _cm_stock_mult: float = 1.0
static var _cm_side_mult: float = 1.0

## Scenario/tuning hook (also used by probes): multiplier on every ship's
## counter-missile rounds. Reset to the scenario's own value by build().
static func set_cm_stock_mult(m: float) -> void:
	_cm_stock_mult = m
const PD_RANGE_M: float = 2.0e8              # 200,000 km
const PD_REACTION_S: float = 0.7
const PD_RECHARGE_S: float = 0.5

const ENERGY_RANGE_M: float = 4.0e8          # 400,000 km
const ENERGY_DAMAGE: float = 150.0
const ENERGY_RECHARGE_S: float = 6.0

const PLAYER_ECHELON_ID: String = "red_squadron"
const PLAYER_FORMATION_ID: String = "red_line"
const ENEMY_FORMATION_ID: String = "blue_line"

const MISSION_TITLE: String = "Перехват у Сент-Лорана"

## Lateral (X) slot per index, centred on the line -- flagship (index 0)
## sits nearest the middle, same visual convention regardless of how many
## ships are in the line.
static func _slot_x(i: int, count: int) -> float:
	return (float(i) - float(count - 1) * 0.5) * LINE_SPACING_M

## Builds the scenario into `world` per `setup` (see ShipClasses for its
## shape); an empty/omitted `setup` uses ShipClasses.default_setup() -- the
## original fixed 4x4 heavy-cruiser mission, byte-for-byte. Returns
## {"red_ids": Array[String], "blue_ids": Array[String]} -- the actual ids
## built, in formation order (index 0 = flagship/guide of that side).
static func build(world: SimulationWorld, setup: Dictionary = {}) -> Dictionary:
	# 2026-09-29: `setup["scenario"]` (a Scenarios.ORDER id) selects the
	# initial geometry / doctrine / counter-missile stock; missing = the
	# original "intercept" scenario, and a missing red/blue composition
	# falls back to that scenario's own default force (for "intercept" that
	# is exactly ShipClasses.default_setup(), the old 4x4 heavy cruisers).
	var scenario_id: String = String(setup.get("scenario", "intercept"))
	if not Scenarios.DATA.has(scenario_id):
		scenario_id = "intercept"
	var scn: Dictionary = Scenarios.get_data(scenario_id)
	var scn_setup: Dictionary = Scenarios.default_setup_for(scenario_id)
	if setup.is_empty():
		setup = ShipClasses.default_setup()
	if not setup.has("red"):
		setup["red"] = scn_setup["red"]
	if not setup.has("blue"):
		setup["blue"] = scn_setup["blue"]

	var red_classes: Array = ShipClasses.flatten_side(setup.get("red", []))
	var blue_classes: Array = ShipClasses.flatten_side(setup.get("blue", []))
	if red_classes.is_empty():
		red_classes = ShipClasses.flatten_side(ShipClasses.default_setup()["red"])
	if blue_classes.is_empty():
		blue_classes = ShipClasses.flatten_side(ShipClasses.default_setup()["blue"])

	# Ship ids: "alpha"/"beta" stay the flagships/guides regardless of
	# composition (HUD_POV_SHIP_ID, PlayerInput and older tests all refer
	# to exactly these two ids) -- "alpha_2".."alpha_N" / "beta_2".."beta_M"
	# for the rest, same convention the fixed 4x4 scenario always used.
	var red_ids: Array = _make_ids("alpha", red_classes.size())
	var blue_ids: Array = _make_ids("beta", blue_classes.size())

	var red_names: Array = ShipClasses.names_for("red", red_ids.size())
	var blue_names: Array = ShipClasses.names_for("blue", blue_ids.size())
	var display_names: Dictionary = {}
	for i in range(red_ids.size()):
		display_names[red_ids[i]] = red_names[i]
	for i in range(blue_ids.size()):
		display_names[blue_ids[i]] = blue_names[i]
	ShipNames.names = display_names
	ShipNames.ship_class.clear()
	for i in range(red_ids.size()):
		ShipNames.ship_class[red_ids[i]] = red_classes[i]
	for i in range(blue_ids.size()):
		ShipNames.ship_class[blue_ids[i]] = blue_classes[i]

	world.sensor_range_m = SENSOR_RANGE_M
	world.player_controlled_teams["red"] = true
	world.subsystem_damage_model = true
	var rng := RandomNumberGenerator.new()
	rng.seed = 1904
	SubsystemDamageResolution.spread_rng = rng
	SubsystemDamageResolution.structural_share_override = 0.1
	world.missile_sensor_update_interval_ticks = 6
	world.missile_detonation_range_override_m = LASERHEAD_TERMINAL_RANGE_M
	world.missile_max_lifetime_override_s = MISSILE_MAX_LIFETIME_S
	world.missile_zem_guidance = true
	# Combat attitude (see SimulationWorld.ship_attitude): default
	# "broadside" for both sides (the book's classic missile duel,
	# broadside to broadside); "auto"/"wedge" are the player's choices.
	# The player can override per ship from the command bar.
	var env_att: String = OS.get_environment("DEMO_ATTITUDE")
	for sid in red_ids:
		world.set_ship_attitude(sid, env_att if env_att != "" else String(scn["red_attitude"]))
	for sid in blue_ids:
		world.set_ship_attitude(sid, env_att if env_att != "" else String(scn["blue_attitude"]))

	# Player squadron starts at the world origin (not symmetric about it):
	# float32 positions are most precise near 0, and the player zooms into
	# their own ships far more than the enemy's (see RenderOrigin).
	_build_side(world, red_ids, red_classes, "red", Vector3.ZERO, Scenarios.red_yaw_rad(scenario_id), float(scn["red_speed"]), float(scn["red_thrust"]), float(scn["red_cm_mult"]) * _cm_stock_mult)
	_build_side(world, blue_ids, blue_classes, "blue", Scenarios.blue_center(scenario_id), Scenarios.blue_yaw_rad(scenario_id), float(scn["blue_speed"]), float(scn["blue_thrust"]), float(scn["blue_cm_mult"]) * _cm_stock_mult)
	for bid in blue_ids:
		world.set_ship_cm_policy(bid, String(scn["blue_cm_policy"]))
	_make_formation(world, PLAYER_FORMATION_ID, red_ids)
	_make_formation(world, ENEMY_FORMATION_ID, blue_ids)
	world.add_command_echelon(PLAYER_ECHELON_ID, "Squadron 1")
	world.attach_formation_to_echelon(PLAYER_ECHELON_ID, PLAYER_FORMATION_ID)

	return {"red_ids": red_ids, "blue_ids": blue_ids}

static func _make_ids(prefix: String, count: int) -> Array:
	var ids: Array = []
	for i in range(count):
		ids.append(prefix if i == 0 else "%s_%d" % [prefix, i + 1])
	return ids

## Human-readable Russian force-composition line, e.g. "4 тяжёлых крейсера"
## or "2 эсминца, 1 лёгкий крейсер" for a mixed side -- used by the
## briefing text so it always describes what was actually picked, not a
## fixed "4 heavy cruisers" sentence.
static func _composition_text(side_setup: Array) -> String:
	var parts: Array = []
	for entry in side_setup:
		var n: int = int(entry.get("count", 0))
		if n <= 0:
			continue
		parts.append("%d %s" % [n, ShipClasses.label(String(entry.get("class_id", "heavy_cruiser")))])
	if parts.is_empty():
		return "неизвестного состава"
	return ", ".join(parts)

## Scenario title for the briefing panel / mission editor.
static func title_for(setup: Dictionary) -> String:
	return Scenarios.title_of(String(setup.get("scenario", "intercept")))

## Briefing text templated with the ACTUAL chosen composition (both
## sides), the flagship names build() just generated and the chosen
## scenario's situation/geometry/task paragraphs -- called by main.gd
## right after build() returns, using the same `setup` passed in.
static func mission_briefing(setup: Dictionary, red_ids: Array, blue_ids: Array) -> String:
	var scn: Dictionary = Scenarios.get_data(String(setup.get("scenario", "intercept")))
	var red_flag: String = ShipNames.of(red_ids[0])
	var blue_flag: String = ShipNames.of(blue_ids[0])
	var red_comp: String = _composition_text(setup.get("red", []))
	var blue_comp: String = _composition_text(setup.get("blue", []))
	var situation: String = String(scn["situation"]).replace("{blue}", blue_comp).replace("{red}", red_comp)
	var red_cm: int = ShipClasses.side_cm_stock(setup.get("red", []))
	var blue_cm: int = ShipClasses.side_cm_stock(setup.get("blue", []))
	red_cm = int(round(float(red_cm) * float(scn["red_cm_mult"])))
	blue_cm = int(round(float(blue_cm) * float(scn["blue_cm_mult"])))
	return """[b]%s[/b]

%s

[b]Ваши силы:[/b] эскадра Королевского флота Мантикоры (%s), флагман — [color=#8cf2ff]%s[/color]. Строй — фронт, дистанция между кораблями 20 км.
[b]Противник:[/b] %s, флагман — [color=#ff6a5a]%s[/color]. %s

[b]Задача:[/b] %s

[b]Обстановка боя:[/b] ракеты с лазерными боеголовками бьют с миллионов км. Клин (импеллерное поле) над и под кораблём непробиваем — но пока корабль повёрнут к врагу клином, его собственные трубы молчат. Борт прикрыт боковой стеной, она ослабляет, но не останавливает лазерные головки. Лазерная ПРО сбивает часть залпа на последних секундах. Лучевое оружие вступит в дело, только если сойтись на 400 тыс. км.

[b]Контрракеты:[/b] у каждого корабля ограниченный запас (у вас ~%d на эскадру, у противника ~%d). Пуск автоматический, но вы решаете, на что их тратить: АВТО — по любой ракете, ТОЛЬКО ФЛАГМАН — по ракетам, идущим на флагман, ТОЛЬКО ЗАЛПЫ — по крупным залпам от 10 ракет, СТОП — беречь. Кончились — остаётся одна ПРО.

[b]Управление:[/b] ЛКМ — выделить (рамкой — несколько), ЛКМ по врагу — приказ, ПКМ — курс в точку. F — камера к кораблю, F2 — эскадра, F1 — весь бой, Esc — назад. Space — пауза, [ ] — скорость времени. Кнопки приказов — внизу.""" % [String(scn["place"]), situation, red_comp, red_flag, blue_comp, blue_flag, String(scn["geometry"]), String(scn["task"]), red_cm, blue_cm]

static func _build_side(world: SimulationWorld, ids: Array, class_ids: Array, team: String, center: Vector3, yaw_rad: float, speed: float, thrust_frac: float, cm_mult: float) -> void:
	_cm_side_mult = cm_mult
	var heading: Vector3 = Scenarios.heading_of(yaw_rad)
	var orient: Quaternion = Quaternion.IDENTITY
	var y: float = fposmod(yaw_rad, TAU)  # -PI and PI are the same heading
	var axis_aligned: bool = y < 1e-6 or absf(y - TAU) < 1e-6 or absf(y - PI) < 1e-6
	if absf(y - PI) < 1e-6:
		orient = Quaternion(Vector3.UP, PI)
	elif not axis_aligned:
		orient = Quaternion(Vector3.UP, -yaw_rad)
	var lateral: Vector3 = Vector3(1, 0, 0)
	if not axis_aligned:
		lateral = orient * Vector3(1, 0, 0)
	var count: int = ids.size()
	for i in range(count):
		var ship_id: String = ids[i]
		var cls: Dictionary = ShipClasses.CLASSES[class_ids[i]]
		var phys := ShipPhysicsState.new()
		phys.position = center + lateral * _slot_x(i, count)
		phys.orientation = orient
		phys.velocity = heading * speed
		# Accelerating along the heading at a fraction of rated max (canon
		# squadrons hold back a margin below the slowest ship's maximum so
		# members have thrust left over to keep station -- ASSUMPTION).
		phys.commanded_thrust_local = Vector3(0.0, 0.0, -thrust_frac)
		phys.mass_kg = cls["mass_kg"]
		phys.max_thrust_n = cls["max_thrust_n"]
		phys.max_angular_speed_rad_s = cls["max_angular_speed_rad_s"]
		phys.defense = ShipDefenseState.new()
		phys.defense.laserhead_sidewall_floor = LASERHEAD_SIDEWALL_FLOOR
		phys.subsystems = ShipSubsystems.new()
		# 2026-09-27 fix (found while chasing "the battle feels static/
		# boring"): a REAL bug, not a style nit. §25.1 says never show the
		# player a hit-point bar -- it does NOT say the engine can't use one
		# internally. Every "AI must ... respond to damage, retreat,
		# disengage" (§26) call in simulation_world.gd/tactical_ai.gd reads
		# `world.hulls[ship_id]`, not the subsystem model, so a HullState
		# is still registered here -- never read by the UI (ShipStatus/
		# ShipCardsPanel never touch world.hulls) -- kept in lockstep with
		# the ship's own STRUCTURAL_INTEGRITY condition every tick (see
		# _apply_extended_subsystem_effects in simulation_world.gd).
		var hull := HullState.new()
		world.add_ship(ship_id, phys, hull)
		world.set_team(ship_id, team)

		for _t in range(int(cls["tubes"])):
			var tube := MissileTube.new()
			tube.ammo_count = int(cls["rounds_per_tube"])
			tube.reload_time_s = float(cls["reload_s"])
			tube.max_range_m = MISSILE_LAUNCH_RANGE_M
			world.add_missile_tube(ship_id, tube)

		# 2026-09-29: counter-missile magazine (scarce, see SimulationWorld
		# cm_tubes). `cm_stock_mult` (scenario) scales rounds per tube.
		for _k in range(int(cls.get("cm_tubes", 0))):
			var cmt := MissileTube.new()
			cmt.ammo_count = maxi(0, int(round(float(cls.get("cm_rounds_per_tube", 0)) * _cm_side_mult)))
			cmt.reload_time_s = CM_RELOAD_S
			cmt.max_range_m = CM_ENGAGE_RANGE_M
			world.add_cm_tube(ship_id, cmt)

		for _p in range(int(cls["pd_mounts"])):
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
		for _e in range(int(cls["energy_broadside"])):
			world.add_weapon_mount(ship_id, WeaponMount.new(laser, WeaponMount.broadside_arc()))
		var chaser := WeaponData.new()
		chaser.id = "bow_chaser"
		chaser.max_range_m = ENERGY_RANGE_M
		chaser.damage_per_hit = ENERGY_DAMAGE
		chaser.recharge_time_s = ENERGY_RECHARGE_S
		for _c in range(int(cls["energy_bow"])):
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
