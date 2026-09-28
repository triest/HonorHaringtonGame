# Honorverse dev state (updated every pass)
Phase: §56.3 full tactical command UI (REPLACES §56.2 as top priority; §56.2's finished pieces are the foundation, not discarded)
Context: user rejected §56.2's result as too minimal/single-ship and supplied a detailed
UI spec (AGENTS.md §56.3, verbatim from project's CHATGPT.md) plus a reference image at
docs/reference/tactical_command_ui_reference.png (VIEW THIS IMAGE FIRST -- it is the visual
target: fleet-view squadron list + tactical-plot minimap on top, closer 3D view with
weapon/order panels on bottom). Read AGENTS.md §56.3 and CLOUD.md §1.10 in full before
starting a NEW lettered item you haven't touched yet -- they are long and detailed, do not
skim; you don't need to re-read them just to resume mid-item (see §0 of this file's own
skill instructions).
What already exists from §56.2/§56.3 items A-D (do NOT rebuild, extend it):
  - Tactical plot base with IFF-colored contact icons + velocity vectors (scripts, see
    prior CHANGELOG entries for exact file names)
  - Missile tracks shown distinctly from ship contacts
  - Mouse click-to-select AND multi-select (Ctrl/Shift/drag-box) on the plot --
    scripts/selection_state.gd (SelectionState), scripts/tactical_plot_selection.gd,
    scripts/tactical_plot.gd's _gui_input handling; main.gd owns the one shared
    SelectionState instance ("selection") -- reuse it, do not create a second one.
  - A canon-scale distance-compression convention (logged in ASSUMPTIONS.md)
  - Subsystem-condition text HUD (from §56.1) as a secondary panel
  - Named command groups: scripts/command_group_controller.gd (CommandGroupController --
    hotkey G / "selection_make_group" input action turns the current 2+-ship own-team
    selection into a real FormationState + leaf CommandEchelon, kind="Squadron N";
    reuses existing SimulationWorld.add_formation/add_command_echelon/
    attach_formation_to_echelon, member stations frozen at current relative position in
    the guide's local frame) + scripts/command_group_panel.gd (CommandGroupPanel --
    read-only left-side text list of world.command_echelons/world.formations, marks
    currently-selected members with ">"). Both wired into main.gd (same world/selection
    instances) and ticked from main.gd._on_tick. Headless-tested only (synthetic 2-4-ship
    worlds in unit tests) -- NOT yet confirmed with a real player (scenario is still 1v1,
    so live grouping of 2+ own ships isn't exercisable yet; item H upgrades that).
    Explicitly NOT done as part of B: disbanding/merging/renaming a group after creation
    -- open follow-up, see ASSUMPTIONS.md "§56.3 item B".
  - RMB move order (item C, this pass): scripts/move_order_controller.gd
    (MoveOrderController) -- RMB-release on the tactical plot (scripts/tactical_plot.gd's
    _on_right_release, via scripts/tactical_plot_projector.gd's new unproject()) issues a
    move order for the current selection. Lone own-team ship not in a formation ->
    IndividualOrder.change_course (already moving) or .change_speed (near-stationary) via
    world.transmit_individual_order_now (comm-delayed, same family as PlayerInput).
    Formation member/guide -> world.issue_formation_order_now(formation_id,
    FormationOrder.approach(...)) -- NOT world.issue_echelon_order (that one only queues,
    no "_now" variant exists yet -- see ASSUMPTIONS.md "§56.3 item C" before "fixing" this
    to go through the echelon). Visualization (course line/arrow/endpoint) is UI-side
    bookkeeping in MoveOrderController.active_move_orders, drawn by
    TacticalPlot._draw_move_orders, pruned by MoveOrderController.prune_completed()
    (called from main.gd._on_tick) on arrival or if the anchor ship is gone. Headless-
    tested only (29 checks, simulation/tests/test_move_order_controller.gd) -- NOT yet
    confirmed with a real player (no live mouse in this environment, and scenario is
    still 1v1 so the FORMATION branch specifically has never been exercised outside a
    synthetic test world either, same caveat as item B).
  - Contextual order menu (item D, this pass): scripts/order_menu_controller.gd
    (OrderMenuController) + scripts/order_menu.gd (OrderMenu, a plain
    hand-drawn Control -- no PopupMenu widget used anywhere in this
    codebase). Interaction: a PLAIN LMB click on a hostile ship contact
    while the current selection already has >=1 own-team ship opens the
    menu WITHOUT replacing the selection (SelectionState.designated_target_id
    is a new, separate single-id field for this -- not a second
    multi-select). OrderMenuController holds NO reference to the OrderMenu
    Control (pure `is_open`/`menu_screen_pos`/`menu_entries` state,
    read once per tick by OrderMenu.sync() from main.gd._on_tick) --
    same §42 division of labor as MoveOrderController/TacticalPlot, kept
    this way specifically so it stays headless-testable. Implemented:
    ATTACK/FOCUS FIRE (transmit_ship_target + weapons_free(true) --
    honestly identical given today's primitives), HOLD FIRE/WEAPONS FREE
    (transmit_ship_weapons_free), APPROACH (reuses
    MoveOrderController.issue_move_order at the target's position, zero
    new order-construction code), WITHDRAW (FormationOrder/IndividualOrder
    .withdraw_orders via the immediate QUEUED api -- NOT transmit_*, see
    ASSUMPTIONS.md "§56.3 item D" for why a 2-order composite can't
    safely go through the comm-delayed "_now" family), MAINTAIN FORMATION
    (issue_formation_order_now HOLD_FORMATION, only offered when a
    selected ship is actually in a formation). NOT implemented, honestly
    omitted from the menu entirely (no backing mechanic exists anywhere
    in simulation/*.gd, confirmed by grep): DEFEND, COVER, FOLLOW,
    INTERCEPT. Headless-tested only (42 checks,
    simulation/tests/test_order_menu_controller.gd) -- NOT yet confirmed
    with a real player (same no-live-mouse caveat as items B/C).
  - Weapon-selection panel (item E, this pass): scripts/weapon_panel_controller.gd
    (WeaponPanelController) + scripts/weapon_panel.gd (WeaponPanel, non-modal --
    unlike OrderMenu it does not cover the full viewport, see that file's own doc
    comment). Visible only when EXACTLY ONE own ship is selected. ENERGY WEAPONS:
    read-only list from world.weapon_mounts. MISSILES (only if tubes exist): salvo
    size (click-to-cycle, capped to tube count) + throttle profile (FULL BURN/
    EXTENDED RANGE, click-to-cycle) are BOTH real -- new optional max_launches/
    throttle_fraction params on world.order_missile_launch/_launch_missile_from_tube
    (both default to old behavior, every existing caller/replay entry unaffected),
    throttle wires the pre-existing but previously-unused MissileState.set_throttle().
    target line reuses SelectionState.designated_target_id as-is (no second target
    concept). POINT DEFENSE (only if PD mounts exist): AUTO/HOLD is a REAL new
    mechanic -- world.ship_pd_hold + set_ship_pd_hold/transmit_ship_pd_hold (same
    comm-delayed convention as transmit_ship_weapons_free), checked by
    _resolve_point_defense (a held ship's PD mounts do not engage at all). Honest
    gaps, NOT shown: missile "type" selection (MissileTube has no type field, no
    ship anywhere has >1 tube type), COUNTER-MISSILES entirely (no automatic
    counter-missile LAUNCH decision exists anywhere in simulation/*.gd -- every
    counter-missile in this codebase is a manually-constructed test double, see
    ASSUMPTIONS.md "§56.3 item E"), PD priority-target designation (TacticalAI.
    select_pd_target has no override parameter). Headless-tested only (36 checks,
    simulation/tests/test_weapon_panel_controller.gd) -- NOT yet confirmed with a
    real player (same no-live-mouse caveat as items B/C/D), AND the MISSILES/POINT
    DEFENSE sections specifically cannot even appear in the live demo scenario yet
    (scripts/main.gd's alpha/beta ships are still energy-only -- item H is what adds
    missile tubes -- so only ENERGY WEAPONS + the panel's visibility gate are
    live-observable today; MISSILES/PD are synthetic-test-only until H lands).
Checklist (§56.3, new scope, roughly in an order that builds incrementally toward the
15-step MVP acceptance test in AGENTS.md §56.3 / §1.10.14):
  [x] A. Multi-select: Ctrl+LMB add to selection, Shift+LMB extend, LMB drag-box select
      multiple contacts. (See CHANGELOG.md 2026-09-23 entry for full detail.)
  [x] B. Selection becomes a named command group (visual list, left-side squadron-list
      panel) -- reuses CommandEchelon/FormationState via CommandGroupController/
      CommandGroupPanel (see "What already exists" above and CHANGELOG.md 2026-09-25
      entry for full detail). Headless-verified only, not live-confirmed.
  [x] C. RMB-on-space move order for the current selection (single ship or group), with a
      visual course line/vector/endpoint per §1.10.6 -- see "What already exists" above
      and CHANGELOG.md 2026-09-26 entry for full detail. Headless-verified only
      (29 checks), not live-confirmed -- see ASSUMPTIONS.md "§56.3 item C" for two
      non-obvious bugs this pass's own test caught and fixed (issue_echelon_order only
      queues; CHANGE_SPEED's is_complete() ignores heading) before anyone gets a chance
      to "simplify" the code back into them.
  [x] D. Contextual order menu after selecting own + designating enemy -- implemented:
      ATTACK, FOCUS FIRE, HOLD FIRE, WEAPONS FREE, APPROACH, WITHDRAW, MAINTAIN FORMATION.
      Honestly NOT implemented/NOT shown in the menu: DEFEND, COVER, FOLLOW, INTERCEPT
      (no backing mechanic anywhere in simulation/*.gd -- see ASSUMPTIONS.md "§56.3 item
      D"). See "What already exists" above and CHANGELOG.md 2026-09-26 entry (second
      2026-09-26 entry, this pass) for full detail. Headless-verified only (42 checks),
      not live-confirmed.
  [x] E. Weapon-type selection panel for the selected ship -- implemented: ENERGY
      WEAPONS (read-only mounted list), MISSILES (salvo size + throttle/profile +
      target readout + FIRE, only shown when tubes exist), POINT DEFENSE (real
      AUTO/HOLD toggle, only shown when PD mounts exist). Honestly NOT
      implemented/NOT shown: missile "type" selection (no type field exists on
      MissileTube), COUNTER-MISSILES entirely (no automatic launch-decision
      mechanic anywhere in simulation/*.gd), PD priority-target designation (no
      override parameter on TacticalAI.select_pd_target) -- see ASSUMPTIONS.md
      "§56.3 item E". See "What already exists" above and CHANGELOG.md 2026-09-26
      entry (item E) for full detail. Headless-verified only (36 checks), not
      live-confirmed -- MISSILES/POINT DEFENSE specifically cannot even appear live
      until item H gives a demo ship missile tubes.
  [x] F. Command camera per §1.10.1: free camera over the battle, can go near-vertical
      top-down, orbit, zoom, quick-center on selected ship/group/contact -- DONE.
      OrbitCamera already covered orbit/near-vertical top-down/zoom (§56.1 item 1);
      this pass added quick-center: new hotkey Home (project.godot [input] action
      "camera_focus_selection") -> scripts/camera_focus.gd (CameraFocus.compute:
      selection -> {pivot, spread} via world.ships/world.missiles TRUE positions,
      own selection beats designated_target_id when both exist) -> scripts/
      camera_focus_controller.gd (CameraFocusController, plain Node +
      _unhandled_input, same pattern as PlayerInput) -> OrbitCamera.focus_on() (new
      method: re-centers pivot + refits distance to the new spread, KEEPS current
      yaw/pitch unlike frame_on(), rebases _base_distance so subsequent zoom is
      relative to the new framing, far only grows never shrinks). Also did the
      first real shared UI-panel layout pass this item's own note named: Hud.
      get_bottom_y() (new, real measured label height) is fed by main.gd._on_tick
      into CommandGroupPanel.update(..., hud_bottom_y) every tick, replacing that
      panel's old hardcoded Vector2(12, 360) guess -- see ASSUMPTIONS.md "§56.3
      item F" for why this is honestly scoped as a FIRST pass (only Hud/
      CommandGroupPanel actually shared a screen region and risked overlapping;
      WeaponPanel/TacticalPlot/OrderMenu each occupy a separate region already and
      were not touched). Headless-tested only (test_camera_focus.gd 17 checks,
      test_camera_focus_controller.gd 5 checks, test_orbit_camera.gd +2,
      test_hud.gd +2, new test_command_group_panel.gd 2 checks) -- NOT live-
      confirmed (OrbitCamera cannot be instantiated outside a live scene tree in
      this headless environment, re-confirmed this pass with a throwaway probe
      script, not just assumed from test_orbit_camera.gd's own older comment; so
      whether Home actually feels good live needs a real player). See
      CHANGELOG.md 2026-09-26 entry (item F) for full detail.
  [x] G. Zoom-level behavior (§1.10.3) -- DONE this pass. Plot (2D minimap) needed no
      change: TacticalPlot.plot_range_m already auto-scales to the farthest live contact
      with no upper bound, so distant contacts were never actually lost there. The 3D
      view (OrbitCamera) had a REAL BUG (not just a gap): `far` was sized off a fixed 3x
      multiplier of required_distance while the scroll-wheel/keyboard zoom-out clamp can
      reach 20x (MAX_DISTANCE_SCALE) -- on a wide enough initial battle framing, scrolling
      all the way out pushed the camera PAST its own far clip plane and blanked the
      ENTIRE 3D view (not "some contacts lost" -- nothing renders once the camera itself
      is beyond far). Fixed with a new pure `_required_far_for_base_distance()` sharing
      the same MAX_DISTANCE_SCALE constant + 1.2x margin, used by both frame_on() and
      focus_on() (far only ever grows, per item F's existing rule). Headless-tested only
      (2 new test_orbit_camera.gd cases spanning base_distance 500m-5,000,000m; full
      regression on test_camera_focus/_controller/hud/command_group_panel all green;
      scene smoke run exit 0, same 16x baseline errors). NOT live-confirmed (same
      OrbitCamera-can't-instantiate-outside-a-scene-tree limitation as item F). Full
      detail: ASSUMPTIONS.md "§56.3 item G", CHANGELOG.md 2026-09-26 "item G" entry.
      Open follow-up logged (not a blocker): far/_base_distance stay fixed at the last
      frame_on()/focus_on() call, so a very long battle where ships drift apart WITHOUT
      the player ever pressing Home again could in principle still outrun the original
      far plane over time -- a separate, slower-moving edge case from the zoom-clamp bug
      just fixed; would need main.gd to feed OrbitCamera live contact distances every
      tick (same pattern TacticalPlot's own auto-scale already uses) to close fully.
  [x] H. Hardcoded demo scenario upgraded from 1v1 to a 3-vs-3 squadron -- DONE this
      pass. scripts/main.gd's `_ready()` now builds ships from a `ship_specs` array
      (id/team/x/z/missile_tubes) instead of two one-off local vars: "alpha"/"beta"
      (the original guides) keep their exact original ids/positions/orientations
      unchanged (HUD_POV_SHIP_ID, PlayerInput's hardcoded player ship, and several
      unit tests' doc comments all still refer to exactly these two ids); new
      alpha_2/alpha_3 (red) and beta_2/beta_3 (blue) are spread +/-1500 m along Z
      around their guide's original X position -- kept well under the 10,000 m X
      separation between sides specifically so AttackGeometry.classify()'s
      dominant-axis pick still resolves every cross-ship pairing to STARBOARD/PORT,
      never BOW/STERN (verified by re-reading attack_geometry.gd's dominant-axis
      logic before picking the 1500 m figure, not just assumed). All 6 ships still
      go through the existing per-ship loop for ShipView/hull/energy weapon mount
      (`world.add_weapon_mount`, unchanged demo_laser/broadside_arc) -- that loop
      already iterated `world.ships.keys()` generically, so it needed no changes
      beyond having more ships to iterate. Every red ship (alpha/alpha_2/alpha_3)
      additionally gets 2 `MissileTube.new()` via `world.add_missile_tube` (engineering-
      placeholder defaults: 10 rounds/tube, 5s reload, 60,000 km range -- trivially in
      range at this scenario's ~10 km separation, and `_resolve_missile_launch_ai`
      requires no extra wiring beyond a non-empty `missile_tubes[ship_id]` entry, same
      target-selection/weapons-free gating as energy mounts). Blue stays energy-only
      (item H only requires "at least one side"; considered ShipFactory + the existing
      medusa_class.tres/sultan_class.tres ShipClassData records per this file's own
      §0 prior guidance, but those are capital-ship-scale loadouts (26-46 missile
      tubes, dozens of energy mounts each) not a fit for a "small squadron" demo --
      kept the existing hand-authored-ship pattern and just added tubes/ship-count to
      it instead of switching the whole demo scenario to the data-driven path, which
      was not part of this item's own scope). This makes items A-D's multi-select/
      group-order behavior actually exercisable live for the first time (2+ own-team
      ships now exist in the live scenario, not just synthetic test worlds) and gives
      item E's MISSILES weapon-panel section something real to show/fire live -- see
      the "What already exists" notes on items B/C/D/E above for the exact "item H
      upgrades that"/"until H lands" caveats this closes; those items' own
      live-player confirmation is still open (no live mouse in this headless
      environment), same honest gap, just no longer blocked ON item H specifically.
      Verified this pass: `godot --headless --import` clean; headless scene smoke
      (`main.tscn --quit-after 120`) exit 0, exactly 48 `mesh_get_surface_count`/
      "Parameter m is null" dummy-renderer baseline errors (16 per ship-pair before
      x3 for the 2-ship-per-side -> 6-ship scenario growth, confirmed by exact count,
      not eyeballed), zero new error types. Fast-visible-result mode still in effect
      (§0/Tests below) -- no full simulation-suite regression run this pass, only the
      headless import/smoke check.
  [x] I. Individual override: within a selected group, pick one ship and give it its own
      order while the rest keep the group order (§1.10.12 worked example) -- DONE this
      pass. Real finding: the SIMULATION side (Milestone 11's individual-order-overrides-
      formation-station-keeping mechanism, world.is_ship_overriding_formation/
      return_ship_to_formation) already fully existed and needed ZERO changes -- the bug
      was purely in MoveOrderController.issue_move_order and
      OrderMenuController._execute_withdraw, which used to treat ANY selected formation
      member as "address the WHOLE formation via its guide" (so selecting one ship and
      giving a move/withdraw order silently redirected the entire group -- the opposite
      of what §1.10.12 asks). Fixed: both now group selected/eligible ids by formation and
      only collapse to one formation-level order when the selection is that formation's
      ENTIRE current membership (new _is_full_formation_membership helper, duplicated in
      both controllers per this codebase's existing small-helper convention); any strict
      subset (most simply, one ship) gets an individual order per selected ship instead,
      leaving every unselected member on the formation's existing order untouched.
      ATTACK/FOCUS FIRE/HOLD FIRE/WEAPONS FREE were NOT affected -- already per-ship via
      transmit_ship_target/transmit_ship_weapons_free, never through FormationState.
      MAINTAIN FORMATION deliberately stays whole-formation (no individual reading makes
      sense for it). Generalized beyond N=1 (also covered: 2-of-3 formation members
      selected -> both get individual overrides, third member untouched). See
      ASSUMPTIONS.md "§56.3 item I" for the full writeup. Tests: test_move_order_
      controller.gd 29->35 checks (old wrong-behavior test rewritten, not just kept),
      test_order_menu_controller.gd 44->48 checks, all passing. Headless import clean;
      scene smoke run exit 0, same 48 baseline dummy-renderer errors, zero new error
      types (expected -- routing-only change, no scenario/ship-count change this pass).
      Windows .exe re-exported (.pck 452032B -> 455776B). Headless-verified only -- NOT
      yet confirmed with a real player/mouse, same standing caveat as every other §56.3
      item (see IMPORTANT note below).
  [ ] J. VISUAL POLISH PASS -- explicit user decision, 2026-09-26, ONLY start this AFTER
      F-I are functionally done: user live-tested items A-E and confirmed they are
      currently bare debug text/dots on a black screen (a tiny corner radar, plain text
      lists) -- nowhere near docs/reference/tactical_command_ui_reference.png's look.
      User was shown this gap directly and explicitly chose "finish F-I (functionality)
      first, visual polish after" over doing polish now. Do NOT get pulled into
      panel/theme/icon work while F-I are still open, even if it would be quick --
      that is exactly the wrong order per this decision. When this item's turn comes:
      replace debug-text/dot placeholders with real Control-based panels reasonably
      close to the reference image (left squadron/group list, proper tactical-plot
      panel with contact icons + range rings instead of a tiny debug radar, bottom
      weapon/order control bar, event/order log panel) -- real Godot Theme/styled-
      Control work, budget real time for it, do not rush.
      SUB-PROGRESS (2026-09-27 pass, still NOT closed -- one sub-piece of several):
      new shared scripts/ui_theme.gd (UiTheme -- panel_stylebox()/ACCENT_COLOR/
      condition_color(), meant to be reused by every other panel in later sub-passes)
      + Hud (scripts/hud.gd) now has a real styled StyleBoxFlat background panel
      (HudBackground) hugging its measured text bounds, cyan accent text matching
      TacticalPlot's own-ship color, instead of bare unstyled text -- see
      ASSUMPTIONS.md "§56.3 item J" and CHANGELOG.md 2026-09-27 entry for full detail.
      SUB-PROGRESS 2 (2026-09-27, second pass): sub-piece (a) DONE --
      CommandGroupPanel now has the same styled background (CommandGroupBackground,
      UiTheme.panel_stylebox(), accent text + outline, new get_bottom_y()); test_
      command_group_panel.gd 5->13 checks green. Remaining: (b), (c) below.
      OrderMenu/WeaponPanel/TacticalPlot's own chrome NOT touched
      yet -- next sub-piece candidates, in no particular required order: (a) apply
      UiTheme.panel_stylebox() to CommandGroupPanel the same way (quickest, same
      pattern just established for Hud), (b) OrderMenu/WeaponPanel backgrounds+
      borders, (c) actually reflow the screen layout toward the reference image's
      composition (squadron list top-left / tactical-plot-minimap top-right / ship-
      card+weapon-bar bottom) rather than the current ad-hoc stacked-top-left
      layout -- (c) is the biggest and most reference-faithful piece, consider it
      after (a)/(b) give every panel at least a consistent basic style first.
  [ ] Run AGENTS.md §56.3/§1.10.14's 15-step MVP acceptance test yourself (headless
      script simulating the input sequence where possible) as a sanity check, but this
      does NOT substitute for the user's own live pass/fail -- see below.
Next concrete step: *** TOP PRIORITY OVERRIDE (2026-09-27, live user feedback) ***
The user ran the .exe and rejected it: no visible missiles, point-blank laser brawl
instead of a long-range missile duel "like in Weber's books", no formation, no ship
control / course plotting / order panel / mouse selection, wants buttons and an
enlargeable radar. An interactive session the same day implemented (see CHANGELOG
2026-09-27 "живой отзыв пользователя"): scripts/demo_scenario.gd (canon-shaped
4v4 squadron approach from 5.3M km, missile broadsides both sides, PD, formations,
real hulls), scripts/battle_overlay.gd (screen-space tactical symbols + mouse
select/box/RMB course/LMB-enemy order menu over the 3D view), scripts/command_bar.gd
(bottom button bar: time, selection, maneuver, fire, radar), radar enlarge/zoom,
plus sim fixes (swept missile arming, formation feedforward, ZEM guidance opt-in,
perf knobs). NOT yet live-confirmed by the user.
FOLLOW-UP same day (live feedback #2, see CHANGELOG "живой отзыв №2"): ammo 40/tube,
time x1..x2000 + auto-slowdown, floating render origin + free zoom to a single hull +
camera follow, per-ship labels in squadron clusters. Also not live-confirmed.
FOLLOW-UP #3 same day (user "not happy with anything"): ShipCardsPanel + BattleLogPanel
replace HUD text; camera view history (F / F1 / F2 / Esc back, smooth flights);
ship combat attitude (course/broadside/wedge/auto) + laserhead sidewall floor.
Remaining from the plan given to the user: counter-missiles (layered defense), smarter
enemy AI (closing to energy range, target focus), formation choice (wall/column),
nicer ship models/effects, reference-image layout polish.
FOLLOW-UP #4 (user: "boring"; wants story/canon, own canon scenario): mission briefing/
debrief + ship names (MissionPanel, ShipNames, DemoScenario.MISSION_*), formation lines,
salvo labels with ETA, off-screen arrows, default attitude broadside. Ideas queued for
"less boring": multiple missions/campaign, counter-missiles, enemy AI that maneuvers and
retreats, captain/crew voice lines in the log, better models + explosions + sound.
FOLLOW-UP #5: HP bar removed; module damage model (subsystem_damage_model, ShipStatus,
module grid in cards, observed-only enemy status). HullState no longer used by the demo.
FOLLOW-UP #6 (model switched mid-session to claude-sonnet-5; user: "по ТЗ, но
скучно"): found and fixed a REAL regression from feedback #5 -- removing HullState
from the demo silently disabled retreat/leader-succession/crossing-T-disengage AI
(all keyed on world.hulls, which was null). Hull is restored as an internal-only
derived signal (synced from STRUCTURAL_INTEGRITY every tick), never shown to the
player. Confirmed via headless probe: formation leadership now actually transfers
under critical damage. Also added: short bridge/crew voice lines in the battle log
for milestone moments (first launch, first hit, critical damage, leader lost, ship
lost, half-fleet-down), each firing once per battle -- confirmed via probe_voice.gd
(11/11 expected triggers fired in a full battle). New dev tool: simulation/tests/
probe_voice.gd (same "not test_-prefixed, not part of the auto-run suite" convention
as probe_demo_scenario.gd/probe_perf.gd).
Remaining ideas for "still might feel thin": enemy AI that maneuvers/closes distance
dynamically rather than static broadside, counter-missiles, a full campaign/multiple
missions, better ship models + explosion effects + sound.
FOLLOW-UP #7 (user: "редактор миссий сделай, чтобы можно было соотношение и типы
кораблей сторон выбирать"): MissionEditorPanel (pre-battle, own force/enemy force,
per-class -/+ steppers, live summary, randomize/default/"В бой"), ShipClasses (4
demo-scale classes), DemoScenario.build(world, setup) parameterized (default = old
fixed 4x4, every existing headless caller unaffected), main.gd's scenario-build code
extracted into re-entrant _start_mission(setup) + _teardown_mission() +
world.reset_ships()/SimClock.reset() so the editor can rebuild mid-session without
restarting the .exe. Confirmed via new probe_mission_editor.gd (rebuild correctness)
and probe_mixed_battle.gd (a 3-destroyer vs 2-battlecruiser mismatch plays out
sensibly). Also fixed a rebuild-only race in ShipCardsPanel (stale cached id
accessed one frame after a queue_free()'d instance's world was already replaced).
FOLLOW-UP #8 (same day): investigated "why do ships stop firing" -- found and
visualized the existing (not new) hull<=30%-disengage silence (ShipStatus verdict,
battle log event, voice line); added dreadnought/superdreadnought to ShipClasses.
OPEN ITEM flagged by the user, NOT yet addressed: "мало простора, просто выбираешь
приказ и всё" (not enough tactical depth -- picking an order and watching it play
out is the whole interaction). Candidate next steps, roughly in order of expected
impact vs effort: (a) formation SHAPE choice (wall/column/wedge -- currently only
"front line" exists) with different defensive/offensive trade-offs; (b) a
CONCRETE decision the player must make under time pressure more than once per
battle (e.g. missile salvo timing / throttle -- WeaponPanel already has salvo
size + FULL BURN/EXTENDED RANGE throttle, but it may be under-surfaced/underused --
check whether the player actually has a reason to touch it); (c) counter-missiles
(still not implemented -- a real second layer of decisions: hold them for a bigger
threat vs. use them now); (d) smarter enemy AI that maneuvers/focuses fire/retreats
convincingly, so "read and react to the enemy" becomes its own skill. Pick ONE,
budget real time, don't rush a shallow version just to check the box -- this is
exactly the kind of thing that reads as fake depth if done sloppily.
FOLLOW-UP #9 (same day, user: "но я же как адмирал могу приказать атаковать,
несмотря на повреждения!"): world.set_ship_hold_the_line(id, bool) -- explicit
per-ship override of the automatic hull<=30%-disengage silence/retreat added
FOLLOW-UP #8. One shared _is_disengaging(ship_id) helper now gates all 5
firing/retreat/formation-target-assignment call sites; formation-guide
succession deliberately left on the OLD automatic check (separate question).
CommandBar buttons "Драться до конца"/"Разрешить отход", card text reflects it.
Confirmed via probe_hold_the_line.gd (184 checks). Full 50-file sweep green.
"Мало простора" (from FOLLOW-UP #8) is STILL open and unaddressed -- this
pass answered a specific, narrower ask (an override for one already-existing
mechanic), not the broader depth request. Pick one of the FOLLOW-UP #8
candidates next.
FOLLOW-UP #10 (same day, user: "от игрока мало что зависит"): measured it directly
instead of guessing (probe_player_impact.gd) -- concentrating fire on the weakest
DETECTED enemy IS a real, measurable win (kills one more enemy ship per battle,
averaged over several independent RNG seeds -- a single shared-seed A/B run is
NOT valid here, see ASSUMPTIONS.md, ran into that trap once already). Fixed a real
gap found along the way: manual target designation used to skip §34.2 ToT salvo
coordination entirely. Added a one-click "Добить слабейшего" command-bar button
since the winning tactic existed but was tedious to execute by hand (hunting
through cards for the weakest enemy). "Мало простора"/"на автомате" (FOLLOW-UP #8)
is STILL the open, not-yet-addressed root complaint -- this pass answered "does
player skill even matter" (yes, confirmed) and gave one concrete lever, but did
not add NEW ongoing decisions (counter-missiles / smarter enemy AI / formation
shape are all still just candidates, not done). If the user reports this still
feels the same, the next honest move is probably one of: (a) make the effect of
THIS tactic more visible/legible during play (a "critically damaged, kill now"
highlight on the plot/overlay, not just cards); (b) actually implement one of the
bigger candidates (counter-missiles is probably the highest-leverage remaining
one: a real scarce resource, a real decision every salvo, not just at mission
start). Don't add another small button and call it depth -- the user has now said
some version of "not enough" four times.
Next pass: (1) if the user has reported on the new build (check CHANGELOG/commits
newer than this), fix what they report FIRST; (2) otherwise, improve along the same
line, in this order: ships should visibly turn their bow toward their thrust/course
(today velocity orders thrust in any direction without rotating); an event log panel
(launches, intercepts, hits, ship lost) like the reference image; per-ship status
cards for the selection (hull %, ammo left, PD state) in place of the long HUD text;
then item J sub-piece (b)/(c) styling. Keep checking the live .exe look with the Xvfb
capture: SCREENSHOT_PRESIM_S=680 SCREENSHOT_RADAR_BIG=1 xvfb-run ... --rendering-driver
opengl3 res://scenes/dev/screenshot_capture.tscn (see CHANGELOG), and the headless
battle probe simulation/tests/probe_demo_scenario.gd (env PROBE_S, PROBE_M,
PROBE_SHIFT_KM=310000 to start right at missile range).
NOTE for export: session $HOME may lack Godot export templates -- copy
.tools/godot_templates_cache/extracted2/templates/* into
~/.local/share/godot/export_templates/4.3.stable/ before --export-release.
Main scene path is res://scenes/main.tscn (not res://main.tscn).
Tests: still fast-visible-result mode -- skip full simulation suite, headless import/smoke
check only, until §56.3 fully closes (this is a big scope, likely spans many passes --
that's fine, keep chipping at the checklist in order, one or two items per pass is a
reasonable pace, don't rush sloppy code to close items faster).
IMPORTANT -- same lesson as §56.1/§56.2: do NOT self-report any part of this "closed" on
headless verification alone. Report per-pass progress against the lettered checklist
above, and only use the words "§56.3 ЗАКРЫТ"/"MVP acceptance test passed" after the user
has explicitly confirmed it live, walking through (or at least trying) the 15 steps.
Blockers: none currently. This is a large scope -- if it starts feeling too big for one
pass's time budget, that's expected; just make honest incremental progress on the
checklist rather than declaring victory early (that's exactly what went wrong twice now).
Last pass finished: 2026-09-28 ~08:00 UTC (interactive, feedback #10): measured
player-skill impact empirically, fixed a real ToT-coordination gap for manual
targeting, added "Добить слабейшего". Full 50-file sweep + probe_attack_weakest.gd
(3 checks) green, .exe re-exported, pushed. §56.3 NOT closed; nothing
live-confirmed yet. "Мало простора" still open -- see FOLLOW-UP #10 for the
honest next-step options.
FOLLOW-UP #11 (same day, user: "наведи порядок с панелью приказов, упорядочи, сделай
переключателями" + mid-turn "прокрутку у левого меню со статусами кораблей"): pure
UI-polish pass, NOT an answer to "мало простора" (FOLLOW-UP #8/#10 -- that root
complaint is still open, see below). CommandBar reorganized into one labelled row per
group instead of one long inline-labelled flow row; ON/OFF pairs (ПРО, огонь
свободный/стоп, драться до конца/отход) merged into single toggle_mode buttons;
ВРЕМЯ/ПОЛОЖЕНИЕ converted to ButtonGroup-based exclusive toggles with real pressed-state
styling (replacing the old .modulate hack for time scale). ShipCardsPanel wrapped in a
real ScrollContainer (needed now that the mission editor allows up to 8 ships/side).
Found and fixed a real bug along the way: bottom_reserved_px (WeaponPanel/BattleLogPanel's
existing pattern) only updates from world.clock.simulation_tick, which does not fire while
paused -- with the new, much taller CommandBar this made the stale default estimate
visibly overlap the card list during the (paused) mission editor/briefing screens. Fixed
by giving ShipCardsPanel a direct command_bar reference read every _process(), independent
of clock state. Every underlying order-issuing function (_weapons_free/_pd_hold/
_hold_the_line/_attitude/_attack_weakest/etc.) is byte-for-byte unchanged -- only how the
UI invokes them changed. Verified: full 50-file test sweep green, probe_hold_the_line
(184)/probe_attack_weakest(3)/probe_mission_editor(14) green, smoke test exit 0 at the
same 56-error baseline, Xvfb screenshot with a new dev-only SCREENSHOT_BIG_SETUP=1 env var
(8 dreadnoughts/superdreadnoughts a side) confirms the scroll clips correctly and the bar
reads as organized groups with correct active-toggle highlighting. .exe re-exported,
pushed. "Мало простора" (FOLLOW-UP #8/#10) is STILL the open, not-yet-addressed root
complaint -- this pass was purely about legibility/organization of controls that already
existed, not about adding new ongoing decisions. Next honest step is still one of:
counter-missiles as a real scarce resource, formation shape choice, or smarter/more
readable enemy AI behavior -- see FOLLOW-UP #10 for the fuller reasoning. Don't mistake
this UI cleanup pass for progress on that item when reporting to the user next time.
Last pass finished: 2026-09-28 ~08:50 UTC (interactive, feedback #11): CommandBar
reorganized + real toggles, ShipCardsPanel scrolling added, a real bottom_reserved_px
staleness bug fixed along the way. Full 50-file sweep + 3 targeted probes green, .exe
re-exported, pushed. §56.3 NOT closed; nothing live-confirmed yet. "Мало простора" still
open -- see FOLLOW-UP #10/#11 for the honest next-step options.
FOLLOW-UP #12 (same day, user: "Модели кораблей и импеллеров то улучши. А то
совсем черновик"): visual-quality pass on the procedural hull/wedge meshes and
ShipView materials -- NOT the "мало простора" thread either (FOLLOW-UP #8/#10
still open). Hull: superellipse cross-section (squarer/more mechanical than the
old perfect ellipse, cardinal points unchanged so AABB/tests unaffected), baked
vertex-colour shading (dorsal brighter/ventral darker + seam banding) picked up
via vertex_color_use_as_albedo, rim/fresnel highlight, plus small static greebles
(bridge mast, flank blisters) for silhouette breakup. Wedge: baked ridge->edge +
lengthwise brightness gradient instead of a flat single-alpha fill, additive
blending so it reads as a glowing field over space instead of a translucent card.
New: a visible impeller-ring glow at the bow/stern flare position, colour/
brightness driven every frame by that ship's own PROPULSION subsystem condition
(CANON_RULES.md already lists impeller rings as a real damage-model component --
this only makes the existing state visible in the 3D view, not a new mechanic).
Verified: godot --import clean, full 50-file test sweep green (incl. 4 new pure-
function tests: hull cross-section cardinal-point exactness + 3 impeller-glow-
color tests), smoke test exit 0 at a NEW baseline of 128 dummy-renderer errors
(was 56 -- expected, documented in ASSUMPTIONS.md: proportional to the 7->16
MeshInstance3D/ship added this pass, not a new error type). Xvfb close-up
screenshots before/after confirm the hull no longer reads as a smooth blob and
the wedge no longer reads as a flat solid triangle. .exe re-exported, pushed.
Last pass finished: 2026-09-28 ~09:10 UTC (interactive, feedback #12): hull/wedge/
impeller visual-quality pass, new 128-error smoke baseline documented. §56.3 NOT
closed; nothing live-confirmed yet. "Мало простора" still open -- see FOLLOW-UP
#10/#11 for the honest next-step options (this pass was visuals, not depth,
same category note as #11).
FOLLOW-UP #13 (same day, user dropped 3 externally-generated graphics plans into
the repo root: "GRAPHICS.md — план модернизации графики HonorHaringtonGame.md",
"GPAPHICS chatgpt.md" (near-duplicate of the same ChatGPT plan, cosmetic list-
marker differences only), "GRAPHICS geminai.md" (a concrete Godot 4.3 spatial
shader for the impeller wedge: Fresnel edge glow + screen-texture distortion +
hit-flash uniform) -- user: "тубе в корень новых md поканикали. Что скажешь?").
All three now `git add`-ed (not yet committed -- see next concrete step) at the
user's explicit follow-up instruction ("и в гит добавь их"); the OTHER, older
untracked root clutter (CHATGPT.md, "ChatGPT Image ....png", comfyui_nsfw_skill.md,
istochniki_izmeneniy.docx) was NOT part of this and was deliberately left alone
(not part of "их" in context, unrelated content, not mine to add/delete
unprompted).

Read the ChatGPT plan in full: solid, compatible with this project's existing
architecture (keeps Godot not Unreal, keeps simulation/render separation ShipView
already enforces, wants PBR via normal/roughness maps rather than pure geometry
for panel detail, LOD by distance/screen-size, three camera tiers strategic/
tactical/cinematic, explicitly hard-SF not Star-Wars-arcade). Its own first step
is an audit (read all current rendering code -> GRAPHICS_AUDIT.md) before
touching anything. Genuinely large scope (its own 10-phase plan) -- competes with
the still-open "мало простора" depth thread (FOLLOW-UP #8/#10), not a quick pass.

ONE DIRECT CONFLICT surfaced and put to the user: the ChatGPT plan's §12 wants the
impeller wedge "очень тонким, почти незаметным... не энергощит" (thin, barely
visible, NOT a bright energy-shield look) -- the exact OPPOSITE of what
FOLLOW-UP #12 (this same day, a few messages earlier) just shipped (additive
blend, bright ridge->edge glow) in response to the user's own "черновик"
complaint. Asked via AskUserQuestion:
  - Wedge style: user picked "дать оба режима (переключатель)" -- BOTH styles,
    switchable. NOT YET IMPLEMENTED (user then said "сейчас ничего не делай,
    только в файлах фиксируй" -- stop, just record for later).
  - Whether to start the plan's own audit-first step now: user picked "сейчас
    не начинать вовсе" -- explicitly NOT now.

Next concrete step (when the user asks to resume this thread, not before):
1. `git commit` + push the 3 now-staged GRAPHICS*.md files (staged, not yet
   committed as of this note -- do that first, trivially, next time this repo is
   touched, unless the user says otherwise).
2. Implement the wedge bright/subtle toggle: a CommandBar toggle (global
   rendering preference, NOT a per-selection order -- no _need_selection() gate)
   flipping a `ShipView.subtle_wedge_style: bool` static var; ShipView keeps TWO
   materials per wedge (the existing bright StandardMaterial3D + a new
   ShaderMaterial using Fresnel-driven alpha over the SAME baked vertex-colour
   geometry WedgeMeshBuilder already produces -- no geometry change needed, only
   which material is applied each frame). Gemini's shader is a good reference for
   the Fresnel term but its screen-texture distortion (gravitational lensing) is
   extra scope beyond what was actually asked for (just the visibility/brightness
   behavior) -- treat that piece as optional, not required.
3. Only THEN, if/when the user actually asks for it, start the plan's own
   audit-first step (GRAPHICS_AUDIT.md) -- do not preempt that ask.
Last pass finished: 2026-09-28 ~09:20 UTC (interactive, feedback #13): reviewed
3 externally-sourced graphics plans, surfaced the wedge-style conflict honestly,
got explicit direction (both modes, implement later) via AskUserQuestion, staged
the 3 files for git per the user's own follow-up instruction, then stopped work
entirely per "сейчас ничего не делай, только в файлах фиксируй" -- no code
changed this pass, no .exe rebuild needed. §56.3 unaffected. "Мало простора"
still open.
