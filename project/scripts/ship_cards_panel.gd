extends CanvasLayer
## ShipCardsPanel
##
## 2026-09-27 (user: "not happy with anything" -- the left side was two
## long debug text dumps). One compact card per own ship, like the
## squadron list in docs/reference/tactical_command_ui_reference.png:
##   name (+ ФЛАГМАН), hull bar, speed, missiles left / tubes ready,
##   weapons & PD mode, and ONLY the damaged subsystems (coloured) --
##   intact ones are noise. Click a card = select that ship, Ctrl/Shift
##   = add, double-click = camera to it. Below: a short enemy roster.
## Pure readout of SimulationWorld + SelectionState (§42); selection goes
## through the one shared SelectionState.
##
## 2026-09-28 (user: "прокрутку у левого меню со статусами кораблей"):
## the mission editor now allows up to 8 ships a side (incl. bigger
## dreadnought/superdreadnought module grids), so the card list can be
## taller than the screen. Wrapped in a real ScrollContainer, sized every
## tick to the space actually available between the top of the screen and
## CommandBar's bottom bar (bottom_reserved_px, set by main.gd exactly
## like WeaponPanel/BattleLogPanel already do) -- it scrolls instead of
## running under the command bar or off the bottom of the screen.
class_name ShipCardsPanel

const UiTheme = preload("res://scripts/ui_theme.gd")
const SubsystemType = preload("res://simulation/subsystem_type.gd")
const ContactState = preload("res://simulation/contact_state.gd")

const SUBSYS_RU: Dictionary = {
	"PROPULSION": "двиг.", "MANEUVERING": "маневр", "SENSORS": "сенсоры",
	"COMMUNICATIONS": "связь", "WEAPONS": "орудия", "MISSILE_SYSTEMS": "ракетн.",
	"COUNTER_MISSILE_SYSTEMS": "противорак.", "POINT_DEFENSE": "ПРО",
	"POWER": "энергия", "STRUCTURAL_INTEGRITY": "набор", "DEFENSIVE_SYSTEMS": "защита",
}

var world: SimulationWorld
var selection: SelectionState
var player_team: String = ""
var camera_focus_controller: CameraFocusController
## Set by main.gd. Read directly every frame (see _process) rather than
## only mirrored via bottom_reserved_px below -- CommandBar.get_height()
## is driven by world.clock.simulation_tick (main.gd's _on_tick), which
## does NOT fire while the clock is paused (SimClock.advance() returns
## early). The mission editor / briefing screens start paused, and this
## reorganized (much taller) bar made that stale-default gap visible as
## real overlap between the card list and the bar. Reading command_bar's
## height straight from the node itself instead makes the scroll area
## correct on its own, independent of whether the simulation is ticking.
var command_bar: CommandBar
## Fallback only, used the few frames before command_bar is assigned or
## while it's null (e.g. a headless caller that never sets one).
var bottom_reserved_px: float = 160.0

var _scroll: ScrollContainer
var _root: VBoxContainer
var _cards: Dictionary = {}  # ship_id -> {panel, name, bar, info, dmg}
var _enemy_label: RichTextLabel
var _built: bool = false

const TOP_MARGIN_PX: float = 8.0
const CARD_LIST_WIDTH_PX: float = 300.0
const MIN_SCROLL_HEIGHT_PX: float = 120.0

func _ready() -> void:
	layer = 4
	_scroll = ScrollContainer.new()
	_scroll.position = Vector2(TOP_MARGIN_PX, TOP_MARGIN_PX)
	_scroll.size = Vector2(CARD_LIST_WIDTH_PX + 16.0, MIN_SCROLL_HEIGHT_PX)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	add_child(_scroll)
	_root = VBoxContainer.new()
	_root.add_theme_constant_override("separation", 4)
	_root.custom_minimum_size = Vector2(CARD_LIST_WIDTH_PX, 0)
	_scroll.add_child(_root)

func _build() -> void:
	_built = true
	var title := Label.new()
	title.text = "ЭСКАДРА"
	title.add_theme_color_override("font_color", UiTheme.ACCENT_COLOR)
	title.add_theme_font_size_override("font_size", 14)
	_root.add_child(title)
	for sid in world.ships.keys():
		if String(world.teams.get(sid, "")) != player_team:
			continue
		_cards[sid] = _make_card(sid)
	var et := Label.new()
	et.text = "ПРОТИВНИК"
	et.add_theme_color_override("font_color", Color(1.0, 0.45, 0.4))
	et.add_theme_font_size_override("font_size", 14)
	_root.add_child(et)
	var ep := PanelContainer.new()
	ep.add_theme_stylebox_override("panel", UiTheme.panel_stylebox(Color(1.0, 0.4, 0.35, 0.6)))
	_root.add_child(ep)
	_enemy_label = RichTextLabel.new()
	_enemy_label.bbcode_enabled = true
	_enemy_label.fit_content = true
	_enemy_label.custom_minimum_size = Vector2(290, 0)
	_enemy_label.add_theme_font_size_override("normal_font_size", 13)
	_enemy_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ep.add_child(_enemy_label)

func _make_card(sid: String) -> Dictionary:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiTheme.panel_stylebox(UiTheme.ACCENT_COLOR_DIM))
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.gui_input.connect(func(ev): _card_input(sid, ev))
	_root.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 1)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(v)
	var name := RichTextLabel.new()
	name.bbcode_enabled = true
	name.fit_content = true
	name.custom_minimum_size = Vector2(290, 0)
	name.add_theme_font_size_override("normal_font_size", 14)
	name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(name)
	# Module grid (AGENTS.md §25.1: no health bar -- each module's own
	# condition, colour-coded, grey = knocked out).
	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 2)
	grid.add_theme_constant_override("v_separation", 2)
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(grid)
	var cells: Dictionary = {}
	for m in ShipStatus.MODULES:
		var cell := Label.new()
		cell.text = m[1]
		cell.tooltip_text = m[2]
		cell.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cell.custom_minimum_size = Vector2(46, 0)
		cell.add_theme_font_size_override("font_size", 10)
		cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
		grid.add_child(cell)
		cells[m[0]] = cell
	var info := RichTextLabel.new()
	info.bbcode_enabled = true
	info.fit_content = true
	info.custom_minimum_size = Vector2(290, 0)
	info.add_theme_font_size_override("normal_font_size", 12)
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(info)
	return {"panel": panel, "name": name, "cells": cells, "info": info}

func _card_input(sid: String, ev: InputEvent) -> void:
	if not (ev is InputEventMouseButton) or not ev.pressed or ev.button_index != MOUSE_BUTTON_LEFT:
		return
	if world.ships[sid].is_wreck:
		return
	if ev.double_click and camera_focus_controller != null:
		selection.select_only([sid])
		camera_focus_controller.view_ids([sid], true)
		return
	if ev.ctrl_pressed:
		selection.toggle(sid)
	elif ev.shift_pressed:
		selection.add_only([sid])
	else:
		selection.select_only([sid])

func _is_guide(sid: String) -> bool:
	for fid in world.formations.keys():
		if world.formations[fid].guide_ship_id == sid:
			return true
	return false

func _hex(c: Color) -> String:
	return "#" + c.to_html(false)

func _process(_d: float) -> void:
	if world == null:
		return
	if not _built:
		_build()
	# Bound the scroll area to whatever room is actually free between the
	# top of the screen and CommandBar's bar (bottom_reserved_px) -- the
	# card list scrolls inside that instead of overflowing under the bar.
	var reserved: float = command_bar.get_height() if command_bar != null else bottom_reserved_px
	var avail_h: float = get_viewport().get_visible_rect().size.y - TOP_MARGIN_PX * 2.0 - reserved
	_scroll.size = Vector2(CARD_LIST_WIDTH_PX + 16.0, maxf(MIN_SCROLL_HEIGHT_PX, avail_h))
	for sid in _cards.keys():
		if not world.ships.has(sid):
			# 2026-09-28: guards a real one-frame race during a mission
			# editor rebuild -- this (old) ShipCardsPanel instance's
			# queue_free() from _teardown_mission() hasn't taken effect
			# yet when _start_mission() immediately repopulates `world`
			# with a NEW roster in the same frame, so `_cards` (built once
			# in _build(), keyed by the OLD roster's ids) can briefly hold
			# an id `world.ships` no longer has. Skipping it here is
			# harmless -- the freshly-created ShipCardsPanel instance
			# takes over with a correct, freshly-built `_cards` dict the
			# very next frame.
			continue
		var c: Dictionary = _cards[sid]
		var ship: ShipPhysicsState = world.ships[sid]
		var sel: bool = selection != null and selection.is_selected(sid)
		var border: Color = Color.WHITE if sel else (Color(0.5, 0.5, 0.5, 0.5) if ship.is_wreck else UiTheme.ACCENT_COLOR_DIM)
		var sb := UiTheme.panel_stylebox(border)
		sb.set_content_margin_all(5)
		if sel:
			sb.bg_color = Color(0.06, 0.16, 0.2, 0.9)
		c["panel"].add_theme_stylebox_override("panel", sb)
		var head: String = "[b]%s[/b]" % ShipNames.of(sid)
		if _is_guide(sid) and not ship.is_wreck:
			head += "  [color=#ffd24a]★ ФЛАГМАН[/color]"
		if ship.is_wreck:
			head = "[color=#888888][s]%s[/s]  УНИЧТОЖЕН[/color]" % ShipNames.of(sid)
		else:
			var vd: Dictionary = ShipStatus.verdict(world, sid)
			head += "   %d км/с\n[color=%s]%s[/color]" % [int(ship.velocity.length() / 1000.0), _hex(vd["color"]), vd["text"]]
		c["name"].text = "[color=%s]%s[/color]" % [_hex(UiTheme.ACCENT_COLOR), head] if not ship.is_wreck else head
		for m in ShipStatus.MODULES:
			var cond: float = ship.subsystems.get_condition(ShipStatus.type_of(m[0])) if ship.subsystems != null else 1.0
			if ship.is_wreck:
				cond = 0.0
			var cell: Label = c["cells"][m[0]]
			var csb := StyleBoxFlat.new()
			var mc: Color = ShipStatus.module_color(cond)
			csb.bg_color = Color(mc, 0.28 if cond > 0.0 else 0.15)
			csb.border_color = mc
			csb.set_border_width_all(1)
			csb.set_corner_radius_all(2)
			cell.add_theme_stylebox_override("normal", csb)
			cell.add_theme_color_override("font_color", mc if cond > 0.0 else Color(0.6, 0.6, 0.6))
			cell.tooltip_text = "%s: %s" % [m[2], ("%d%%" % int(round(cond * 100.0))) if cond > 0.0 else "выбито"]
		if ship.is_wreck:
			c["info"].text = ""
			continue
		var ammo: int = 0
		var ready: int = 0
		var tubes: Array = world.missile_tubes.get(sid, [])
		for t in tubes:
			ammo += t.ammo_count
			if t.is_ready():
				ready += 1
		var directive = world.ship_combat_directives.get(sid)
		var free: bool = directive == null or directive.weapons_free
		var pd_hold: bool = world.ship_pd_hold.get(sid, false)
		var line: String = "[color=#9fd]ракет %d · трубы %d/%d · огонь %s · ПРО %s[/color]" % [ammo, ready, tubes.size(), "своб." if free else "[color=#ffd24a]СТОП[/color]", "[color=#ffd24a]СТОП[/color]" if pd_hold else "авто"]
		# 2026-09-29: counter-missile stock ("n/N") + policy, only for ships
		# that actually carry counter-missile tubes.
		if world.cm_tubes.has(sid) and not world.cm_tubes[sid].is_empty():
			var cm_left: int = world.cm_ammo_remaining(sid)
			var cm_all: int = int(world.cm_start_ammo.get(sid, 0))
			var cm_pol: String = world.cm_policy_of(sid)
			var cm_pol_ru: Dictionary = {"auto": "авто", "flagship": "только флагман", "salvo": "только залпы", "hold": "СТОП"}
			var cm_col: String = "#9fd" if cm_left > 0 else "#ff6a5a"
			line += "\n[color=%s]ПРТР %d/%d · %s[/color]" % [cm_col, cm_left, cm_all, cm_pol_ru.get(cm_pol, cm_pol)]
		var att: String = String(world.ship_attitude.get(sid, ""))
		var eff: String = String(world.ship_effective_attitude.get(sid, att))
		var att_ru: Dictionary = {"auto": "авто", "broadside": "бортом", "wedge": "[color=#ffd24a]КЛИНОМ[/color]", "course": "по курсу"}
		if att != "":
			line += "\n[color=#9fd]положение: %s%s[/color]" % [att_ru.get(eff, eff), (" (авто)" if att == "auto" else "")]
		var tgt: String = world.get_weapon_target_designation(sid)
		if tgt != "":
			line += "\n[color=#9fd]цель: [color=#ff6a5a]%s[/color][/color]" % ShipNames.of(tgt)
		# 2026-09-28: shown whenever the order is active, not only once the
		# ship is actually critical -- so the player remembers which ships
		# they've already told to ignore an eventual disengage.
		if world.ship_hold_the_line.get(sid, false):
			line += "\n[color=#ff6a5a]приказ: драться до конца[/color]"
		c["info"].text = line
	# Enemy roster (from own sensor picture: shown only once detected).
	var pov: String = ""
	for sid in _cards.keys():
		if not world.ships[sid].is_wreck:
			pov = sid
			break
	var contacts: Dictionary = world.sensor_contacts.get(pov, {}) if pov != "" else {}
	var el: Array = []
	for sid in world.ships.keys():
		if String(world.teams.get(sid, "")) == player_team:
			continue
		if not contacts.has(sid) or contacts[sid].state == ContactState.Type.UNKNOWN:
			el.append("[color=#777]%s — не обнаружен[/color]" % ShipNames.of(sid))
			continue
		var mark: String = "◎ " if selection != null and selection.designated_target_id == sid else ""
		if world.ships[sid].is_wreck:
			el.append("[color=#888][s]%s[/s] уничтожен[/color]" % ShipNames.of(sid))
		else:
			var ev: Dictionary = ShipStatus.verdict_observed(world, sid)
			el.append("[color=#ff6a5a]%s%s[/color]  [color=%s]%s[/color]" % [mark, ShipNames.of(sid), _hex(ev["color"]), ev["text"]])
	_enemy_label.text = "\n".join(el)
