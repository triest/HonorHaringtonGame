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

var _root: VBoxContainer
var _cards: Dictionary = {}  # ship_id -> {panel, name, bar, info, dmg}
var _enemy_label: RichTextLabel
var _built: bool = false

func _ready() -> void:
	layer = 4
	var scroll := PanelContainer.new()
	scroll.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	scroll.position = Vector2(8, 8)
	add_child(scroll)
	_root = VBoxContainer.new()
	_root.add_theme_constant_override("separation", 4)
	_root.custom_minimum_size = Vector2(300, 0)
	scroll.add_child(_root)

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
	for sid in _cards.keys():
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
		var att: String = String(world.ship_attitude.get(sid, ""))
		var eff: String = String(world.ship_effective_attitude.get(sid, att))
		var att_ru: Dictionary = {"auto": "авто", "broadside": "бортом", "wedge": "[color=#ffd24a]КЛИНОМ[/color]", "course": "по курсу"}
		if att != "":
			line += "\n[color=#9fd]положение: %s%s[/color]" % [att_ru.get(eff, eff), (" (авто)" if att == "auto" else "")]
		var tgt: String = world.get_weapon_target_designation(sid)
		if tgt != "":
			line += "\n[color=#9fd]цель: [color=#ff6a5a]%s[/color][/color]" % ShipNames.of(tgt)
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
