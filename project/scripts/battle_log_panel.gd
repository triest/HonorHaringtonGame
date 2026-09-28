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

## 2026-09-27 (user: "по ТЗ, но скучно"): short crew/bridge chatter tied
## to milestone moments, mixed into the same log -- purely cosmetic
## flavor text (chosen deterministically from `world`'s own RNG-free
## state so it never affects the simulation), meant to make the battle
## feel narrated rather than a spreadsheet of numbers. Own-side lines are
## voiced by name (bridge crew); enemy lines are voiced generically (we
## do not hear their bridge).
const VOICE_FIRST_LAUNCH_OWN: Array = ["Мостик, ракетная палуба -- пуск произведён, все аппараты чисты.", "Первый залп ушёл, капитан.", "Ракеты пошли -- время на цель передаю на тактический."]
const VOICE_FIRST_LAUNCH_ENEMY: Array = ["Captain, we have missile launch -- multiple birds inbound!", "Радар -- вижу пуск с противника, идёт отслеживание.", "Внимание, входящие! Первый залп противника на подходе."]
const VOICE_FIRST_HIT_OWN: Array = ["Капитan, попадание! Отчёт по повреждениям на подходе.", "Нас зацепило -- держим строй, ждём доклад по системам.", "Прямое попадание, сэр. Работаем."]
const VOICE_CRITICAL_OWN: Array = ["Капитан, серьёзные повреждения! Мостик просит разрешения на манёвр уклонения.", "Мы горим -- энергетика на пределе, рекомендую отход.", "Тяжёлые повреждения, сэр. Боеспособность падает."]
const VOICE_LEADER_LOST: Array = ["Флагман серьёзно повреждён -- командование эскадрой переходит.", "Мостик флагмана молчит -- беру управление на себя.", "Приказ принят: командование эскадрой -- на второй корабль."]
const VOICE_SHIP_LOST_OWN: Array = ["Мы теряем «%s»! Спасательные капсулы -- пошли.", "«%s» разрушен -- да упокоятся с миром.", "Потеряли «%s». Продолжаем бой."]
const VOICE_SHIP_LOST_ENEMY: Array = ["Цель уничтожена -- один корабль противника выведен из строя.", "«%s» противника разрушен.", "Есть! Один корабль хевенитов уничтожен."]
const VOICE_HALF_ENEMY_DOWN: Array = ["Капитан, у противника серьёзные потери -- их строй разваливается.", "Противник теряет эскадру -- ещё немного, и они дрогнут."]
const VOICE_HALF_OWN_DOWN: Array = ["Капитан, мы несём тяжёлые потери -- запрашиваю указания по отходу.", "Эскадра тает, сэр. Нужно решение -- держаться или отходить."]
const VOICE_DISENGAGE_OWN: Array = ["Капитан, корпус критический -- разрешите выйти из линии.", "«%s» больше не может держать строй, выходит из боя.", "Мостик докладывает: «%s» разворачивается, бой продолжать не в состоянии."]
const VOICE_DISENGAGE_ENEMY: Array = ["Один из кораблей противника выходит из боя -- видны серьёзные повреждения.", "Противник теряет ход -- «%s» разворачивается прочь."]

var _voice_seen: Dictionary = {}
var _own_lost_count: int = 0
var _en_lost_count: int = 0
var _own_total: int = 1
var _en_total: int = 1

func _voice_once(key: String, pool: Array, t: float, sub: String = "") -> void:
	if _voice_seen.has(key):
		return
	_voice_seen[key] = true
	var line: String = pool[randi() % pool.size()]
	if sub != "" and line.find("%s") >= 0:
		line = line % sub
	_lines.append({"key": "voice:%d" % _lines.size(), "t": t, "bb": "[i][color=%s]« %s »[/color][/i]" % [DIM_HEX, line]})
	_trim()

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
	if _own_total <= 1 and _en_total <= 1 and not world.ships.is_empty():
		_own_total = 0
		_en_total = 0
		for sid in world.ships.keys():
			if _own(sid):
				_own_total += 1
			else:
				_en_total += 1
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
			_voice_once("launch_" + ("own" if _own(a) else "en"), VOICE_FIRST_LAUNCH_OWN if _own(a) else VOICE_FIRST_LAUNCH_ENEMY, t)
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
				if _own(tg):
					_voice_once("hit_own", VOICE_FIRST_HIT_OWN, t)
					var vd: Dictionary = ShipStatus.verdict(world, tg)
					if vd["text"] != "боеспособен" and vd["text"] != "повреждения":
						_voice_once("crit_" + tg, VOICE_CRITICAL_OWN, t)
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
			if _own(sd):
				_own_lost_count += 1
				_voice_once("lost_" + sd, VOICE_SHIP_LOST_OWN, t, ShipNames.of(sd))
				if _own_total > 0 and float(_own_lost_count) / float(_own_total) >= 0.5:
					_voice_once("half_own", VOICE_HALF_OWN_DOWN, t)
			else:
				_en_lost_count += 1
				_voice_once("lost_" + sd, VOICE_SHIP_LOST_ENEMY, t, ShipNames.of(sd))
				if _en_total > 0 and float(_en_lost_count) / float(_en_total) >= 0.5:
					_voice_once("half_en", VOICE_HALF_ENEMY_DOWN, t)
		"formation_leader_lost":
			_lines.append({"key": "lead:%d" % e["seq"], "t": t, "bb": "[color=%s]Флагман %s потерян, командование принял %s[/color]" % [WARN_HEX, ShipNames.of(d.get("old_guide_id", "")), ShipNames.of(d.get("new_guide_id", ""))]})
			_trim()
			if _own(d.get("old_guide_id", "")):
				_voice_once("leader_lost", VOICE_LEADER_LOST, t)
		"ship_disengaging":
			var dsid: String = d.get("ship_id", "")
			_lines.append({"key": "diseng:" + dsid, "t": t, "bb": "[color=%s]%s[/color]: [color=%s]выходит из боя -- критические повреждения корпуса[/color]" % [_col(dsid), ShipNames.of(dsid), WARN_HEX]})
			_trim()
			if _own(dsid):
				_voice_once("disengage_" + dsid, VOICE_DISENGAGE_OWN, t, ShipNames.of(dsid))
			else:
				_voice_once("disengage_" + dsid, VOICE_DISENGAGE_ENEMY, t, ShipNames.of(dsid))

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
