extends RefCounted
## Scenarios
##
## 2026-09-29 (user: "попробуй разнообразить игру ... давай сценарии и
## контрракеты. И их запас"): until now every battle was the SAME
## engagement -- two equal squadrons closing bow-on from 5.3 million km.
## A scenario is pure DATA (no simulation logic): initial geometry (range,
## bearing, headings, speeds), default force compositions, each side's
## counter-missile stock multiplier and the enemy's doctrine (counter-
## missile policy / combat attitude), plus briefing text. DemoScenario.
## build() reads it; the mission editor lets the player pick one (and still
## edit the composition afterwards).
##
## Geometry conventions (world axes as everywhere else: -Z is the RED
## squadron's original bow direction, RED starts at the origin):
##   - `bearing_deg`: direction from RED's start to BLUE's start,
##     0 = straight ahead of red (-Z), +90 = red's +X side, 180 = astern.
##   - `red_yaw_deg`: red's heading, same yaw convention (0 = -Z,
##     180 = +Z, 90 = +X).
##   - blue's heading is "toward red" (its own bow on red) plus
##     `blue_aim_offset_deg` (positive = turned toward +yaw), so a crossing /
##     flanking approach is expressed as an aim offset instead of a
##     hand-computed angle.
## All numbers are pacing choices (ASSUMPTIONS.md "сценарии"), not canon.
class_name Scenarios

const ORDER: Array = ["intercept", "head_on", "flank", "pursuit", "ambush", "swarm"]

const DATA: Dictionary = {
	"intercept": {
		"title": "Перехват у Сент-Лорана",
		"short": "Перехват",
		"tagline": "Классика: дальний ракетный дуэль с 5,3 млн км, борт к борту.",
		"place": "1904 г. П.Д., система Сент-Лоран, граница Звёздного королевства Мантикора.",
		"situation": "Разведка засекла рейдовую эскадру Народного флота Хевена: {blue} идут к транспортам, стоящим у местной станции. Официально войны нет, но «неопознанные» корабли уже дважды нападали на мантикорские конвои в этом секторе.",
		"geometry": "Дистанция ~5,3 млн км, сближение ~600 км/с: ракеты полетят с самого начала боя, подлёт около двух с половиной минут.",
		"task": "не допустить противника к транспортам — уничтожить эскадру или вынудить её отойти, сохранив как можно больше своих кораблей.",
		"sep_m": 5.3e9, "bearing_deg": 0.0,
		"red_yaw_deg": 0.0, "blue_aim_offset_deg": 0.0,
		"red_speed": 3.0e5, "blue_speed": 3.0e5,
		"red_thrust": 0.8, "blue_thrust": 0.8,
		"red_cm_mult": 1.0, "blue_cm_mult": 1.0,
		"blue_cm_policy": "auto", "red_attitude": "broadside", "blue_attitude": "broadside",
		"setup": {
			"red": [{"class_id": "heavy_cruiser", "count": 4}],
			"blue": [{"class_id": "heavy_cruiser", "count": 4}],
		},
	},
	"head_on": {
		"title": "Встречный бой",
		"short": "Встречный бой",
		"tagline": "Короткая дистанция: ракеты в воздухе почти сразу, на раздумья — секунды.",
		"place": "Пустое пространство за внешней планетой, никаких ориентиров.",
		"situation": "Две эскадры вышли из гиперпространства почти лоб в лоб и увидели друг друга слишком поздно, чтобы разойтись: у вас {red}, у противника — {blue}.",
		"geometry": "Дистанция ~1,6 млн км, сближение ~400 км/с. Подлёт ракет — меньше минуты, у ПРО и контрракет почти нет времени на второй заход.",
		"task": "выиграть ракетный обмен первым залпом и не дать себя расстрелять на подходе — уничтожить или отбросить эскадру противника.",
		"sep_m": 1.6e9, "bearing_deg": 0.0,
		"red_yaw_deg": 0.0, "blue_aim_offset_deg": 0.0,
		"red_speed": 2.0e5, "blue_speed": 2.0e5,
		"red_thrust": 0.5, "blue_thrust": 0.5,
		"red_cm_mult": 1.0, "blue_cm_mult": 1.0,
		"blue_cm_policy": "auto", "red_attitude": "broadside", "blue_attitude": "broadside",
		"setup": {
			"red": [{"class_id": "battlecruiser", "count": 2}, {"class_id": "light_cruiser", "count": 2}],
			"blue": [{"class_id": "battlecruiser", "count": 2}, {"class_id": "light_cruiser", "count": 2}],
		},
	},
	"flank": {
		"title": "Фланговый удар",
		"short": "Фланг",
		"tagline": "Противник заходит с траверза: строй развёрнут не туда, где он появился.",
		"place": "Выход на орбиту газового гиганта, эскадра идёт в походном порядке.",
		"situation": "Пока вы шли к точке сбора, {blue} вышли на перехват с правого траверза. Ваш строй — фронтом по курсу, а не к противнику.",
		"geometry": "Противник справа под ~70° к курсу, дистанция ~3,4 млн км, идёт на пересечение курса. Ракеты бьют почти сразу; борта и клин придётся разворачивать по ходу боя.",
		"task": "перестроиться под удар, развернуть корабли бортом или клином к залпам и уничтожить или отбросить противника.",
		"sep_m": 3.4e9, "bearing_deg": 70.0,
		"red_yaw_deg": 0.0, "blue_aim_offset_deg": 30.0,
		"red_speed": 3.0e5, "blue_speed": 4.0e5,
		"red_thrust": 0.8, "blue_thrust": 0.8,
		"red_cm_mult": 1.0, "blue_cm_mult": 1.0,
		"blue_cm_policy": "auto", "red_attitude": "course", "blue_attitude": "broadside",
		"setup": {
			"red": [{"class_id": "heavy_cruiser", "count": 4}],
			"blue": [{"class_id": "battlecruiser", "count": 2}, {"class_id": "heavy_cruiser", "count": 2}],
		},
	},
	"pursuit": {
		"title": "Погоня",
		"short": "Погоня",
		"tagline": "Противник догоняет с кормы: корма и нос не прикрыты клином.",
		"place": "Отход от разгромленного конвоя, эскадра уходит на север.",
		"situation": "{red} отходят, прикрывая уходящие транспорты. За кормой — {blue}, они быстрее и медленно догоняют.",
		"geometry": "Противник в кормовой полусфере, дистанция ~2,8 млн км, он быстрее на ~300 км/с. Ракеты приходят в корму, где клин не защищает.",
		"task": "продержаться, пока транспорты не уйдут: отбить залпы, ответить на огонь и не дать догнавшим противникам расстрелять эскадру с кормы.",
		"hold_s": 900.0,
		"sep_m": 2.8e9, "bearing_deg": 180.0,
		"red_yaw_deg": 0.0, "blue_aim_offset_deg": 0.0,
		"red_speed": 3.0e5, "blue_speed": 6.0e5,
		"red_thrust": 0.8, "blue_thrust": 0.9,
		"red_cm_mult": 1.0, "blue_cm_mult": 1.0,
		"blue_cm_policy": "auto", "red_attitude": "auto", "blue_attitude": "broadside",
		"setup": {
			"red": [{"class_id": "heavy_cruiser", "count": 4}],
			"blue": [{"class_id": "battlecruiser", "count": 3}],
		},
	},
	"ambush": {
		"title": "Засада",
		"short": "Засада",
		"tagline": "Вы дрейфуете без хода, противник сильнее и уже на подходе.",
		"place": "Дрейф у заброшенной станции, двигатели заглушены для скрытности.",
		"situation": "Эскадра стояла в дрейфе, экономя энергию. Сенсоры поздно засекли {blue}: они шли на вас с выключенными опознавательными сигналами.",
		"geometry": "Ваша скорость почти нулевая (~50 км/с), противник справа-спереди, дистанция ~2,2 млн км, скорость ~600 км/с. Превосходство противника в числе, но у него меньше запас контрракет.",
		"task": "быстро набрать ход и развернуться к бою, использовать запас контрракет и выиграть время — уничтожить или отбросить превосходящего противника.",
		"sep_m": 2.2e9, "bearing_deg": 40.0,
		"red_yaw_deg": 0.0, "blue_aim_offset_deg": 0.0,
		"red_speed": 5.0e4, "blue_speed": 6.0e5,
		"red_thrust": 0.0, "blue_thrust": 0.8,
		"red_cm_mult": 1.5, "blue_cm_mult": 0.5,
		"blue_cm_policy": "auto", "red_attitude": "auto", "blue_attitude": "broadside",
		"setup": {
			"red": [{"class_id": "heavy_cruiser", "count": 4}],
			"blue": [{"class_id": "heavy_cruiser", "count": 6}],
		},
	},
	"swarm": {
		"title": "Волчья стая",
		"short": "Стая",
		"tagline": "Восемь лёгких кораблей против трёх тяжёлых: залпы насыщают вашу оборону.",
		"place": "Внешний пояс, рейдеры охотятся на одиночные эскадры.",
		"situation": "Против вашей эскадры ({red}) вышла стая мелких кораблей — {blue}. Каждый по отдельности слаб, но вместе они выпускают столько ракет, что ПРО не успевает.",
		"geometry": "Дистанция ~4,2 млн км, противник под ~25° к курсу. Запас контрракет у стаи небольшой, но расходуют они его сразу, не экономя.",
		"task": "не дать насытить оборону: экономьте контрракеты для крупных залпов, концентрируйте огонь и не допустите гибели флагмана.",
		"sep_m": 4.2e9, "bearing_deg": 25.0,
		"red_yaw_deg": 0.0, "blue_aim_offset_deg": 0.0,
		"red_speed": 3.0e5, "blue_speed": 4.0e5,
		"red_thrust": 0.8, "blue_thrust": 0.8,
		"red_cm_mult": 1.0, "blue_cm_mult": 1.0,
		"blue_cm_policy": "auto", "red_attitude": "broadside", "blue_attitude": "broadside",
		"setup": {
			"red": [{"class_id": "battlecruiser", "count": 3}],
			"blue": [{"class_id": "destroyer", "count": 8}],
		},
	},
}

static func get_data(id: String) -> Dictionary:
	return DATA.get(id, DATA["intercept"])

static func title_of(id: String) -> String:
	return String(get_data(id).get("title", "Перехват"))

static func short_of(id: String) -> String:
	return String(get_data(id).get("short", id))

static func tagline_of(id: String) -> String:
	return String(get_data(id).get("tagline", ""))

## Deep copy of the scenario's default force composition, in the shape
## DemoScenario.build()/the mission editor use ({"red": [...], "blue": [...]}).
static func default_setup_for(id: String) -> Dictionary:
	return get_data(id)["setup"].duplicate(true)

## Yaw (radians, project convention: 0 = facing -Z, PI = facing +Z, PI/2 =
## facing +X) of the horizontal direction `dir`.
static func yaw_of(dir: Vector3) -> float:
	return atan2(dir.x, -dir.z)

static func heading_of(yaw_rad: float) -> Vector3:
	return Vector3(sin(yaw_rad), 0.0, -cos(yaw_rad))

## World-space start position of BLUE's squadron centre (RED sits at the
## origin), from the scenario's range + bearing.
static func blue_center(id: String) -> Vector3:
	var d: Dictionary = get_data(id)
	return heading_of(deg_to_rad(float(d["bearing_deg"]))) * float(d["sep_m"])

static func red_yaw_rad(id: String) -> float:
	return deg_to_rad(float(get_data(id)["red_yaw_deg"]))

## Blue heads for red's start point, plus the scenario's aim offset.
static func blue_yaw_rad(id: String) -> float:
	var d: Dictionary = get_data(id)
	var to_red: Vector3 = (-blue_center(id)).normalized()
	return yaw_of(to_red) + deg_to_rad(float(d["blue_aim_offset_deg"]))
