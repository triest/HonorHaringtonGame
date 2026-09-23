# Honorverse dev state (updated every pass)
Phase: §56.3 full tactical command UI (REPLACES §56.2 as top priority; §56.2's finished pieces are the foundation, not discarded)
Context: user rejected §56.2's result as too minimal/single-ship and supplied a detailed
UI spec (AGENTS.md §56.3, verbatim from project's CHATGPT.md) plus a reference image at
docs/reference/tactical_command_ui_reference.png (VIEW THIS IMAGE FIRST -- it is the visual
target: fleet-view squadron list + tactical-plot minimap on top, closer 3D view with
weapon/order panels on bottom). Read AGENTS.md §56.3 and CLOUD.md §1.10 in full before
starting -- they are long and detailed, do not skim.
What already exists from §56.2 (do NOT rebuild, extend it):
  - Tactical plot base with IFF-colored contact icons + velocity vectors (scripts, see
    prior CHANGELOG entries for exact file names)
  - Missile tracks shown distinctly from ship contacts
  - Mouse click-to-select on the plot
  - A canon-scale distance-compression convention (logged in ASSUMPTIONS.md)
  - Subsystem-condition text HUD (from §56.1) as a secondary panel
Checklist (§56.3, new scope, roughly in an order that builds incrementally toward the
15-step MVP acceptance test in AGENTS.md §56.3 / §1.10.14):
  [x] A. Multi-select: Ctrl+LMB add to selection, Shift+LMB extend, LMB drag-box select
      multiple contacts. DONE this pass: scripts/selection_state.gd (SelectionState --
      shared select_only/toggle/add_only/clear), scripts/tactical_plot_selection.gd (pure
      hit_test/box_test geometry, unit-tested headlessly), scripts/tactical_plot.gd's
      mouse_filter flipped IGNORE->STOP with real _gui_input() click/drag handling,
      main.gd owns the one shared SelectionState instance and injects it into
      tactical_plot (reuse this same instance for B/D below, do not create a second
      one). NOTE: there was in fact no real single-select implemented from §56.2 despite
      state.md's prior "already exists" note -- TacticalPlot's mouse_filter was still
      IGNORE and player_input.gd is hotkey-only; this pass built click-select AND
      multi-select together as one unit, see CHANGELOG.md for exact detail. Headless-
      tested only (synthetic icons in unit tests) -- NOT yet confirmed with a real mouse
      by the user; scenario is still 1v1 so there is only one own ship to multi-select
      with today (item H upgrades that).
  [ ] B. Selection becomes a named command group (visual list, e.g. left-side panel like
      the reference image's squadron list) -- reuse CommandEchelon/FormationState, do not
      invent a parallel selection-group model.
  [ ] C. RMB-on-space move order for the current selection (single ship or group), with a
      visual course line/vector/predicted-turn-point per §1.10.6 -- routes into existing
      IndividualOrder/FormationOrder, ship still obeys real acceleration/inertia (no
      teleport).
  [ ] D. Contextual order menu after selecting own + designating enemy: at minimum ATTACK,
      FOCUS FIRE, HOLD FIRE, WEAPONS FREE, DEFEND, MAINTAIN FORMATION (full list in
      §1.10.7) -- routes into ShipCombatDirective/FormationOrder, no UI-only order model.
  [ ] E. Weapon-type selection panel for the selected ship: missiles (type + salvo size +
      target + FIRE), counter-missiles (auto/manual/hold), energy weapons, PD
      (auto/hold/priority-target) -- must only show weapons the selected ship's class
      actually has mounted (no showing weapons it doesn't carry).
  [ ] F. Command camera per §1.10.1: free camera over the battle, can go near-vertical
      top-down, orbit, zoom, quick-center on selected ship/group/contact -- extend the
      existing OrbitCamera rather than replacing it if it already covers most of this.
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
Next concrete step: item B -- selection becomes a named command group (visual list,
e.g. left-side squadron-list panel per the reference image), reusing
CommandEchelon/FormationState (simulation/command_echelon.gd, simulation/
formation_state.gd -- read both before starting, do not invent a parallel grouping
model). Read main.gd's `selection` (SelectionState, from item A) rather than adding a
second selection mechanism.
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
Last pass finished: 2026-09-23 22:11 UTC (scheduled dev pass, manually fired outside
the normal 3h cron with the §56.3 adoption context as payload): implemented and
headless-verified §56.3 item A (multi-select) -- selection_state.gd,
tactical_plot_selection.gd, tactical_plot.gd input wiring, main.gd wiring, 2 new test
files (17 checks total, all passing), ASSUMPTIONS.md item-A interaction-model entry,
CHANGELOG.md updated; pushed this pass. B-I not started.
