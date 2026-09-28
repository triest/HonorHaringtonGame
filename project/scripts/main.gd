extends Node3D
## Main
##
## Visual prototype bring-up scene: creates a SimulationWorld with a
## small squadron per side (§56.3 item H) on an inertial thrust course,
## each with a procedural hull mesh
## (scripts/hull_mesh_builder.gd) and a live wedge visualization driven by
## ship_defense_state.gd -- the first actually-visible prototype of the
## simulation, not just headless unit tests (ТЗ §56 Milestone 1-3 bring-up).
##
## ТЗ §56.1 item 6 ("Hardcoded 1v1/2v2 scenario vs TacticalAI"): both demo
## ships now have a team assigned (world.set_team, mutually hostile) and
## their weapon mounts are registered directly on `world` via
## world.add_weapon_mount() -- NOT in a separate main.gd-only dict like
## before. That is what makes SimulationWorld._resolve_weapons_ai actually
## select a target and fire each tick: it only ever looks at
## `world.weapon_mounts`/`world.teams`, and target SELECTION for both
## sides already goes through TacticalAI.select_weapon_target (see
## SimulationWorld._resolve_weapon_target) with no separate "AI class" to
## instantiate here. See CHANGELOG.md for the authoritative "done vs not
## done" list.
##
## 2026-09-28 (user: "редактор миссий, чтобы можно было соотношение и
## типы кораблей сторон выбирать"): the whole "build a scenario + wire
## every controller/panel to it" block used to live directly in _ready().
## It is now `_start_mission(setup)`, callable more than once: _ready()
## calls it once with ShipClasses.default_setup() (so every existing
## headless caller -- probes, screenshots, tests -- sees the same 4x4
## scenario immediately, unaffected by any of this), then shows
## MissionEditorPanel on top; confirming a different composition there
## calls `_start_mission(new_setup)` again, which tears down every node
## `_start_mission` created last time (`_teardown_mission()`) and
## `world.reset_ships()`s the simulation before rebuilding. See
## scripts/demo_scenario.gd / scripts/ship_classes.gd / scripts/
## mission_editor_panel.gd.
##
## WeaponFx (scripts/weapon_fx.gd, ТЗ §56.1 item 3) is wired into the
## per-tick loop below and now has something to actually draw: with teams
## assigned and mounts registered on `world`, SimulationWorld.
## last_tick_weapon_shots is populated live once both ships are in range
## and a mount comes off cooldown.

var world: SimulationWorld
var hulls: Dictionary = {}  # String ship_id -> HullState (local, illustrative only -- NOT passed to world.hulls; see world.add_ship's optional hull param, unused here)
var weapon_fx: WeaponFx
var hud: Hud
var tactical_plot: TacticalPlot
## §56.3 item A: single shared selection, injected into TacticalPlot (and
## future §56.3 UI -- squadron list, order menu) below -- see
## selection_state.gd's own doc comment for why this lives here rather
## than inside any one view. Recreated fresh by every _start_mission()
## call (old selected/designated ids would just point at a ship-less
## world after a rebuild).
var selection: SelectionState
## §56.3 item B: translates the group hotkey (G) into real
## FormationState/CommandEchelon structure from `selection` -- see that
## script's own doc comment. Owns no rendering; command_group_panel
## below is the readout of what it writes.
var command_group_controller: CommandGroupController
## §56.3 item B: left-side "squadron list" readout of
## world.command_echelons/world.formations, see that script's own doc
## comment for the interim layout choice.
var command_group_panel: CommandGroupPanel
## §56.3 item C: RMB-on-plot move order routing -- see that script's own
## doc comment. Same shared world/selection as command_group_controller
## above, plus `player_team` (below) so it never lets the player order an
## enemy AI ship around.
var move_order_controller: MoveOrderController
## §56.3 item D: same shared world/selection/player_team convention as
## move_order_controller above; also reuses move_order_controller itself
## for its APPROACH entry (see order_menu_controller.gd's own doc
## comment). `order_menu` is the visible popup this controller drives.
var order_menu_controller: OrderMenuController
var order_menu: OrderMenu
## §56.3 item E: same shared world/selection/player_team convention as
## move_order_controller/order_menu_controller above -- see that
## script's own doc comment for the panel's visibility rule and honest
## gaps. `weapon_panel` is the persistent (non-modal) side panel this
## controller drives.
var weapon_panel_controller: WeaponPanelController
var weapon_panel: WeaponPanel
## §56.3 item F: quick-center hotkey (project.godot [input]
## "camera_focus_selection") -- see that script's own doc comment. Same
## shared world/selection as the other §56.3 controllers above, plus a
## reference to the scene's own OrbitCamera (see _frame_camera_on_ships,
## unchanged by this item other than the camera it already framed now
## also being reachable from here).
var camera_focus_controller: CameraFocusController
var player_input: PlayerInput
## 2026-09-27 live feedback: screen-space tactical symbols + mouse
## selection/orders over the 3D view, and a bottom bar of real buttons.
var battle_overlay: BattleOverlay
var command_bar: CommandBar
var battle_log: BattleLogPanel
var ship_cards: ShipCardsPanel
var mission_panel: MissionPanel
var win_lose_screen: WinLoseScreen
## 2026-09-28: the mission-editor overlay (see class doc above) and the
## composition it last confirmed -- kept around so a later pass could read
## "what's actually in play" without re-deriving it from world.teams.
var mission_editor: MissionEditorPanel
var current_setup: Dictionary = {}

## ТЗ §56.1 item 4 (Minimal HUD): which ship the single HUD panel is a
## point of view for. "alpha" is always the RED side's flagship/guide --
## DemoScenario._make_ids() guarantees this regardless of composition
## (HUD_POV_SHIP_ID, PlayerInput's default, and several unit tests' doc
## comments all still refer to exactly this id).
const HUD_POV_SHIP_ID: String = "alpha"

func _ready() -> void:
	world = SimulationWorld.new()
	add_child(world)
	world.clock.simulation_tick.connect(_on_tick)

	_start_mission(ShipClasses.default_setup())

	# 2026-09-28: the mission editor shows ON TOP of the mission
	# `_start_mission()` above already built and paused (via its own
	## briefing pause) -- every existing headless caller that never
	# interacts with UI (probes, screenshot_capture.gd, test_camera_views.
	# gd) sees exactly the same ships/state it always did, one frame in.
	# A live player sees the editor first, adjusts composition, and
	# confirming rebuilds via _start_mission() again.
	mission_editor = MissionEditorPanel.new()
	mission_editor.on_confirm = Callable(self, "_start_mission")
	add_child(mission_editor)

	# 2026-09-23 live bug report (§56.1 items 4/5, see .tools/state.md/
	# CHANGELOG.md for that date): user ran the exported Windows .exe and
	# got a rendered 3D scene with ships firing on each other, but NO HUD
	# text and NO keys/mouse doing anything at all. Investigation that
	# pass found Hud/PlayerInput's own scripting logic correct -- reproduced
	# both in pure --headless (simulation/tests/test_hud.gd,
	# simulation/tests/test_player_input.gd) and in an actual Xvfb-rendered
	# run (real OpenGL display: HudLabel came up visible with real text,
	# and an injected keypress DID reach PlayerInput and change ship
	# state) -- so nothing in this file or Hud/PlayerInput was actually
	# broken. The leading remaining hypothesis for what a live user would
	# see as "nothing responds" is the OS-level game window simply not
	# having input focus when it first opens (a known category of
	# Godot/Windows export quirk -- e.g. a SmartScreen prompt or the
	# console wizard window stealing focus at launch); that can only be
	# observed live, never from this headless-only environment, so this
	# call is a defensive best-effort fix, not a confirmed root-cause fix.
	# Harmless everywhere else (a no-op if the window already has focus,
	# and both calls are silently safe under --headless/dummy display --
	# see simulation/tests -- so this does not risk breaking the existing
	# headless smoke checks).
	get_window().grab_focus()
	DisplayServer.window_move_to_foreground()

## Frees every node the LAST _start_mission() call created (ships views +
## every controller/panel below) and wipes the simulation itself
## (world.reset_ships()) so the next _start_mission() call rebuilds onto
## a genuinely clean slate. A no-op the very first time (nothing to tear
## down yet) -- guarded by `weapon_fx == null`, the first field this
## block ever sets, at the caller.
func _teardown_mission() -> void:
	for child in get_children():
		if child is ShipView:
			child.queue_free()
	for n in [weapon_fx, hud, tactical_plot, command_group_controller, command_group_panel,
			move_order_controller, order_menu, order_menu_controller, weapon_panel_controller,
			weapon_panel, camera_focus_controller, player_input, win_lose_screen, battle_overlay,
			command_bar, ship_cards, battle_log, mission_panel]:
		if n != null:
			n.queue_free()
	hulls.clear()
	weapon_fx = null
	hud = null
	tactical_plot = null
	command_group_controller = null
	command_group_panel = null
	move_order_controller = null
	order_menu = null
	order_menu_controller = null
	weapon_panel_controller = null
	weapon_panel = null
	camera_focus_controller = null
	player_input = null
	win_lose_screen = null
	battle_overlay = null
	command_bar = null
	ship_cards = null
	battle_log = null
	mission_panel = null
	world.reset_ships()

## Builds `setup` into `world` (DemoScenario.build) and (re)creates every
## ship view + controller/panel wired to it. This IS the body of the old
## _ready() from "DemoScenario.build(world)" onward, parameterized by
## `setup` and made re-entrant (see _teardown_mission() above) so the
## mission editor can call it again with a different composition.
func _start_mission(setup: Dictionary) -> void:
	if weapon_fx != null:
		_teardown_mission()
	current_setup = setup

	# 2026-09-27: canon-shaped squadron engagement (line-abreast squadrons,
	# bow-on approach from ~5.3M km, missile broadsides + PD + energy
	# mounts on both sides, real HullState so ships can die) -- see
	# scripts/demo_scenario.gd's doc comment for the full why.
	var ids: Dictionary = DemoScenario.build(world, setup)
	var red_ids: Array = ids["red_ids"]
	var blue_ids: Array = ids["blue_ids"]

	for ship_id in world.ships.keys():
		var view := ShipView.new()
		view.bind(world.ships[ship_id])  # builds its own procedural hull + wedge planes
		add_child(view)
		hulls[ship_id] = world.hulls.get(ship_id)

	weapon_fx = WeaponFx.new()
	add_child(weapon_fx)

	hud = Hud.new()
	add_child(hud)

	# ТЗ §56.2 items A/B (tactical plot): same POV ship as Hud below --
	# see tactical_plot.gd's own doc comment for why it reads
	# world.sensor_contacts (not world.ships/world.missiles directly).
	selection = SelectionState.new()

	tactical_plot = TacticalPlot.new()
	tactical_plot.selection = selection
	add_child(tactical_plot)

	# §56.3 item B: same shared `selection`/`world` as tactical_plot
	# above -- no second selection or command-structure mechanism.
	command_group_controller = CommandGroupController.new()
	command_group_controller.world = world
	command_group_controller.selection = selection
	add_child(command_group_controller)

	command_group_panel = CommandGroupPanel.new()
	add_child(command_group_panel)

	# The player always commands "red" (Manticore) regardless of chosen
	# composition -- the editor only varies ship counts/types per side,
	# never which side the player is on.
	var player_team: String = "red"

	# §56.3 item C: same shared world/selection as command_group_controller
	# above.
	move_order_controller = MoveOrderController.new()
	move_order_controller.world = world
	move_order_controller.selection = selection
	move_order_controller.player_team = player_team
	add_child(move_order_controller)
	tactical_plot.move_order_controller = move_order_controller

	# §56.3 item D: the order-menu popup itself must be added to the tree
	# AFTER tactical_plot (see order_menu.gd's own doc comment on why
	# sibling order controls input priority -- this makes the menu
	# properly modal over the plot once opened) so it draws/intercepts
	# input on top of it, never the other way around.
	order_menu = OrderMenu.new()
	add_child(order_menu)

	order_menu_controller = OrderMenuController.new()
	order_menu_controller.world = world
	order_menu_controller.selection = selection
	order_menu_controller.player_team = player_team
	order_menu_controller.move_order_controller = move_order_controller
	add_child(order_menu_controller)
	tactical_plot.order_menu_controller = order_menu_controller
	order_menu.controller = order_menu_controller

	# §56.3 item E: weapon-type selection panel for the currently
	# (singly-)selected own ship -- same shared world/selection/
	# player_team as move_order_controller/order_menu_controller above.
	weapon_panel_controller = WeaponPanelController.new()
	weapon_panel_controller.world = world
	weapon_panel_controller.selection = selection
	weapon_panel_controller.player_team = player_team
	add_child(weapon_panel_controller)

	weapon_panel = WeaponPanel.new()
	weapon_panel.controller = weapon_panel_controller
	add_child(weapon_panel)

	# §56.3 item F: quick-center hotkey -- same shared world/selection as
	# every other §56.3 controller above.
	camera_focus_controller = CameraFocusController.new()
	camera_focus_controller.world = world
	camera_focus_controller.selection = selection
	camera_focus_controller.camera = get_node_or_null("Camera3D") as OrbitCamera
	add_child(camera_focus_controller)

	# ТЗ §56.1 item 5 (Order input wiring): translates hotkeys (project.
	# godot [input], see PlayerInput's own doc comment) into calls on
	# `world`'s existing transmit_*/order APIs.
	player_input = PlayerInput.new()
	player_input.world = world
	add_child(player_input)

	# ТЗ §56.1 item 7 (Win/lose screen): same per-tick pure-readout
	# convention as WeaponFx/Hud above (§42, ready before the tick-signal
	# connect below so it exists before the first _on_tick call). Kept
	# hidden (see below) -- superseded on-screen by MissionPanel's debrief.
	win_lose_screen = WinLoseScreen.new()
	add_child(win_lose_screen)
	win_lose_screen.visible = false

	battle_overlay = BattleOverlay.new()
	battle_overlay.world = world
	battle_overlay.selection = selection
	battle_overlay.camera = get_node_or_null("Camera3D") as Camera3D
	battle_overlay.player_team = player_team
	battle_overlay.move_order_controller = move_order_controller
	battle_overlay.order_menu_controller = order_menu_controller
	battle_overlay.camera_focus_controller = camera_focus_controller
	add_child(battle_overlay)
	# Drawn under the other Controls (plot, menus): move to the front of
	# the Control draw order, i.e. index right after the world node.
	move_child(battle_overlay, 1)

	command_bar = CommandBar.new()
	command_bar.world = world
	command_bar.selection = selection
	command_bar.player_team = player_team
	command_bar.command_group_controller = command_group_controller
	command_bar.tactical_plot = tactical_plot
	command_bar.camera_focus_controller = camera_focus_controller
	add_child(command_bar)

	# 2026-09-27 (user feedback #3): the old debug text dumps (Hud, command
	# group list) are replaced on screen by per-ship cards and a battle log.
	# The old nodes stay in the tree (their tests/logic unchanged), hidden.
	hud.visible = false
	command_group_panel.visible = false
	ship_cards = ShipCardsPanel.new()
	ship_cards.world = world
	ship_cards.selection = selection
	ship_cards.player_team = player_team
	ship_cards.camera_focus_controller = camera_focus_controller
	add_child(ship_cards)
	battle_log = BattleLogPanel.new()
	battle_log.world = world
	battle_log.player_team = player_team
	add_child(battle_log)
	command_bar.battle_log = battle_log

	# Live-game clock tuning (defaults off for tests, see SimClock.advance):
	# coarser ticks at high time scales + a per-frame CPU budget so 25x/100x
	# stay responsive with hundreds of missiles in flight.
	world.clock.max_dt_multiplier = 50
	world.clock.frame_budget_ms = 10.0
	# Start on the whole squadron selected, at 5x: the opening approach is
	# minutes of sim time before missile range.
	selection.select_only(red_ids.duplicate())
	world.clock.set_time_scale(5.0)

	# Floating render origin + free zoom down to a single hull (see
	# RenderOrigin / OrbitCamera.use_floating_origin). Camera runs after
	# the simulation tick (world._process) and ship views after the camera,
	# so a followed ship is drawn at this frame's position, not last frame's.
	var cam := get_node_or_null("Camera3D") as OrbitCamera
	if cam != null:
		cam.use_floating_origin = true
		cam.process_priority = 10
	for child in get_children():
		if child is ShipView:
			child.process_priority = 20

	_frame_camera_on_ships()

	# 2026-09-27 (user: story/canon, "confusing view"): mission briefing
	# (pauses until "К бою"), debrief with stats at the end, and the
	# battle opens on our own squadron (the line and the direction of the
	# enemy visible, the whole-battle view one keypress away: F1 / Esc).
	mission_panel = MissionPanel.new()
	mission_panel.world = world
	mission_panel.player_team = player_team
	mission_panel.briefing_title = DemoScenario.MISSION_TITLE
	mission_panel.briefing_bbcode = DemoScenario.mission_briefing(setup, red_ids, blue_ids)
	add_child(mission_panel)
	if OS.get_environment("SKIP_BRIEFING") != "1":
		mission_panel.show_briefing()
	camera_focus_controller.view_own_squadron()

## NOTE on ordering: SimulationWorld itself connects to `world.clock.
## simulation_tick` in ITS OWN _ready() (simulation_world.gd), which runs
## synchronously during `add_child(world)` in _ready() above -- BEFORE
## this file's own connect() call a few lines later. Godot calls a
## signal's listeners in connection order, so world.tick_simulation()
## (which rebuilds last_tick_weapon_shots for this tick, AND advances
## world.weapon_mounts' condition sync) has already run by the time this
## handler fires, and weapon_fx.update() below is reading this tick's
## fresh data, not last tick's. Every field read here is reassigned by
## _start_mission(), never by _ready() directly, so a mission rebuild is
## always atomic from this handler's point of view (see _start_mission's
## own doc comment).
##
## Cooldown advance for `world.weapon_mounts` (WeaponMount.tick(dt)) is
## deliberately still done HERE, not inside SimulationWorld.
## tick_simulation() -- see weapon_mount.gd: "Call once per fixed
## simulation tick to advance cooldown" is the mount's own contract, and
## SimulationWorld never calls it itself (missile tubes are the odd one
## out: _resolve_missile_launch_ai already advances those). Skipping this
## loop would leave every mount's cooldown stuck at whatever
## trigger_cooldown() last set it to, so a mount would fire once and then
## never again.
func _on_tick(dt: float, _tick: int, _sim_time: float) -> void:
	for ship_id in world.weapon_mounts.keys():
		for mount in world.weapon_mounts[ship_id]:
			mount.tick(dt)
	weapon_fx.update(world)
	hud.update(world, HUD_POV_SHIP_ID)
	tactical_plot.update(world, HUD_POV_SHIP_ID)
	# §56.3 item F: Hud's own current measured height feeds
	# CommandGroupPanel's position -- see that script's own doc comment
	# for why this replaces a previously-independent fixed guess.
	command_group_panel.update(world, selection, hud.get_bottom_y())
	move_order_controller.prune_completed()
	order_menu.sync()
	weapon_panel_controller.sync()
	weapon_panel.bottom_reserved_px = command_bar.get_height()
	battle_log.bottom_reserved_px = command_bar.get_height()
	weapon_panel.sync()
	win_lose_screen.update(world)

## Points the scene's OrbitCamera at the midpoint between the two demo
## ships from a distance proportional to their separation, computed from
## actual ship positions rather than a hand-tuned fixed transform in the
## .tscn (which, on inspection, was aimed along -Z without ever pointing
## at the ships -- a Milestone 1 oversight since headless test runs
## cannot verify framing visually; fixed now that this is meant to
## actually be looked at).
##
## ТЗ §56.1 item 1: the camera used to be fixed after this initial framing
## shot; OrbitCamera (scripts/orbit_camera.gd) now lets the player orbit/
## zoom from here. This function only sets the STARTING pivot/framing --
## all player-driven movement lives in OrbitCamera itself, so main.gd
## still never touches per-frame camera transforms.
func _frame_camera_on_ships() -> void:
	var camera: Camera3D = get_node_or_null("Camera3D")
	if camera == null:
		return

	var positions: Array = []
	for ship_id in world.ships.keys():
		positions.append(world.ships[ship_id].position)
	if positions.is_empty():
		return

	var midpoint: Vector3 = Vector3.ZERO
	for p in positions:
		midpoint += p
	midpoint /= positions.size()

	var spread: float = 1.0
	for p in positions:
		spread = maxf(spread, midpoint.distance_to(p))

	if camera.has_method("frame_on"):
		camera.frame_on(midpoint, spread)
		return

	# Fallback for a plain Camera3D with no OrbitCamera script attached
	# (e.g. a dev/test scene that reuses this function) -- reproduces the
	# pre-OrbitCamera fixed-framing behavior exactly.
	camera.fov = 60.0
	var half_fov_rad: float = deg_to_rad(camera.fov * 0.5)
	var required_distance: float = (spread / tan(half_fov_rad)) * 1.6
	var view_dir := Vector3(0.15, 0.45, 1.0).normalized()
	camera.global_position = midpoint + view_dir * required_distance
	camera.look_at(midpoint, Vector3.UP)
	camera.far = required_distance * 3.0 + 10000.0
