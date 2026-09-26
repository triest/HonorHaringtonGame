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
  [ ] E. Weapon-type selection panel for the selected ship: missiles (type + salvo size +
      target + FIRE), counter-missiles (auto/manual/hold), energy weapons, PD
      (auto/hold/priority-target) -- must only show weapons the selected ship's class
      actually has mounted (no showing weapons it doesn't carry). AGENTS.md §1.10.8,
      ~line 2434.
  [ ] F. Command camera per §1.10.1: free camera over the battle, can go near-vertical
      top-down, orbit, zoom, quick-center on selected ship/group/contact -- extend the
      existing OrbitCamera rather than replacing it if it already covers most of this.
      NOTE: this is also the point to do a real shared UI-panel layout pass (Hud +
      TacticalPlot + CommandGroupPanel currently use ad-hoc fixed positions that will
      start colliding as more panels are added -- see ASSUMPTIONS.md "§56.3 item B").
  [ ] G. Zoom-level behavior (§1.10.3): at minimum ensure zooming out doesn't lose distant
      contacts (they must stay visible on the plot even far out) and zooming in reveals
      per-ship detail -- doesn't need all 4 named levels to be literally distinct modes,
      but the plot must not become unreadable at either extreme.
  [ ] H. Hardcoded demo scenario upgraded from 1v1 to at least a couple of ships per side
      (small squadron vs small squadron) so multi-select/group-order behavior in A-D is
      actually exercisable live, and so missile salvos (E) have something meaningful to
      fire at -- give at least one side missile tubes (currently energy-only per §56.1
      CHANGELOG entries), this was explicitly asked about by the user separately.
  [ ] I. Individual override: within a selected group, pick one ship and give it its own
      order while the rest keep the group order (§1.10.12 worked example).
  [ ] Run AGENTS.md §56.3/§1.10.14's 15-step MVP acceptance test yourself (headless
      script simulating the input sequence where possible) as a sanity check, but this
      does NOT substitute for the user's own live pass/fail -- see below.
Next concrete step: item E -- weapon-type selection panel for the selected ship
(§1.10.8, AGENTS.md ~line 2434 -- read it fresh, it was only skimmed against item D's
own needs so far). Minimal interface per class: MISSILES (type, salvo size, target,
throttle/profile if available, FIRE), COUNTER-MISSILES (AUTO/MANUAL DESIGNATION/HOLD),
ENERGY WEAPONS (laser/graser/other mounted), POINT DEFENSE (AUTO/HOLD/priority-threat
assignment). Hard requirement: "Нельзя показывать игроку оружие, которого у корабля
нет" -- the panel must only list weapons the SELECTED ship's class actually has mounted
(world.weapon_mounts[ship_id]/world.missile_tubes[ship_id], not a hardcoded list).
Existing primitives to check/reuse before inventing anything: ShipCombatDirective
(manual_target_ship_id/weapons_free -- already wired via transmit_ship_target/
transmit_ship_weapons_free, see player_input.gd/order_menu_controller.gd for existing
usage) covers "target"/"weapon mode" but has NO notion of missile salvo size, missile
throttle/profile, or counter-missile/point-defense POLICY (auto/manual/hold) yet --
grep simulation/*.gd (missile_tube.gd, point_defense_mount.gd, counter_missile_resolution.gd,
point_defense_resolution.gd, tactical_ai.gd's select_pd_target) before assuming what
does/doesn't already exist, same "check first, log the honest gap" discipline as item D.
A one-shot "FIRE missiles now" action is a genuinely different kind of thing from a
standing directive (matches order_missile_launch's own existing "immediate explicit
trigger" convention per ship_combat_directive.gd's class doc) -- don't force it into
ShipCombatDirective's posture model. Like item D, this is a UI/routing item: implement
what maps cleanly onto what exists, log clearly whatever doesn't (e.g. per-missile-type
selection, throttle/profile, counter-missile/PD policy toggles may need small new,
additive state -- that is fine and expected, just keep it small and honestly logged,
NOT a request to redesign weapon_mount.gd/missile_tube.gd's own resolution logic).
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
Last pass finished: 2026-09-26 14:28 UTC (scheduled dev pass, fired from the normal 3h
cron; cron prompt still says "§56.1" -- that is a stale/generic scheduled-task prompt
that this skill's own instructions say NOT to update via update_trigger, so it is
intentionally ignored in favor of this file, which is the actual source of truth):
implemented and headless-verified §56.3 item D (contextual order menu) -- new
scripts/order_menu_controller.gd (OrderMenuController) + scripts/order_menu.gd
(OrderMenu), new SelectionState.designated_target_id concept, tactical_plot.gd's plain-
click branch now tries the menu before falling back to select_only, plus a new
designated-target diamond marker in TacticalPlot._draw(); main.gd wiring (order_menu
added to the tree AFTER tactical_plot for input priority, order_menu.sync() called from
_on_tick). ATTACK/FOCUS FIRE/HOLD FIRE/WEAPONS FREE/APPROACH/WITHDRAW/MAINTAIN FORMATION
implemented; DEFEND/COVER/FOLLOW/INTERCEPT honestly NOT offered in the menu (no backing
mechanic exists -- see ASSUMPTIONS.md "§56.3 item D"). New test file
simulation/tests/test_order_menu_controller.gd (42 checks, all passing), plus 9 existing
regression suites re-run clean (test_selection_state.gd, test_move_order_controller.gd,
test_command_group_controller.gd, test_tactical_plot_selection.gd,
test_tactical_plot_projector.gd, test_individual_orders.gd, test_command_transmission.gd,
test_formation.gd, test_ship_combat_directive.gd) plus a headless scene smoke run
(exit 0, same 16x baseline dummy-renderer errors, zero new error types). One
non-obvious trap found and worked around while writing this pass's OWN test (not a bug
in the shipped code, a test-authoring pitfall -- see ASSUMPTIONS.md "§56.3 item D"):
WITHDRAW's turn-then-accelerate composite silently no-ops if the ship starts at zero
speed (inherited from change_course's existing is_complete() semantics, same as every
other withdraw_orders caller in this codebase already requires). ASSUMPTIONS.md/
CHANGELOG.md updated; pushed this pass. E-I not started.
