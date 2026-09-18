# ARCHITECTURE.md

Соответствует ТЗ §42 (Simulation Architecture).

## Принцип

`simulation/` не знает о Node3D/рендере. `scripts/` (рендер) только читает
объекты из `simulation/` и не принимает боевых/физических решений.

## Реализовано (Milestone 1)

* `SimClock` — детерминированные fixed-timestep тики (60 Hz), time scale,
  pause, single-step (ТЗ §43, §44). Ещё не подключены UI-кнопки управления
  временем — это Milestone позже.
* `ShipPhysicsState` — полное 3D состояние корабля: position/velocity/
  acceleration (Vector3), orientation (Quaternion), angular velocity/
  acceleration, relative velocity, closure velocity, distance (ТЗ §6, §11-13).
  Thrust → acceleration → velocity → position (§12), инерционное движение
  (нулевая тяга не гасит скорость — покрыто тестом).
* `SimulationWorld` — держит все корабли, тикает их от `SimClock`.
* `ShipView` — рендер-нода, один в один читает `ShipPhysicsState`.

## Ещё не реализовано (не выдавать за готовое, ТЗ §58/§59)

Wedge/sidewalls, weapons, missiles, counter-missiles, sensors, ECM, damage,
AI, formations, command hierarchy, replay, scenarios, UI — все следующие
Milestone 3+ по §56. Текущий `main.gd` — это только bring-up с двумя кубами
вместо кораблей, для проверки связки Simulation/Rendering.

## Milestone 3: Wedge / Sidewalls (реализовано)

* `simulation/attack_geometry.gd` — `AttackGeometry.classify()`: по
  позициям атакующего/цели и ориентации цели определяет сектор атаки
  (TOP/BOTTOM/BOW/STERN/PORT/STARBOARD) в локальных координатах цели
  (ТЗ §10). Не знает о прочности защиты — только геометрия.
* `simulation/ship_defense_state.gd` — `ShipDefenseState.resolve_attack()`:
  раздельная логика для wedge (TOP/BOTTOM — почти непробиваем, пока wedge
  поднят), бортовых sidewalls (PORT/STARBOARD — attenuation по condition,
  НЕ shieldHP-пул) и носовых/кормовых sidewalls (BOW/STERN — не защищены,
  если стенка не поднята; если поднята — ослабляют, но уязвимы под острым
  углом к своей же оси, согласно канону). ТЗ §9, §16.
* `ship_physics_state.gd` — интегрировал канон "поднятая носовая/кормовая
  sidewall блокирует impeller-ускорение": пока `defense.bow_sidewall_raised`
  или `stern_sidewall_raised` истинно, тяга обнуляется в `integrate()`.
* Все числовые пороги (burnout threshold, кривая attenuation, угол
  уязвимости) — задокументированные ASSUMPTION-placeholder, см.
  ASSUMPTIONS.md, не выданы за канон.
* Тесты: `simulation/tests/test_wedge_sidewall.gd` — классификация секторов
  по всем 6 направлениям, wedge блокирует/не блокирует в зависимости от
  своего состояния, sidewall attenuation vs burnout, bow sidewall блокирует
  тягу. Прогнаны через Godot v4.3-stable headless: `ALL TESTS PASSED`,
  exit 0 (вместе с Milestone 1 тестами — оба набора зелёные после
  пересборки global_script_class_cache через `--import`).

## Milestone 4: Energy Weapons (реализовано)

* `simulation/weapon_data.gd` — data-driven описание оружия (id, класс,
  range, damage, recharge) — ТЗ §8, §17, §48. Значения — ASSUMPTION
  placeholder, см. ASSUMPTIONS.md.
* `simulation/weapon_mount.gd` — физическая установка на корабле: оружие +
  огневой сектор (`broadside_arc()`, `bow_chaser_arc()`, `stern_chaser_arc()`)
  + cooldown + condition. CLOUD.md §2.2 ("limited by weapon charging cycles
  and exact firing arcs").
* `simulation/hull_state.gd` — ВРЕМЕННЫЙ (§58) единый пул прочности корпуса,
  чтобы было что повреждать до появления полноценной §25 subsystem damage
  модели в Milestone 8. Явно помечен как подлежащий замене.
* `simulation/weapon_resolution.gd` — `WeaponResolution.fire()`: проверяет
  range → cooldown → огневой сектор атакующего (в его собственной системе
  координат) → защиту цели через `ShipDefenseState.resolve_attack()`
  (её собственная система координат) → применяет урон к `HullState`.
  Связывает Milestone 3 (геометрия/защита) с реальным уроном впервые.
* Тесты `test_weapon_resolution.gd` — 6 проверок: out-of-range, cooldown,
  отсутствие огневого сектора, блокировка wedge, реальный урон через
  ослабленный sidewall (0.4 condition — полностью исправный 1.0 по модели
  §16 гасит 100% урона, это намеренно, не баг), расход cooldown при
  выстреле. Все зелёные (headless Godot 4.3, exit 0), вместе с Milestone 1
  и 3 тестами (итого 3 test-файла, все ALL TESTS PASSED).
* Демо-сцена (`main.gd`): оба демо-корабля получили `HullState` и один
  bow-chaser лазер (пока не стреляют автоматически — это Milestone AI/
  ручное управление, здесь только тикает cooldown).

## Milestone 5: Missiles + Guidance (реализовано)

* `simulation/kinematics_utils.gd` — вынесена общая интеграция (thrust→
  velocity→position, clamp по c, поворот по угловой скорости) из
  `ship_physics_state.gd`, чтобы не дублировать её в `missile_state.gd`.
  `ShipPhysicsState` отрефакторен на использование этого модуля (поведение
  не изменилось — все старые тесты остались зелёными после рефакторинга).
* `simulation/missile_state.gd` — полноценная 3D-сущность ракеты (ТЗ §18):
  position/velocity/acceleration/orientation, target, guidance_state
  (BOOST/MIDCOURSE/TERMINAL/DETONATED/SELF_DESTRUCTED/LOST), sensor_state
  (переиспользует состояния §23), lifetime, warhead_armed. Двигатель горит
  ограниченное время (канон-пример 46 000G/180с), после чего ракета летит
  баллистически без манёвра — не "вечный" арcade-снаряд.
* `simulation/missile_guidance.gd` — `MissileGuidance.compute_thrust_direction()`
  реализует predicted intercept (несколько итераций уточнения точки
  перехвата по target position + target velocity), а не прямое наведение
  на текущую позицию цели — прямое требование §19. При потере захвата
  (`SensorState.LOST`) — держит текущий курс, а не "телепортирует" наводку.
* Тесты `test_missile.gd` — 5 проверок: наведение реально "упреждает" цель
  при боковой скорости (не наивное преследование), двигатель ускоряет
  только во время горения и потом гаснет, ракета доходит до цели и
  переходит в TERMINAL, потеря захвата не ломает курс, self-destruct по
  истечении времени жизни. Все зелёные вместе с остальными 3 файлами
  тестов (headless Godot v4.3-stable, exit 0).

## Milestone 5 (продолжение): Laserhead Detonation (реализовано)

* `simulation/missile_resolution.gd` — `MissileResolution.resolve_detonation()`:
  замыкает цепочку ракета→подрыв→урон, переиспользуя
  `ShipDefenseState.resolve_attack()` (тот же путь, что и энергетическое
  оружие в Milestone 4). Защищает от повторного подрыва (`has_detonated`).
  Явно задокументирована INTERPRETATION-трактовка laserhead как
  однонаправленного удара (не полная модель с разводящими штангами) —
  см. ASSUMPTIONS.md.
* Тесты `test_missile_resolution.gd` — 4 проверки: невзведённая боеголовка
  не подрывается, незащищённое попадание бьёт по корпусу, wedge блокирует,
  повторный подрыв невозможен. Зелёные.

## Milestone 5 (продолжение 2): Lasing Rod Fan-Out (реализовано)

* `simulation/lasing_rod.gd` — лёгкая resolution-time сущность одной
  штанги (позиция + потенциал урона). Существует только в момент подрыва,
  не тикается как полноценная simulation entity (канон описывает это как
  часть терминальной фазы, не отслеживаемый отдельно полёт — §21.4
  оставляет точный тайминг UNKNOWN).
* `missile_state.gd` — добавлены `rod_count`, `rod_offset_m`,
  `rod_spread_half_angle_rad` (все — по §21.1/§21.2 AGENTS.md).
* `missile_resolution.gd` — `compute_rod_positions()` (чистая функция,
  детерминированный веер позиций, без RNG — важно для §43 Deterministic
  Simulation) + `resolve_detonation()` теперь резолвит каждую штангу
  отдельным вызовом `ShipDefenseState.resolve_attack()`, суммирует урон,
  возвращает `rod_results` (по сектору/исходу/урону на штангу) для
  будущей визуализации/отладки (§53 Debug Tools).
* 3 новых теста (итого 7 в файле): количество и дистанция штанг верны,
  сумма урона по штангам равна общему урону боеголовки, режим с
  rod_count=1 не ломается (обратная совместимость с предыдущим
  однолучевым поведением). Все зелёные, весь набор (5 файлов / 26
  проверок) — тоже зелёный.
* Явно НЕ реализовано (см. ASSUMPTIONS.md): суббоеприпасы с независимым
  выбором разных целей (Mark 13 style) — это отдельная фича мультитаргетинга.

## Milestone 6a: Counter-Missiles (реализовано)

* `missile_state.gd`: `target` разтипизирован (был `ShipPhysicsState`,
  стал untyped) — контрракета целится в `MissileState`, не в корабль;
  `MissileGuidance` работает с любой целью через duck typing (position/
  velocity), без дублирования кода наведения. Добавлено состояние
  `GuidanceState.INTERCEPTED` + `is_intercepted()`.
* `counter_missile_resolution.gd` — `CounterMissileResolution.check_intercept()`:
  канонический механизм перехвата — контрракета наводится на входящую
  ракету и убивает её (и сама гибнет) при сближении на дистанцию
  наложения клиньев (`INTERCEPT_KILL_RADIUS_M` — ASSUMPTION placeholder,
  точная цифра не найдена в источниках). НЕ прямое столкновение и НЕ
  обычный подрыв боеголовки рядом — специально смоделирован как отдельная
  механика, отличная от `missile_resolution.gd` (laserhead vs корабль).
* Тесты `test_counter_missile.gd` — 5 проверок, включая end-to-end:
  контрракета реально наводится (переиспользуя `MissileGuidance`) и
  перехватывает баллистическую входящую ракету в пределах разумного числа
  тиков. Все зелёные.

## Milestone 5 (продолжение 3): физика полёта ракет — throttle (реализовано)

* `missile_state.gd`: `set_throttle(fraction)` — дросселирование
  двигателя по канону (АGENTS.md §18.1): снижение ускорения увеличивает
  время горения, по модели константного бюджета delta-v (ASSUMPTION,
  см. ASSUMPTIONS.md). `estimated_powered_range_m()` — инженерная оценка
  дальности на активном участке (0.5*a*t²), используется в тесте-проверке
  правдоподобия против цитаты канона ("46 000G/180с → свыше 6 млн км").
* 2 новых теста в `test_missile.gd`: throttle корректно меняет
  accel/burn_time с сохранением бюджета; формула дальности попадает в
  диапазон, согласующийся с канонической цитатой. Оба зелёные.
* Честно НЕ реализовано (см. CANON_RULES.md/ASSUMPTIONS.md): многоступенчатые
  MDM, вращение ракеты для PD, пусковые трубы/mass driver, зависимость
  ослабления sidewall от типа боеголовки.

## Закрытие TODO: Damage-Type-Aware Sidewall Attenuation (реализовано)

* `damage_type.gd` — общий enum, чтобы избежать циклических зависимостей
  между `weapon_data.gd`/`missile_state.gd`/`ship_defense_state.gd`.
* `ship_defense_state.gd` — `resolve_attack()` принимает `damage_type`
  (default ENERGY), применяет `LASERHEAD_SIDEWALL_PENETRATION_MULTIPLIER`
  к transmitted_fraction для LASERHEAD-атак (и на broadside, и на
  bow/stern), всегда clamp в [0,1].
* `weapon_resolution.gd` / `missile_resolution.gd` — передают ENERGY /
  LASERHEAD соответственно.
* Новый тест в `test_wedge_sidewall.gd`: при одинаковом condition sidewall
  laserhead проходит больше энергии, чем энергетическое оружие. Зелёный.

## Первый визуальный прототип (реализовано, по запросу пользователя)

* `scripts/hull_mesh_builder.gd` — процедурная генерация меша корпуса
  ("flattened spindle" + hammerhead, см. CANON_RULES.md пятая сверка) —
  чистая функция профиля радиуса + SurfaceTool для сборки геометрии.
  Протестирована headless (`test_hull_mesh_builder.gd`, 3 проверки):
  форма меша, профиль узкий на концах/широкий в середине, нет
  вырожденных вершин.
* `ship_physics_state.gd` — добавлены `length_m`/`max_width_m`/
  `max_height_m` (данные для рендера, ТЗ §8).
* `scripts/ship_view.gd` — переписан: строит меш корпуса из
  `HullMeshBuilder` (вместо BoxMesh-заглушки) + визуализацию wedge
  (два полупрозрачных плоскости сверху/снизу), видимость которых
  напрямую читает `sim_state.defense.wedge_up` — не отдельный источник
  истины, честный readout уже существующей логики.
* `scripts/main.gd` — камера теперь вычисляется по трём точкам реально
  на основе позиций кораблей и FOV (`_frame_camera_on_ships`), вместо
  фиксированной трансформации в .tscn, которая (обнаружено при
  визуальной проверке) на самом деле НЕ смотрела на корабли — это баг
  Milestone 1, необнаруженный ранее, т.к. headless-тесты не проверяют
  визуальный кадр.
* `scenes/main.tscn` — добавлен WorldEnvironment (чёрный фон космоса
  вместо серого по умолчанию, §50 Visual Style), fill-свет.
* Dev-инструменты (НЕ часть игры, `scenes/dev/`):
  `screenshot_capture.gd/tscn` — рендерит основную демо-сцену и
  сохраняет PNG; `closeup_capture.gd/tscn` — крупный план одного
  корабля. Использованы для реальной визуальной проверки через Xvfb +
  Godot (не headless — headless вообще не рендерит) в этой сессии;
  оставлены в проекте как полезный debug-инструмент (§53) для будущей
  визуальной регрессии, не для финальной игры.
* Реальные скриншоты сгенерированы и просмотрены в этой сессии
  (llvmpipe software rendering через Xvfb) — подтверждено визуально, не
  только "должно работать": корпус имеет узкие нос/корму и широкую
  середину, wedge отображается только когда поднят, оба корабля видны
  на боевой дистанции.

## Milestone: Point Defense (реализовано)

* `point_defense_mount.gd` — состояние PD-установки: дистанция вовлечения,
  время реакции, recharge, число попаданий для уничтожения, condition.
  Отслеживает прогресс ПО КОНКРЕТНОЙ цели (`_tracking_target`,
  `_tracking_time_s`, `_hits_scored`) — переключение цели или выход
  ракеты из радиуса сбрасывает прогресс (реалистичное следствие "время
  реакции" как реальной стоимости, не бесплатного мгновенного отклика).
* `point_defense_resolution.gd` — `PointDefenseResolution.engage()`:
  резолвит одно вовлечение за тик для УЖЕ ВЫБРАННОЙ цели (выбор цели —
  задача AI, не этого модуля, тот же принцип разделения ответственности,
  что у `WeaponResolution`). При накоплении нужного числа попаданий
  выставляет `MissileState.GuidanceState.INTERCEPTED` — переиспользует
  то же состояние, что и контрракеты (Milestone 6a), единая семантика
  "ракета уничтожена оборонительной системой" независимо от того, какой
  слой обороны это сделал.
* Тесты `test_point_defense.gd` — 6 проверок: нет цели, вне радиуса,
  накопление времени реакции, полный цикл до уничтожения, сброс прогресса
  при смене цели, сброс прогресса при выходе ракеты из радиуса. Все
  зелёные. Полный набор: 8 файлов тестов, 47+ проверок.

## Улучшение визуализации клина (по замечанию пользователя после первого прототипа)

* `scripts/wedge_mesh_builder.gd` — процедурный V-образный ("шатёр")
  клин вместо плоского PlaneMesh: узко у центра корабля, шире к носу/
  корме. `ship_view.gd` использует его вместо `_make_wedge_plane`.
  Тесты `test_wedge_mesh_builder.gd` (3 проверки) — форма, зеркальность
  top/bottom, профиль ширины. Полный набор: 9 файлов тестов, 50+ проверок,
  все зелёные.
* Визуально проверено через Xvfb-скриншот, отправлено пользователю.

## Milestone: Sensors (§23) — первая версия

* `simulation/contact_state.gd` — `ContactState.Type` enum
  (UNKNOWN/DETECTED/TRACKED/ESTIMATED/UNCERTAIN/LOST), единый источник
  истины для confidence-состояний контакта. `MissileState.SensorState`
  теперь АЛИАС на этот enum (`const SensorState = ContactState.Type`)
  вместо дублирования — самонаведение ракеты и будущие sensor-контакты
  кораблей используют одну и ту же семантику состояний.
* `simulation/sensor_contact.gd` — `SensorContact`: чисто данные (ТЗ §8/
  §48 data-driven, правила обнаружения НЕ здесь). Держит
  duck-typed `target` (ShipPhysicsState или MissileState — не важно,
  какой, лишь бы были `.position`/`.velocity`), текущее `state`,
  оценку `estimated_position/estimated_velocity` (актуальную позицию
  при обнаружении, dead-reckoned — при ESTIMATED), и таймеры
  `continuous_detection_s`/`time_since_lost_s`, которые двигают
  state machine.
* `simulation/sensor_resolution.gd` — `SensorResolution`: логика
  тика. `_is_emitting_signature(entity)` — duck-typed проверка
  "испускает ли цель обнаружимую сигнатуру прямо сейчас" (корабль:
  `defense.wedge_up`; ракета: `drive_burn_remaining_s > 0`), прямое
  инженерное следствие подтверждённого канона (CANON_RULES.md
  "Седьмая сверка", первоисточник "On Basilisk Station" гл.3).
  `update_contact(contact, observer_position, dt, sensor_range_m)` —
  один тик state machine: not-detected→DETECTED (первый контакт)
  →TRACKED (после `DETECTED_TO_TRACKED_TIME_S` непрерывного контакта)
  →ESTIMATED (dead-reckoning coast после потери контакта)→LOST (после
  `ESTIMATED_GRACE_PERIOD_S`). Повторное обнаружение из ESTIMATED/
  UNCERTAIN/LOST возвращает в DETECTED, не сразу в TRACKED — заново
  зарабатывается устойчивость контакта. `update_contacts(...)` —
  удобная обёртка create-or-update по словарю контактов, ключ —
  произвольный id, выбранный вызывающим кодом (например id корабля).
* Как и `WeaponResolution`/`PointDefenseResolution`, модуль НЕ решает,
  кого атаковать/наводиться — только обновляет уверенность в контакте.
  Подключение к `MissileGuidance`/`PointDefenseResolution` (чтобы
  наведение и ПРО перестали "видеть" цель идеально всегда) — следующий
  шаг, ещё не сделан (см. CHANGELOG.md/ASSUMPTIONS.md).
* Тесты `simulation/tests/test_sensor_resolution.gd` — 13 проверок:
  обнаружение в радиусе/по сигнатуре, отсутствие обнаружения при
  погашенном клине, отсутствие обнаружения вне радиуса, ракета
  обнаружима при горящем двигателе / не обнаружима при погашенном,
  DETECTED→TRACKED после устойчивого контакта, ESTIMATED→LOST после
  grace period, dead reckoning корректно двигает оценку позиции,
  повторное появление цели возвращает DETECTED. Все зелёные. Полный
  набор: 10 файлов тестов, 60+ проверок, все зелёные.

## Подключение сенсоров к наведению ракет (§23 → §19)

* `missile_state.gd` — добавлено поле `sensor_contact` (изначально `null`,
  ленивая инициализация) и `sensor_state` теперь по умолчанию `UNKNOWN`
  (раньше — `TRACKED`, то есть "идеальная информация с рождения"). Старое
  поведение НЕ сломано: любой тест/вызывающий код, который сам явно
  передаёт `SensorState.TRACKED` в `compute_thrust_direction()`, продолжает
  работать как раньше — "идеальное наведение" остаётся доступно, просто
  больше не единственный путь по умолчанию.
* `missile_guidance.gd` — два новых статических метода:
  `update_target_tracking(missile, dt, sensor_range_m)` создаёт/обновляет
  `missile.sensor_contact` через `SensorResolution.update_contact()` и
  синхронизирует `missile.sensor_state`; `resolve_thrust_direction(missile,
  dt, sensor_range_m)` — сенсорно-честная замена прямому вызову
  `compute_thrust_direction()`: считает направление тяги по ОЦЕНКЕ
  наблюдателя (`sensor_contact.estimated_position/velocity`), а не по
  истинной позиции цели. Раньше ракета всегда "видела" цель идеально
  через `target.position` напрямую — это первый шаг, где несовершенство
  сенсоров реально влияет на поведение, а не просто существует как
  неиспользуемая система.
* `compute_thrust_direction()` расширен: раньше держал курс только при
  `SensorState.LOST`, теперь — при ЛЮБОМ состоянии, не являющемся
  DETECTED/TRACKED/ESTIMATED (то есть и при `UNKNOWN` — цель ещё ни разу
  не обнаружена). Иначе на первом тике, пока `sensor_contact` ещё не
  успел ничего обнаружить, ракета целилась бы в `Vector3.ZERO`
  (дефолтная `estimated_position` непроинициализированного контакта) —
  явный баг, пойманный именно тестом, а не проверкой "на глаз".
* Тесты `test_missile_guidance_sensors.gd` — 11 проверок: нет цели →
  держит курс; цель ещё не обнаружена (вне радиуса на первом тике) →
  держит курс, а не летит в ноль; обнаруженная цель → доворачивает на
  оценку; `sensor_contact` создаётся один раз и переиспользуется;
  погасший клин → ESTIMATED (dead reckoning), но наведение остаётся
  рабочим (не мгновенно LOST). Все зелёные. Полный набор: 11 файлов
  тестов, 73+ проверок, все зелёные.
* Честно НЕ сделано: `integrate()` (проверка входа в терминальную
  дальность/взвод боеголовки) по-прежнему использует истинную позицию
  цели (`target.position`), а не сенсорную оценку — детонация
  срабатывает по физической близости независимо от того, "видит" ли
  ракета цель. Это сознательно оставлено как отдельный, ещё не принятый
  вопрос (в реальности промах без захвата цели тоже возможен) — см.
  ASSUMPTIONS.md. `PointDefenseResolution`/`CounterMissileResolution`
  по-прежнему проверяют дистанцию напрямую, не через `SensorContact` —
  подключение ПРО к сенсорам не входило в этот шаг.

## Milestone 7 завершён: Sensors (§23) + ECM (§24)

* `ecm_state.gd` — `ECMState`: чисто данные. `jamming_active`,
  `jamming_range_multiplier` (ASSUMPTION=0.4), `decoy_positions`
  (Array, ограничен `MAX_DECOYS`=4 через `add_decoy()`/`clear_decoys()`),
  канон: Honorverse Wiki "Electronic warfare" (см. CANON_RULES.md
  "Восьмая сверка").
* `sensor_resolution.gd` расширен (обратно совместимо — новый параметр
  `target_ecm = null` у `update_contact()`/`update_contacts()`):
  `_effective_sensor_range_m()` — при активном глушении эффективная
  дальность наблюдателя против цели умножается на
  `jamming_range_multiplier`; `_resolve_apparent_return()` —
  наблюдатель захватывает ближайший к себе "возврат" среди истинной
  цели и всех активных decoy этой цели (детерминированно, без RNG,
  ТЗ §43). Оба эффекта — прямое следствие более глубокой модели
  сенсоров (дальность/геометрия), не плоский модификатор шанса
  попадания — ровно то, что требует ТЗ §24.
* Тесты `test_ecm.gd` — 9 проверок: без ECM обнаружение как раньше;
  активное глушение сокращает эффективную дальность (цель вне
  досягаемости, хотя без глушения была бы обнаружена); при достаточном
  сближении обнаружение всё равно проходит (глушение не ослепляет
  полностью); `jamming_active=false` не влияет; более близкая decoy
  подменяет собой позицию цели; более далёкая decoy игнорируется;
  `MAX_DECOYS` соблюдается; `clear_decoys()` работает. Все зелёные.
* Milestone 7 (§56: "Sensors + ECM") можно считать закрытым на уровне
  изолированной, протестированной логики: и `SensorResolution`
  (детекция/трекинг), и `ECMState`/глушение/decoy подключены друг к
  другу и (для наведения ракет и одного пути Point Defense) к
  вышестоящим модулям — `MissileGuidance.resolve_thrust_direction()`
  и `PointDefenseResolution.engage(..., sensor_contact)`.
* Честно НЕ сделано (по-прежнему): ECM не подключён отдельно к
  `PointDefenseResolution`/`CounterMissileResolution` (они получают
  уже готовый `SensorContact`, где ECM эффекты УЖЕ учтены на уровне
  формирования контакта наблюдателем — то есть эффект есть, но нет
  прямого API "поставь помеху конкретно против ПРО"); decoy drones не
  симулируются как отдельные физические сущности (их позиции задаются
  вызывающим кодом вручную, а не летящим дроном с собственной
  кинематикой) — ASSUMPTION-упрощение; корабль-уровневый `ECMState` не
  подключён нигде в `ShipPhysicsState`/`ShipDefenseState` как готовое
  поле — вызывающий код должен сам завести и передать `ECMState`.
  Полный набор: 13 файлов тестов, 87+ проверок, все зелёные.

## Milestone 8 начат: Subsystem Damage (§25)

* `subsystem_type.gd` — `SubsystemType.Type`, все 11 систем из ТЗ §25
  (propulsion, maneuvering, sensors, communications, weapons, missile
  systems, counter-missile systems, point defense, power, structural
  integrity, defensive systems) — единый источник истины для списка.
* `subsystem_state.gd` — `SubsystemState`: чисто данные, `integrity`
  0..1, `apply_damage()`/`repair()` (clamp), `is_disabled()` при 0.0.
* `ship_subsystems.gd` — `ShipSubsystems`: контейнер, один
  `SubsystemState` на каждый `SubsystemType`, все начинаются с полного
  здоровья. Честно задокументирован как КАНОНИЧЕСКИЙ, но пока НЕ
  единственный источник истины: `ShipPhysicsState.propulsion_condition`/
  `.compensator_condition`, `WeaponMount.condition`,
  `PointDefenseMount.condition` и sidewall-condition в
  `ShipDefenseState` существовали ДО этого Milestone как отдельные поля
  и пока не унифицированы с этим контейнером — сознательно отложенный
  рефакторинг, чтобы не расшатывать уже протестированные системы.
* Подключён один реальный потребитель, прямо по примеру из ТЗ §25
  ("sensor damage → degraded tracking"): `sensor_resolution.gd`
  получил новый опциональный параметр `observer_subsystems`
  (`ShipSubsystems` НАБЛЮДАТЕЛЯ, не цели) у `update_contact()`/
  `update_contacts()` — состояние `SENSORS` масштабирует эффективную
  дальность обнаружения непрерывно (`condition` как множитель), а
  полностью выведенный из строя сенсор (`is_disabled`) блокирует
  свежее обнаружение вообще, независимо от дальности. Урон по
  сенсорам и глушение (§24) складываются мультипликативно, не
  перезаписывая друг друга.
* Тесты: `test_ship_subsystems.gd` (28 проверок — все 11 подсистем
  стартуют с полного здоровья, `apply_damage`/`repair`/clamp/
  `is_disabled` для представительных подсистем) и
  `test_sensor_subsystem_damage.gd` (5 проверок — неповреждённые
  сенсоры детектируют как раньше; повреждённые сокращают эффективную
  дальность настолько, что обнаружение срывается; полностью выбитые
  сенсоры блокируют обнаружение даже в упор; отсутствие параметра
  сохраняет старое поведение; урон и РЭБ складываются, а не
  перекрывают друг друга). Все зелёные. Полный набор: 15 файлов
  тестов, 120+ проверок, все зелёные.
* Честно НЕ сделано (Milestone 8 не закрыт полностью): остальные 10
  подсистем (`PROPULSION`, `MANEUVERING`, `COMMUNICATIONS`, `WEAPONS`,
  `MISSILE_SYSTEMS`, `COUNTER_MISSILE_SYSTEMS`, `POINT_DEFENSE`,
  `POWER`, `STRUCTURAL_INTEGRITY`, `DEFENSIVE_SYSTEMS`) есть в
  контейнере, но НИКЕМ не читаются — ни один консьюмер их пока не
  проверяет. Нет ничего, что распределяло бы входящий урон по
  подсистемам (какая подсистема "получает" урон при попадании) — это
  отдельная, ещё не решённая задача (вероятно: направление/сектор
  атаки → вероятная подсистема, детерминированно по геометрии, не по
  RNG, аналогично §21 lasing rod fan-out). Нет UI/AI, которые бы
  реагировали на `is_disabled()`.

## Milestone 8 продвинут: распределение урона по подсистемам

* `subsystem_damage_resolution.gd` — `SubsystemDamageResolution.apply_hit(subsystems, damage_amount, sector)`:
  решает, КАКАЯ подсистема получает урон при попадании, по секторному
  признаку (`AttackGeometry.Sector`, уже вычисляемому
  `WeaponResolution`/`MissileResolution` для клина/сайдволлов). Карта
  секторов → подсистем (TOP→SENSORS, BOTTOM→COMMUNICATIONS,
  BOW→MANEUVERING, STERN→PROPULSION, PORT→WEAPONS,
  STARBOARD→POINT_DEFENSE) — ЧЕСТНО помечена как ИНЖЕНЕРНАЯ ДОГАДКА, не
  канон (источника, какая система стоит за какой обшивкой, не найдено).
  `STRUCTURAL_INTEGRITY` получает долю урона от КАЖДОГО попадания
  независимо от сектора. Детерминированно, без RNG (ТЗ §43).
* `WeaponResolution.fire()` и `MissileResolution.resolve_detonation()`
  получили новый опциональный параметр `target_subsystems` (по
  умолчанию `null` — старое поведение без изменений, обратная
  совместимость для всех существующих вызовов/тестов). Когда передан,
  результат (`ShotResult`/`DetonationResult`) дополнительно несёт
  `subsystem_damage: Dictionary` с фактически применённым уроном по
  подсистемам. У ракеты урон применяется ПО КАЖДОМУ стержню отдельно,
  его собственным сектором — более детально, чем по кораблю целиком.
* Тесты `test_subsystem_damage_resolution.gd` — 13 проверок:
  `apply_hit` без ShipSubsystems/с нулевым уроном — no-op; секторная
  карта применяет урон к ожидаемой подсистеме; структурная целостность
  получает долю от любого попадания; неклассифицированный сектор
  (null) откатывается на STRUCTURAL_INTEGRITY; `WeaponResolution.fire`
  и `MissileResolution.resolve_detonation` корректно передают урон в
  ShipSubsystems, когда он передан, и НЕ ломают старое поведение, когда
  не передан. Все зелёные. Полный набор: 16 файлов тестов, 130+
  проверок, все зелёные, регрессий нет.
* Milestone 8 (§25) существенно продвинут: теперь есть контейнер (11
  подсистем), потребитель (SensorResolution) И распределение входящего
  урона по подсистемам от обоих типов оружия (энергетическое,
  лазерная головка ракеты). Честно НЕ закрыт: только SENSORS реально
  влияет на поведение потребителя; остальные 10 подсистем накапливают
  урон, но их condition пока никем, кроме тестов, не читается (нет
  потребителя для PROPULSION/MANEUVERING/WEAPONS/POINT_DEFENSE и
  других — их собственные, более старые condition-поля в других
  модулях остаются несвязанными с этим контейнером, см. ASSUMPTIONS.md).

## Milestone 8 продвинут: PROPULSION/MANEUVERING подключены к тяге корабля

* `ShipPhysicsState` получил новое опциональное поле `subsystems`
  (`ShipSubsystems`, по умолчанию `null` — старое поведение без
  изменений). `effective_max_acceleration()` теперь ДОПОЛНИТЕЛЬНО
  умножает на condition `PROPULSION` и `MANEUVERING` из этого
  контейнера, если он задан — складывается МУЛЬТИПЛИКАТИВНО со старыми
  полями `propulsion_condition`/`compensator_condition` (не заменяет
  их) — прямая реализация примера из самого ТЗ §25: "propulsion damage
  → degraded acceleration". Полная унификация старых полей с
  контейнером всё ещё сознательно отложена (см. ASSUMPTIONS.md), но
  теперь у урона, распределённого через `SubsystemDamageResolution` по
  сектору STERN (→PROPULSION) или BOW (→MANEUVERING), есть реальный,
  измеримый эффект на способность корабля маневрировать — не только
  накопление в изолированном контейнере.
* Тесты `test_propulsion_subsystem_damage.gd` — 6 проверок: без
  `subsystems` — старое поведение; неповреждённый контейнер не влияет;
  урон по PROPULSION пропорционально снижает ускорение; урон по
  MANEUVERING тоже снижает; полностью выбитый PROPULSION обнуляет
  ускорение; старые condition-поля и новый контейнер складываются
  мультипликативно (0.5×0.5=0.25), а не перекрывают друг друга. Все
  зелёные. Полный набор: 17 файлов тестов, 136+ проверок, все зелёные,
  регрессий нет.
* Итог по Milestone 8 на данный момент: из 11 подсистем реально влияют
  на игровое поведение — SENSORS (дальность обнаружения),
  PROPULSION и MANEUVERING (эффективное ускорение). Урон от обоих типов
  оружия (энергетическое, лазерная головка) реально распределяется по
  всем 11 категориям через сектор попадания, но у оставшихся 8
  (COMMUNICATIONS, WEAPONS, MISSILE_SYSTEMS, COUNTER_MISSILE_SYSTEMS,
  POINT_DEFENSE, POWER, STRUCTURAL_INTEGRITY, DEFENSIVE_SYSTEMS) урон
  накапливается, но никем не читается — честно зафиксировано, не
  скрыто.

## Milestone 1 наконец закрыт по-настоящему: первый живой игровой цикл

* `simulation_world.gd` полностью переписан. Раньше `SimulationWorld`
  тикал ТОЛЬКО физику кораблей — ни ракеты, ни сенсоры, ни ПРО, ни
  контрракеты, ни подсистемы никогда не вызывались вместе, ни одним
  циклом. Теперь `tick_simulation(dt)` (публичный метод, вызываемый и
  из `SimClock`-сигнала, и напрямую из тестов без SceneTree) на каждом
  тике выполняет по порядку: очистку неактивных ракет; обновление
  сенсорных контактов КАЖДОГО корабля по КАЖДОМУ другому кораблю и
  ракете (§23, с учётом ECM цели §24 и своего состояния SENSORS §25);
  наведение+полёт+детонацию каждой активной ракеты (§18/§19/§21, через
  `MissileGuidance.resolve_thrust_direction`); проверку перехвата
  контрракетами (§20); работу ПРО (§22, с сенсорным гейтингом через
  контакт корабля-цели); интеграцию физики всех кораблей (§12).
* Честно ограничено (не тактический AI, §26): выбор цели ПРО — это
  ЗАДОКУМЕНТИРОВАННЫЙ ПЛЕЙСХОЛДЕР ("ближайшая активная ракета,
  нацеленная именно на этот корабль"), не настоящая приоритизация
  угроз. Стрельба корабль-корабль НЕ автоматическая — `fire_weapon()`
  существует как явный вызов для вызывающего кода (сценарий/будущий
  AI), сам `SimulationWorld` не выбирает, кто по кому стреляет.
* Тесты `test_simulation_world.gd` — 8 сквозных (end-to-end) проверок:
  корабль с тягой набирает скорость через мировой цикл; ракета летит и
  получает сенсорный контакт у корабля-цели через мировой цикл; ракета
  детонирует по незащищённой цели и наносит урон корпусу, после чего
  сама убирается из `world.missiles` на следующем тике; ПРО способна
  обнаружить (через плейсхолдер-выбор) и перехватить входящую ракету
  ЧЕРЕЗ ВЕСЬ мировой цикл (не изолированным вызовом `engage()`, как
  раньше); `remove_ship`/`remove_missile` работают. Все зелёные.
  Полный набор: 18 файлов тестов, 144+ проверок, все зелёные,
  регрессий нет.
* Это первый раз, когда весь массив ранее написанной и протестированной
  логики (Milestones 2–8) реально работает СОВМЕСТНО, тик за тиком, а
  не существует изолированными, хоть и рабочими по отдельности,
  модулями.

## Milestone 9 начат: Tactical AI (§26) — первая версия

* `tactical_ai.gd` — `TacticalAI`: чистые статические функции выбора
  цели, читающие ТОЛЬКО сенсорные контакты (`SensorContact.state`/
  `estimated_position`), никогда истинную позицию/принадлежность цели
  напрямую — прямая реализация требования §26 "No cheat vision".
  `select_pd_target(ship, contacts)` — ближайший пригодный
  (DETECTED/TRACKED/ESTIMATED) контакт, чья цель — АКТИВНАЯ ракета,
  нацеленная именно на этот корабль. `select_weapon_target(ship,
  contacts, hostile_ship_ids)` — ближайший пригодный контакт среди
  явно переданного списка враждебных id.
* Это одновременно и НОВАЯ функциональность, и ИСПРАВЛЕНИЕ: старый
  плейсхолдер выбора цели для ПРО в `simulation_world.gd` сканировал
  `world.missiles` по ИСТИННОЙ позиции/идентичности — то есть сам
  нарушал "No cheat vision" из §26. Теперь оба (`_resolve_point_defense`
  и новый `_resolve_weapons_ai`) идут через `TacticalAI` и сенсорные
  контакты.
* `simulation_world.gd`: добавлены `teams: Dictionary` (ship_id →
  команда) и `is_hostile()`/`set_team()` — минимальная модель
  вражды (ASSUMPTION: разные НЕПУСТЫЕ команды = враги; отсутствие
  команды = нейтрален, никогда не выбирается целью по умолчанию).
  Новый шаг цикла `_resolve_weapons_ai(dt)` — каждый корабль с оружием
  и назначенной командой сам выбирает ближайшую враждебную цель через
  `TacticalAI` и стреляет из всех готовых, способных довернуть орудий
  (§26 "select targets"/"use weapons"). `fire_weapon()` остаётся и
  доступен для явного вызова сценарием.
* Честно ограничено: это САМЫЙ простой возможный слой AI, который
  проходит пункты §26 "detect contacts"/"evaluate threats"(тривиально —
  ближайший)/"select targets"/"use weapons"/"use point defense". НЕ
  реализовано: взвешивание угроз сложнее "ближайший" (размер залпа,
  время до попадания, ценность корабля), управление формациями,
  маневрирование/выбор дистанции, решения о запуске ракет,
  реакция на повреждения/потерю кораблей, отступление/выход из боя —
  все это остаётся в ASSUMPTIONS.md как открытые пункты §26.
* Тесты: `test_tactical_ai.gd` (8 проверок — игнорирует необнаруженные/
  не-по-этому-кораблю/неактивные ракеты; выбирает ближайший пригодный
  контакт; критически — использует ОЦЕНКУ контакта, а не истинную
  позицию цели, даже когда они специально расходятся; фильтрует оружейные
  цели по списку враждебных id, а не просто по дистанции; ближайший
  среди нескольких враждебных; отсутствие враждебных → null, не
  случайный дефолт) и 2 новых сквозных теста в `test_simulation_world.gd`
  (AI сама стреляет по враждебному кораблю, но не по гораздо более
  близкому нейтральному без команды; корабль без команды вообще не
  стреляет — нет дефолтной вражды). Все зелёные. Полный набор: 19
  файлов тестов, 155+ проверок, все зелёные, регрессий нет.
