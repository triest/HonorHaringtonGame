extends CanvasLayer
## MissionPanel
##
## 2026-09-27 (user: "boring, not how I imagined"; wants story/canon, an own
## scenario set in the canon): mission framing around the battle.
##  * Briefing at start (game paused until "К бою"): situation, forces,
##    objectives, and a short how-to.
##  * Debrief when one side is destroyed or out of the fight: result plus
##    statistics gathered from world.battle_events (salvos, missiles, PD
##    kills, hits, losses per side).
## Replaces the old bare "RED WINS" WinLoseScreen text on screen (that node
## stays in the tree, hidden, for its tests).
class_name MissionPanel

const UiTheme = preload("res://scripts/ui_theme.gd")

var world: SimulationWorld
var player_team: String = ""
var briefing_title: String = ""
var briefing_bbcode: String = ""

var _panel: PanelContainer
var _text: RichTextLabel
var _button: Button
var _dim: ColorRect
var _mode: String = ""  # "briefing" / "debrief" / ""
var _done: bool = false
var _stats: Dictionary = {}
var _last_seq: int = 0

func _ready() -> void:
	layer = 20
	_dim = ColorRect.new()
	_dim.color = Color(0, 0, 0, 0.55)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_dim)
	_panel = PanelContainer.new()
	var sb := UiTheme.panel_stylebox()
	sb.set_content_margin_all(18)
	sb.bg_color = Color(0.02, 0.05, 0.07, 0.96)
	_panel.add_theme_stylebox_override("panel", sb)
	add_child(_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	_panel.add_child(v)
	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.fit_content = true
	_text.custom_minimum_size = Vector2(760, 0)
	_text.add_theme_font_size_override("normal_font_size", 15)
	_text.add_theme_font_size_override("bold_font_size", 15)
	v.add_child(_text)
	_button = Button.new()
	_button.focus_mode = Control.FOCUS_NONE
	_button.add_theme_font_size_override("font_size", 18)
	_button.custom_minimum_size = Vector2(220, 40)
	_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var bn := UiTheme.panel_stylebox(UiTheme.ACCENT_COLOR)
	bn.bg_color = Color(0.08, 0.2, 0.25, 0.95)
	_button.add_theme_stylebox_override("normal", bn)
	var bh := UiTheme.panel_stylebox(Color.WHITE)
	bh.bg_color = Color(0.15, 0.35, 0.4, 0.95)
	_button.add_theme_stylebox_override("hover", bh)
	_button.add_theme_color_override("font_color", UiTheme.ACCENT_COLOR)
	_button.pressed.connect(_on_button)
	v.add_child(_button)
	visible = false

func show_briefing() -> void:
	_mode = "briefing"
	_text.text = "[center][b][font_size=24]%s[/font_size][/b][/center]\n\n%s" % [briefing_title, briefing_bbcode]
	_button.text = "К бою"
	if world != null:
		world.clock.paused = true
	visible = true
	_center.call_deferred()

func _center() -> void:
	var vs: Vector2 = _panel.get_viewport_rect().size
	_panel.reset_size()
	_panel.position = (vs - _panel.size) * 0.5

func _on_button() -> void:
	if _mode == "briefing":
		visible = false
		_mode = ""
		if world != null:
			world.clock.paused = false
	elif _mode == "debrief":
		visible = false
		_mode = ""

func _process(_d: float) -> void:
	if world == null:
		return
	for e in world.battle_events:
		if e["seq"] <= _last_seq:
			continue
		_last_seq = e["seq"]
		_count(e)
	if _done or _mode == "briefing":
		return
	var own_alive: int = 0
	var en_alive: int = 0
	var en_armed: int = 0
	var own_armed: int = 0
	for sid in world.ships.keys():
		if world.ships[sid].is_wreck:
			continue
		var own: bool = String(world.teams.get(sid, "")) == player_team
		# Out of the fight (no power / disarmed) counts as knocked out for
		# the mission result -- capability, not hit points (§25.1).
		if world.is_combat_ineffective(sid):
			continue
		var ammo: int = 0
		for t in world.missile_tubes.get(sid, []):
			ammo += t.ammo_count
		if own:
			own_alive += 1
			own_armed += ammo
		else:
			en_alive += 1
			en_armed += ammo
	var result: String = ""
	if en_alive == 0 and own_alive > 0:
		result = "win"
	elif own_alive == 0 and en_alive > 0:
		result = "loss"
	elif own_alive == 0 and en_alive == 0:
		result = "draw"
	elif own_armed == 0 and en_armed == 0 and _no_missiles_in_flight():
		result = "spent"
	if result != "":
		_done = true
		_show_debrief(result, own_alive, en_alive)

func _no_missiles_in_flight() -> bool:
	for mid in world.missiles.keys():
		if world.missiles[mid].is_active():
			return false
	return true

func _side(sid: String) -> String:
	return "own" if String(world.teams.get(sid, "")) == player_team else "en"

func _bump(key: String, n: float = 1.0) -> void:
	_stats[key] = _stats.get(key, 0.0) + n

func _count(e: Dictionary) -> void:
	var d: Dictionary = e["data"]
	match e["type"]:
		"missile_launched":
			_bump(_side(d.get("attacker_ship_id", "")) + "_launched")
		"pd_intercept":
			_bump(_side(d.get("ship_id", "")) + "_pd_kills")
		"missile_detonation":
			var a: String = _side(d.get("attacker_ship_id", ""))
			if float(d.get("damage_dealt", 0.0)) > 0.0:
				_bump(a + "_hits")
				_bump(a + "_damage", float(d.get("damage_dealt", 0.0)))
			else:
				_bump(a + "_blocked")
		"weapon_hit":
			_bump(_side(d.get("attacker_ship_id", "")) + "_beam_hits")
		"ship_destroyed":
			_bump(_side(d.get("ship_id", "")) + "_lost")

func _show_debrief(result: String, own_alive: int, en_alive: int) -> void:
	_mode = "debrief"
	world.clock.paused = true
	var title: String = {"win": "[color=#8cf2ff]ПОБЕДА — противник выведен из боя[/color]", "loss": "[color=#ff6a5a]ПОРАЖЕНИЕ[/color]", "draw": "ВЗАИМНОЕ УНИЧТОЖЕНИЕ", "spent": "БОЕЗАПАС ИСЧЕРПАН — БОЙ ПРЕКРАЩЁН"}[result]
	var t: int = int(world.world_sim_time)
	var s := func(k: String) -> int: return int(_stats.get(k, 0.0))
	var body: String = ""
	body += "Длительность боя: %02d:%02d:%02d\n\n" % [t / 3600, (t / 60) % 60, t % 60]
	body += "[table=3]"
	body += "[cell][b] [/b][/cell][cell][b][color=#8cf2ff]Мантикора[/color]   [/b][/cell][cell][b][color=#ff6a5a]Хевен[/color][/b][/cell]"
	body += "[cell]Ракет выпущено   [/cell][cell]%d[/cell][cell]%d[/cell]" % [s.call("own_launched"), s.call("en_launched")]
	body += "[cell]Сбито ПРО (своей)   [/cell][cell]%d[/cell][cell]%d[/cell]" % [s.call("own_pd_kills"), s.call("en_pd_kills")]
	body += "[cell]Попаданий ракет   [/cell][cell]%d[/cell][cell]%d[/cell]" % [s.call("own_hits"), s.call("en_hits")]
	body += "[cell]Остановлено клином/стеной   [/cell][cell]%d[/cell][cell]%d[/cell]" % [s.call("own_blocked"), s.call("en_blocked")]
	body += "[cell]Лучевых попаданий   [/cell][cell]%d[/cell][cell]%d[/cell]" % [s.call("own_beam_hits"), s.call("en_beam_hits")]
	body += "[cell]Потеряно кораблей   [/cell][cell]%d[/cell][cell]%d[/cell]" % [s.call("own_lost"), s.call("en_lost")]
	body += "[/table]\n\nБоеспособных: у нас %d, у противника %d." % [own_alive, en_alive]
	_text.text = "[center][b][font_size=26]%s[/font_size][/b][/center]\n\n%s" % [title, body]
	_button.text = "Осмотреть поле боя"
	visible = true
	_center.call_deferred()
