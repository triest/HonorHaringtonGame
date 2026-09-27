extends CanvasLayer
## BattleLogPanel
##
## 2026-09-27 (user: "not happy with anything"): a readable battle log in
## place of guessing what happened. Reads SimulationWorld.battle_events
## (UI-only feed) and turns them into short Russian lines, aggregating
## bursts so a 16-missile broadside is ONE line, not sixteen:
##   T+09:12  alpha_2: залп 4 ракеты -> beta
##   T+11:40  ПРО beta_3: сбито 3
##   T+11:41  beta: 2 попадания, -800 (корпус 60%)
##   T+12:05  beta_4 УНИЧТОЖЕН
## Plus order acknowledgements pushed by CommandBar (add_local()).
## Own-side lines cyan, enemy-side red, kills/losses highlighted.
class_name BattleLogPanel

const UiTheme = preload("res://scripts/ui_theme.gd")
const MAX_LINES: int = 60
const MERGE_WINDOW_S: float = 3.0

var world: SimulationWorld
var player_team: String = ""
var bottom_reserved_px: float = 0.0

var _panel: PanelContainer
var _text: RichTextLabel
var _last_seq: int = 0
var _lines: Array = []  # {key, t, text_fn args...} -> we store dicts: {key, t, count, dmg, bb}
const OWN_HEX := "#8cf2ff"
const EN_HEX := "#ff6a5a"
const WARN_HEX := "#ffd24a"
const DIM_HEX := "#7fa5aa"

func _ready() -> void:
	layer = 4
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", UiTheme.panel_stylebox())
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel)
	var v := VBoxContainer.new()
	_panel.add_child(v)
	var title := Label.new()
	title.text = "ЖУРНАЛ БОЯ"
	title.add_theme_color_override("font_color", UiTheme.ACCENT_COLOR_DIM)
	title.add_theme_font_size_override("font_size", 12)
	v.add_child(title)
	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.scroll_following = true
	_text.fit_content = false
	_text.custom_minimum_size = Vector2(470, 170)
	_text.add_theme_font_size_override("normal_font_size", 13)
	_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(_text)

func _process(_d: float) -> void:
	if world == null:
		return
	var vs: Vector2 = _panel.get_viewport_rect().size
	# Right column under the radar (the left column is the ship cards).
	_panel.position = Vector2(vs.x - _panel.size.x - 8, 348)
	var changed: bool = false
	for e in world.battle_events:
		if e["seq"] <= _last_seq:
			continue
		_last_seq = e["seq"]
		_ingest(e)
		changed = true
	if changed:
		_render()

func add_local(text: String) -> void:
	var t: float = world.world_sim_time if world != null else 0.0
	_lines.append({"key": "local:%d" % _lines.size(), "t": t, "bb": "[color=%s]ПРИКАЗ: %s[/color]" % [WARN_HEX, text]})
	_trim()
	_render()

func _own(ship_id: String) -> bool:
	return world != null and String(world.teams.get(ship_id, "")) == player_team

func _col(ship_id: String) -> String:
	return OWN_HEX if _own(ship_id) else EN_HEX

func _hull_pct(ship_id: String) -> int:
	var h = world.hulls.get(ship_id)
	if h == null or h.max_integrity <= 0.0:
		return -1
	return int(round(100.0 * h.integrity / h.max_integrity))

## Merge into the last line with the same key if it is recent, else append.
func _merge(key: String, t: float) -> Dictionary:
	for i in range(_lines.size() - 1, maxi(-1, _lines.size() - 8), -1):
		var l: Dictionary = _lines[i]
		if l["key"] == key and t - l["t"] <= MERGE_WINDOW_S:
			return l
	var nl: Dictionary = {"key": key, "t": t, "count": 0, "dmg": 0.0, "bb": ""}
	_lines.append(nl)
	_trim()
	return nl

func _trim() -> void:
	while _lines.size() > MAX_LINES:
		_lines.pop_front()

func _ingest(e: Dictionary) -> void:
	var d: Dictionary = e["data"]
	var t: float = e["t"]
	match e["type"]:
		"missile_launched":
			var a: String = d.get("attacker_ship_id", "")
			var m = world.missiles.get(d.get("missile_id", ""))
			var tgt: String = ""
			if m != null and m.target != null:
				for sid in world.ships.keys():
					if world.ships[sid] == m.target:
						tgt = sid
			var l := _merge("launch:" + a + ":" + tgt, t)
			l["count"] += 1
			l["bb"] = "[color=%s]%s[/color]: залп %d ракет%s → [color=%s]%s[/color]" % [_col(a), ShipNames.of(a), l["count"], _plural(l["count"]), _col(tgt), ShipNames.of(tgt)]
		"pd_intercept":
			var s: String = d.get("ship_id", "")
			var l2 := _merge("pd:" + s, t)
			l2["count"] += 1
			l2["bb"] = "[color=%s]ПРО %s[/color]: сбито ракет %d" % [_col(s), ShipNames.of(s), l2["count"]]
		"missile_detonation":
			var tg: String = d.get("target_ship_id", "")
			var dmg: float = float(d.get("damage_dealt", 0.0))
			var l3 := _merge("det:" + tg, t)
			l3["count"] += 1
			l3["dmg"] += dmg
			for st in (d.get("subsystems", []) if _own(tg) else []):
				if not l3.has("mods"):
					l3["mods"] = {}
				l3["mods"][ShipStatus.long_name(st)] = true
			var hp_txt: String = ""
			if l3.has("mods") and not l3["mods"].is_empty():
				var mk: Array = l3["mods"].keys()
				hp_txt = " — задеты: " + ", ".join(mk.slice(0, 4)) + (" и др." if mk.size() > 4 else "")
			if l3["dmg"] > 0.0:
				l3["bb"] = "[color=%s]%s[/color]: попаданий %d%s" % [_col(tg), ShipNames.of(tg), l3["count"], hp_txt]
			else:
				l3["bb"] = "[color=%s]%s[/color]: %d ракет%s взорвались без урона (клин/бортовая стена)" % [_col(tg), ShipNames.of(tg), l3["count"], _plural(l3["count"])]
		"weapon_hit":
			var tg2: String = d.get("target_ship_id", "")
			var l4 := _merge("beam:" + tg2, t)
			l4["count"] += 1
			l4["dmg"] += float(d.get("damage_dealt", 0.0))
			l4["bb"] = "[color=%s]%s[/color]: лучевых попаданий %d" % [_col(tg2), ShipNames.of(tg2), l4["count"]]
		"subsystem_disabled":
			var ss: String = d.get("ship_id", "")
			if not _own(ss):
				return  # enemy internals are not observable (no cheat vision)
			_lines.append({"key": "sub:%d" % e["seq"], "t": t, "bb": "[color=%s]%s[/color]: [color=%s]выбито — %s[/color]" % [_col(ss), ShipNames.of(ss), WARN_HEX, ShipStatus.long_name(int(d.get("subsystem", 0)))]})
			_trim()
		"ship_destroyed":
			var sd: String = d.get("ship_id", "")
			_lines.append({"key": "dead:" + sd, "t": t, "bb": "[b][color=%s]%s УНИЧТОЖЕН[/color][/b]" % [_col(sd), ShipNames.of(sd)]})
			_trim()
		"formation_leader_lost":
			_lines.append({"key": "lead:%d" % e["seq"], "t": t, "bb": "[color=%s]Флагман %s потерян, командование принял %s[/color]" % [WARN_HEX, ShipNames.of(d.get("old_guide_id", "")), ShipNames.of(d.get("new_guide_id", ""))]})
			_trim()

func _plural(n: int) -> String:
	var n10: int = n % 10
	var n100: int = n % 100
	if n10 == 1 and n100 != 11:
		return "а"
	if n10 >= 2 and n10 <= 4 and (n100 < 12 or n100 > 14):
		return "ы"
	return ""

func _render() -> void:
	var out: String = ""
	for l in _lines:
		var ti: int = int(l["t"])
		out += "[color=%s]T+%02d:%02d:%02d[/color]  %s\n" % [DIM_HEX, ti / 3600, (ti / 60) % 60, ti % 60, l["bb"]]
	_text.text = out
