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
	var bar := ProgressBar.new()
	bar.min_value = 0
	bar.max_value = 100
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(290, 7)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.1, 0.15, 0.17, 0.9)
	bar.add_theme_stylebox_override("background", bg)
	var fill := StyleBoxFlat.new()
	fill.bg_color = UiTheme.CONDITION_GOOD_COLOR
	bar.add_theme_stylebox_override("fill", fill)
	v.add_child(bar)
	var info := RichTextLabel.new()
	info.bbcode_enabled = true
	info.fit_content = true
	info.custom_minimum_size = Vector2(290, 0)
	info.add_theme_font_size_override("normal_font_size", 12)
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(info)
	return {"panel": panel, "name": name, "bar": bar, "fill": fill, "info": info}

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
		var hull = world.hulls.get(sid)
		var frac: float = 1.0
		if hull != null and hull.max_integrity > 0.0:
			frac = hull.integrity / hull.max_integrity
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
			head += "   [color=%s]%d%%[/color]   %d км/с" % [_hex(UiTheme.condition_color(frac)), int(round(frac * 100.0)), int(ship.velocity.length() / 1000.0)]
		c["name"].text = "[color=%s]%s[/color]" % [_hex(UiTheme.ACCENT_COLOR), head] if not ship.is_wreck else head
		c["bar"].value = frac * 100.0
		c["fill"].bg_color = UiTheme.condition_color(frac)
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
		var dmg: Array = []
		if ship.subsystems != null:
			for tv in SubsystemType.Type.values():
				var cond: float = ship.subsystems.get_condition(tv)
				if cond < 0.995:
					var nm: String = SubsystemType.Type.keys()[tv]
					dmg.append("[color=%s]%s %d%%[/color]" % [_hex(UiTheme.condition_color(cond)), SUBSYS_RU.get(nm, nm), int(round(cond * 100.0))])
		if not dmg.is_empty():
			line += "\n" + " · ".join(dmg)
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
		var h = world.hulls.get(sid)
		var f: float = 1.0 if h == null or h.max_integrity <= 0.0 else h.integrity / h.max_integrity
		var mark: String = "◎ " if selection != null and selection.designated_target_id == sid else ""
		if world.ships[sid].is_wreck:
			el.append("[color=#888][s]%s[/s] уничтожен[/color]" % ShipNames.of(sid))
		else:
			el.append("[color=#ff6a5a]%s%s[/color]  [color=%s]%d%%[/color]" % [mark, ShipNames.of(sid), _hex(UiTheme.condition_color(f)), int(round(f * 100.0))])
	_enemy_label.text = "\n".join(el)
