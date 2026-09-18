# CANON_RULES.md - Honorverse Tactical Specifications

## 1. IMPELLER WEDGE GEOMETRY & MECHANICS [CANON]
* **Top/Bottom Impenetrability:** The top and bottom hyper-spatial stress bands (the Impeller Wedge) create an absolute gravitational barrier. No physical entity or energy weapon can penetrate the wedge. Any object entering the wedge is instantaneously destroyed by tidal gravitational forces.
* **Vulnerable Throats:** The front (bow) and rear (stern) openings of the wedge are completely unprotected by the wedge itself. These are the critical vectors for axial energy weapons (chaser armaments) and missile ingress.
* **Krennikov Coupler Limits:** Ships cannot engage hyper-drive or maintain normal sub-light acceleration if the impeller wedge bands overlap or suffer harmonic failure. 

## 2. SIDEWALLS [CANON]
* **Spatial Distortion Shields:** Sidewalls are artificial gravitational shear zones projected along the port and starboard beams. They do not block attacks through raw capacity (HP Pools), but distort and refract incoming energy beams and missile laserheads.
* **Overloading & Burnout:** A sidewall can be overloaded by concentrated energy weapon strikes or high-yield laserhead detonations. An overloaded sidewall generator burns out, leaving the underlying hull section entirely exposed to subsequent salvos.

## 3. MISSILE & LASERHEAD WEAPONS [CANON]
* **Offensive Profiles:** Missiles accelerate at thousands of gravities ($G$), rapidly entering high relativistic fractions of $c$ (up to $0.7c$ or higher depending on the technological era).
* **Laserhead Functionality:** Missiles do not detonate upon physical contact. At the terminal phase, they detonate at distances of thousands of kilometers, pumping their nuclear fusion energy into focused X-ray lasing rods (Laserheads) directed at the target's vulnerable vectors.

## 4. COUNTER-MISSILES & POINT DEFENSE [CANON]
* **Counter-Missiles (CM):** Active interceptors launched to detonate near incoming missiles, using spatial distortions to break their tracking or destroy them prematurely.
* **Laser Clusters & Point Defense:** Active close-in laser mounts that track and destroy incoming missiles that penetrate the outer CM screens.

## 5. SENSORS & ECM [CANON]
* **Gravitic Sensors:** Detection relies primarily on gravitic sensors that read the immense spatial distortions of an active impeller wedge. A ship with an active wedge cannot hide its presence within normal system ranges.
* **Electronic Countermeasures (ECM):** Systems like "Ghost Rider" project multiple false gravitic signatures, distorting the target tracking systems of missiles and enemy ships.

## 6. SUBSYSTEM DAMAGE [CANON]
* **Component Degradation:** Damage directly incapacitates specific nodes: impeller rings (degrading max acceleration), sidewall generators (reducing shield coverage), missile tubes (dropping salvo density), and control rooms (introducing telemetry lag).

## 7. FORMATIONS & COMMAND HIERARCHY [CANON]
* **Tactical Layout:** Ships fly in strict vertical wall-of-battle formations to interlock their sidewalls and protect each other's open throats. 
* **Command Lag:** Orders are bound by the speed of light ($c$). In grand fleet actions across millions of kilometers, changes in formation doctrine or target priority take real simulation time to propagate down the command chain.

---

## Проверка чисел (сверка с Honorverse Wiki, 2026-09-18)

* **Ускорение ракет:** в CANON выше указано "thousands of gravities" —
  это верно по порядку величины, но не точно. Конкретный пример из книг:
  ракета калибра капитал-шипа поздних технологий (Peep Wars-эры)
  "could accelerate at 46,000 G for perhaps 180 seconds before its drive
  burned out" (Honorverse Wiki, статья Missile). ЗНАЧЕНИЕ ЗАВИСИТ ОТ
  ЭПОХИ/КЛАССА РАКЕТЫ — нельзя брать 46,000G как универсальную константу
  для всех ракет всех эпох; статус для конкретных цифр — CANON только для
  цитируемого примера, для остальных эпох — UNKNOWN, делать configurable.
* **Дистанция поражения laserhead:** в CANON выше "thousands of kilometers"
  — по источнику точнее: боеголовка детонирует, разводящие штанги (lasing
  rods) выдвигаются на ~100 метров перед боеголовкой, "meaningful damage
  could be dealt to anything within 25,000 kilometers of the detonation".
  Уточнить как CANON (пример) с явной пометкой "конкретное число варьируется
  по классу боеголовки/эпохе — UNKNOWN для точного значения по умолчанию".
* Источник: https://honorverse.fandom.com/wiki/Missile (фан-вики —
  приоритет 4 по AGENTS.md §4, использовать как вспомогательный источник,
  не как замену первоисточнику книг; при расхождении с текстом книг —
  книги приоритетнее).

TODO: остальные пункты этого файла (Krennikov Coupler, ECM "Ghost Rider",
overloading механика sidewall) пока НЕ сверены с первоисточником — не
считать окончательным каноном, пока не перепроверено по тексту книг или
более надёжному справочнику.

---

## Вторая сверка (Honorverse Wiki, 2026-09-18) — оставшиеся пункты

* **Wedge: непробиваемость сверху/снизу + уничтожение объектов внутри клина.**
  Статус: CONFIRMED CANON (Honorverse Wiki, статья Missile: "impenetrable
  wedges above and below the ship"). Оставить как есть.

* **Уязвимые throats (нос/корма).** CONFIRMED CANON, согласуется с общей
  механикой клина по всем найденным источникам. Оставить как есть.

* **"Krennikov Coupler" (ограничение работы гипер-двигателя/impeller при
  перекрытии полос клина).** НЕ НАЙДЕНО ни в одном источнике (Honorverse
  Wiki "Impeller drive", целевой поиск по термину "Krennikov" — ноль
  релевантных совпадений). Статус понижен с CANON до **UNKNOWN /
  вероятно придуманный термин** — не использовать как канон без прямой
  цитаты из книги. Если механика "нельзя одновременно держать hyper-drive
  и impeller / клинья не должны пересекаться" нужна геймплейно — это
  ASSUMPTION/INTERPRETATION, а не CANON, пока не найдена цитата.

* **Sidewalls — общий механизм (искажение/ослабление луча, не HP-пул).**
  CONFIRMED CANON (Honorverse Wiki, статья Sidewall: "barrier of gravitic
  distortion... attenuating any energy attack"; явно указано, что sidewall
  "incapable of making a ship invulnerable").

* **Sidewalls — overload/burnout генератора.** НЕ ПОДТВЕРЖДЕНО — во
  фрагменте статьи Sidewall нет упоминания overload/burnout. Статус:
  CANON → **понижен до INTERPRETATION**, пока не найдена прямая цитата.
  Механику можно оставить как игровой дизайн, но помечать как
  INTERPRETATION, не CANON.

* **Новые канонические детали (были упущены в исходной версии файла),
  добавить в реализацию:**
  - Поднятый носовой/кормовой sidewall блокирует использование impeller
    для ускорения, пока стенка активна (компромисс скорость vs защита
    носа/кормы). CONFIRMED CANON (Honorverse Wiki, Sidewall).
  - Двухступенчатая носовая стенка ("two-stage bow wall"): первая ступень
    уязвима к лучам под острым углом атаки, а также ракеты могут
    "проскользнуть" мимо неё до детонации, т.к. эта стенка представляет
    собой круг диаметром лишь вдвое больше макс. ширины корпуса. CONFIRMED
    CANON, источник тот же. Это существенная деталь для §10 (направление
    атаки) — стоит учесть в геометрии носовой защиты отдельно от
    бортовых sidewalls.

* **Ghost Rider (ECM).** Существование и общее назначение (программа РЭБ
  Royal Manticoran Navy, изначально для капитал-шипов, расширена на
  Shrike/Ferret-класс лёгких кораблей, дала линейку "продвинутых
  ракет/дронов") — CONFIRMED CANON (Honorverse Wiki, статья Ghost Rider).
  Конкретный механизм "проецирует множественные ложные гравитационные
  сигнатуры" — НЕ подтверждён в найденном фрагменте, статус: понижен
  CANON → **INTERPRETATION** до отдельной проверки.

* **Gravitic sensors (детектирование клина, нельзя скрыть активный
  клин).** НЕ УДАЛОСЬ ПРОВЕРИТЬ — страница Honorverse Wiki "Gravitic
  sensor" не отдавалась (402 ошибка при обоих запросах). Статус остаётся
  **INTERPRETATION** (правдоподобно по духу сеттинга, но не подтверждено
  цитатой в этой сессии) — перепроверить отдельно, когда будет
  реализовываться Milestone сенсоров.

* **Wall-of-battle формация / command lag со скоростью света.** Общая идея
  ("wall of battle" — устойчивый канонический термин серии) правдоподобна,
  но в этой сессии не подтверждена прямой цитатой. Статус: **INTERPRETATION**,
  перепроверить при реализации Milestone формаций/AI.

Источники второй сверки:
- https://honorverse.fandom.com/wiki/Impeller_drive (поиск термина Krennikov)
- https://honorverse.fandom.com/wiki/Ghost_Rider
- https://honorverse.fandom.com/wiki/Sidewall
- https://honorverse.fandom.com/wiki/Missile (повторно, для wedge)

Итог: из 7 пунктов, требовавших проверки — 4 подтверждены как CANON (wedge
top/bottom, throats, sidewall общий механизм, sidewall блокирует ускорение
+ двухступенчатая носовая стенка, Ghost Rider как программа), 1 понижен
до UNKNOWN (Krennikov Coupler — вероятно вымышленный термин, не найден
ни в одном источнике), 2 понижены до INTERPRETATION (sidewall overload/
burnout, детальный механизм Ghost Rider), 2 остались непроверенными
(gravitic sensor range, wall-of-battle/command lag) — перепроверить при
реализации соответствующих Milestone.

---

## Третья сверка (Honorverse Wiki, 2026-09-18) — механика laserhead по запросу пользователя

По просьбе пользователя доработаны AGENTS.md §21 и CLOUD.md §2.2 —
подробная последовательность подрыва laserhead, подтверждено CANON:

* Штанги (lasing rods) физически ОТДЕЛЯЮТСЯ от корпуса ракеты при выходе
  на финальный боевой курс, у каждой свои двигатели и сенсоры, наводятся
  независимо, занимают позицию ~100м перед боеголовкой.
* Кольцо гравитационных генераторов за боеголовкой фокусирует взрыв в
  гауссов импульс, направленный на штанги — это и есть механизм "накачки"
  рентгеновского лазера.
* Количество и тип штанг — характеристика конкретного класса боеголовки,
  не универсальная константа: Mark 23 (капитал-ракета) = 6 штанг 500х40см
  по одной цели; Mark 13 (суббоеприпас) = 6 независимо наводимых
  суббоеприпасов Mark 73, каждый может бить по своей точке/цели.
* Реальные примеры характеристик ракет (тоже НЕ универсальные константы):
  Mark 23 MDM ~48 000G / ~63 млн км дальности на половинном ускорении;
  Mark 31 контрракета ~130 000G / 75с / ~3.6 млн км; Viper — fire-and-forget
  с бортовым ИИ, без телеметрии с корабля; Apollo — control missile с
  FTL-телеметрией координирует залп из 8 обычных MDM в реальном времени.

Источники: https://honorverse.fandom.com/wiki/Missile,
https://honorverse.fandom.com/wiki/Manticoran_missile_technology

Статус относительно текущей реализации (`missile_resolution.gd`,
`missile_state.gd`): реализация пока НЕ обновлена под эту детальную
механику (одна направленная атака из позиции ракеты вместо честного
разведения штанг ~100м с независимым наведением) — явно
INTERPRETATION-упрощение, см. ASSUMPTIONS.md. Обновление реализации —
следующий по очереди проход разработки, не сделано в этом проходе (проход
был про доработку ТЗ по прямому запросу пользователя, не про код).

---

## Четвёртая сверка (Honorverse Wiki, статья Missile, 2026-09-18) — физика полёта и поражающие факторы, по запросу пользователя

* **Трёхфазная модель полёта ракеты** (powered flight → throttled/
  stepped-down → ballistic coast) — CONFIRMED CANON. Пример: 46 000G/180с
  даёт powered range "over six million kilometers"; проверка по формуле
  0.5*a*t² даёт ~7.3 млн км — согласуется с цитатой (сама формула не
  канон, это инженерная проверка правдоподобия числа).
* **Дросселирование двигателя** (снижение ускорения ради увеличения
  времени горения/дальности, ценой большего времени на реакцию цели) —
  CONFIRMED CANON.
* **Баллистическая фаза после выгорания — ракету легко избежать** —
  CONFIRMED CANON, уже реализовано в коде (missile coasts, no course
  correction after burnout).
* **Многоступенчатые MDM** (независимые ступени двигателя, отстрел
  последовательно или с «дрейфом» между ступенями) — CONFIRMED CANON.
  Мантикорские конструкции — до 3 ступеней, хевенитские — до 2 (из-за
  габаритов конденсаторного кольца). НЕ РЕАЛИЗОВАНО в коде (текущая
  модель — одна ступень/один burn timer).
* **Вращение ракеты в полёте** для затруднения работы point defense
  (тот же принцип защиты клином сверху/снизу, что у кораблей, в масштабе
  ракеты) — CONFIRMED CANON. Не реализовано визуально/геометрически
  (ориентация ракеты сейчас жёстко следует за вектором скорости, без
  вращения вокруг этой оси).
* **Ракета должна выйти за пределы клина своего корабля-носителя перед
  активацией собственного клина/двигателя — отсюда пусковые трубы/
  mass driver** — CONFIRMED CANON. Не реализовано (нет модели пусковой
  трубы/старта).
* **Незащищённые ракеты в подвесных pod ("проксимити-килл")** —
  CONFIRMED CANON, релевантно для будущей модели повреждения контейнеров
  боезапаса. Не реализовано.
* **Laserhead эффективнее против sidewalls, чем чистый термоядерный
  заряд** — CONFIRMED CANON. ВАЖНО для поражающих факторов: означает,
  что тип боеголовки должен влиять на коэффициент ослабления sidewall, а
  не только состояние (condition) самого sidewall. ТЕКУЩАЯ РЕАЛИЗАЦИЯ
  (`ship_defense_state.gd`) НЕ учитывает тип атакующего оружия — одна
  формула ослабления для всех. Задокументированный пробел, не молчаливая
  неточность.

Источник: https://honorverse.fandom.com/wiki/Missile (два целевых fetch
в этом проходе, по физике полёта отдельно и по поражающим факторам
отдельно).

---

## Пятая сверка — форма корпуса корабля (для процедурной 3D-модели, по запросу пользователя)

* **"Flattened spindle" (сплющенное веретено)** — CONFIRMED CANON: корпус
  сужается на носу/корме (там расположены impeller-узлы, создающие клин),
  расширяется в средней части (вооружение/экипаж).
* **"Hammerhead"** — военные корабли имеют характерные расширения-наросты
  на носовой/кормовой оконечностях (в отличие от гражданских судов, у
  которых их нет) — CONFIRMED CANON. Там же концентрируются chase-оружие,
  point defense и чувствительные сенсорные решётки (нос/корма не защищены
  клином — см. §9/§10).
* **Размещение вооружения**: главный калибр — по бортам (под защитой
  sidewalls), нос/корма — chase-оружие и point defense (там же, где
  hammerhead). Согласуется с уже реализованной геометрией атаки
  (`attack_geometry.gd`).
* Форма подразумевает сплющенность (шире, чем выше) — согласуется с тем,
  что клин защищает именно сверху/снизу (§9), то есть высота — самое
  уязвимое измерение по площади, которое имеет смысл минимизировать.

Источник: https://en-academic.com/dic.nsf/enwiki/2910958 (зеркало
Wikipedia-контента Honorverse Wiki, сама Honorverse Wiki отдала 402 при
прямом запросе).

Статус: используется как основа для процедурной 3D-заглушки корпуса
(`hull_mesh_builder.gd`), НЕ для копирования конкретного фан-артового
силуэта (§7: fan art не является источником для геометрии).

---

## Шестая сверка — Point Defense (перед реализацией §22)

* **PD — часть многослойной обороны** ("thickened the defensive envelope"
  совместно с контрракетами и ECM, интеграция с платформами Keyhole) —
  CONFIRMED CANON (Honorverse Wiki, Space Weapons Technology). Реализация
  должна отражать это как один из нескольких защитных слоёв, не
  единственное решение — согласуется с уже реализованными контрракетами
  (Milestone 6a) как отдельным, параллельным слоем защиты.
* Дистанция вовлечения, число необходимых попаданий, время реакции —
  НЕ НАЙДЕНЫ в источниках. Все числа в реализации — ASSUMPTION placeholder.
* Keyhole platforms (упомянуты как расширяющие защитный периметр) — НЕ
  реализовано, отдельная фича вне текущего охвата.

Источник: https://honorverse.fandom.com/wiki/Space_Weapons_Technology

---

## Седьмая сверка — Sensors/ECM, ПЕРВОИСТОЧНИК (On Basilisk Station, глава 3, до этого не проверялось)

Впервые в этой сессии удалось прочитать текст САМОЙ КНИГИ (через
зеркало chapters на stuff.mit.edu), а не только вики — по приоритету
источников (AGENTS.md §4) это выше вики.

* **Корабль МОЖЕТ спрятаться от пассивных сенсоров, заглушив импеллер**
  ("shutting down her impellers and dropping off the enemy's passive
  scanners") — CONFIRMED CANON, ПЕРВОИСТОЧНИК. ЭТО ОТМЕНЯЕТ мою более
  раннюю запись (третья сверка, INTERPRETATION-статус "нельзя скрыть
  активный клин") — та запись была основана на предположении по духу
  сеттинга без цитаты и была явно помечена как неподтверждённая; теперь
  заменяется прямо противоположным подтверждённым фактом. Тактическое
  ограничение — разгон с нуля требует времени (ускорение не мгновенно,
  §12), то есть "невидимость" ценой манёвренности.
* **Двойная полоса клина + sidewall между ними мешает точному считыванию**
  ("Hostile sensors might be able to analyze the outermost band, but they
  couldn't get accurate readings on the inner ones") — CONFIRMED CANON,
  ПЕРВОИСТОЧНИК. Означает: даже обнаружив клин противника, наблюдатель
  не получает автоматически точные характеристики корабля — согласуется
  с состояниями UNCERTAIN/ESTIMATED в §23.
* **Электронные "досье" на суда противника** ("each side had complete
  files on the electronic signatures of the other side's units") —
  CONFIRMED CANON: конкретные известные корабли (например флагманы)
  могут быть опознаны по уникальной сигнатуре — IFF/распознавание по
  базе данных, не мгновенное "всеведение".
* **Ракеты при пуске дают отчётливый, легко обнаруживаемый след**
  ("missile traces streaking towards...") — CONFIRMED CANON.

Источник: https://stuff.mit.edu/afs/sipb/user/jhawk/baen/www.baen.com/chapters/basilisk_3.htm
(легальное зеркало текста книги "On Basilisk Station", David Weber —
издатель Baen ранее сам распространял ознакомительные главы бесплатно).

## Восьмая сверка — ECM/РЭБ (§24), Honorverse Wiki "Electronic warfare"

Источник: https://honorverse.fandom.com/wiki/Electronic_warfare (вторичный
источник — вики, НЕ книжный первоисточник; попытка проверить по книге не
делалась в этот проход, честно помечено как разрыв в верификации).

Подтверждено вики (цитаты):
* Корабли несут "a complex suite of electronic warfare systems" с тремя
  элементами: (1) глушилки и ложные цели "used to defeat or confuse
  incoming missiles"; (2) стелс-возможности, скрывающие излучение
  корабля; (3) мощные бортовые вычислительные комплексы + эмиттеры,
  позволяющие "confuse incoming fire".
* Ложные цели (decoy drones) развёртываются СНАРУЖИ корабля, но
  требования по питанию у них настолько высокие, что собственного
  питания не хватает — они держатся рядом на тракторном луче и
  получают питание по лучу, из-за чего одновременно развернуть можно
  "only a handful of them at a time" (ограниченный ресурс, не
  бесконечный расходник).
* Keyhole — "an advanced ECM system", применяется на уровне эскадры.

Инженерная реализация (`ecm_state.gd`, `sensor_resolution.gd`):
глушение моделируется как СОКРАЩЕНИЕ эффективной дальности обнаружения
наблюдателя против цели (не плоский -20% к шансу попадания — ТЗ §24
прямо запрещает такой шорткат без обоснования более глубокой моделью);
ложные цели моделируются как альтернативный "возврат" сенсора —
наблюдатель захватывает БЛИЖАЙШИЙ к себе возврат (истинная цель или
одна из decoy), детерминированно, без RNG (ТЗ §43 запрещает
unseeded-рандом). Оба механизма — ASSUMPTION/INTERPRETATION поверх
подтверждённого вики-источника, конкретные числа (множитель дальности
0.4, максимум decoy = 4) не из канона, см. ASSUMPTIONS.md.

Честно НЕ проверено: точный масштаб эффекта РЭБ (насколько именно
"confuse incoming fire" снижает эффективность — не количественно, а
качественно); есть ли у РЭБ отдельный физический принцип (не гравика,
а радар/лазер-наведение); первоисточник (книжный текст) для этого
раздела не найден в этот проход.

## Девятая сверка — сверка с Honorverse_Docs.zip (конденсированные заметки от Grok)

Пользователь передал `Honorverse_Docs.zip` с более короткими черновиками
CLOUD.md/BUILD.md/README.md/ARCHITECTURE.md/ASSUMPTIONS.md/CANON_RULES.md/
CHANGELOG.md (судя по размеру — ранние наброски, а не замена накопленных
рабочих логов; AGENTS.md в zip оказался БАЙТ-В-БАЙТ идентичен текущему,
так что реального конфликта по основному ТЗ нет). Из содержимого извлечено
и проверено следующее:

1. **Подтверждено (Honorverse Wiki "Manticoran missile technology",
   verified 2026-09-18):** Mark 23 MDM имеет режим ПОЛНОГО ускорения
   ~96 000 g / дальность ~15 000 000 км, отдельно от уже задокументированного
   режима половинного ускорения ~48 000 g / ~63 000 000 км. Добавлено в
   CLOUD.md §2.2. Тот же trade-off (быстрее/короче vs медленнее/дальше)
   уже реализован механизмом `MissileState.set_throttle()`.
2. **Найдена и исправлена ошибка в ДОКУМЕНТАЦИИ (не в коде):**
   несколько комментариев (ASSUMPTIONS.md, `sensor_resolution.gd`)
   ошибочно называли дефолт `terminal_detonation_range_m` "50 000 км"
   вместо правильных "50 км" (= 50 000 м — сам код был верным, ошибка
   только в 1000x в прозе комментариев). Черновик из zip случайно указал
   правильное значение ("temporary assumption 50 km"), что и вскрыло
   несоответствие. Исправлено в обоих местах.
3. Остальное содержимое zip (Wedge/Sidewalls, Laserheads, Sensors/ECM,
   Subsystem Damage, Command Model, Simulation Requirements) — уже
   покрыто существующими AGENTS.md/CLOUD.md/ARCHITECTURE.md, местами в
   БОЛЬШЕЙ детализации, чем в конденсированном черновике; ничего
   противоречащего не найдено. Добавлены только два новых явных
   подраздела CLOUD.md §2.2.2 (Counter-Missiles) и §2.2.3 (Point
   Defense) — раньше эти механики были только в AGENTS.md/коде, без
   отдельного конденсированного пункта в CLOUD.md.
4. Более короткие ARCHITECTURE.md/ASSUMPTIONS.md/CANON_RULES.md/
   CHANGELOG.md из zip НЕ используются для замены — они значительно
   короче текущих (это подтверждает, что это ранние черновики/шаблоны,
   а не обновлённая версия), и замена уничтожила бы накопленную историю
   решений этой сессии. Пользователь распаковал `Honorverse_Docs.zip` в
   подпапку `Honorverse_Docs/` для ручного сравнения; после того как всё
   полезное было перенесено в канонические файлы (см. выше), и сама
   распакованная подпапка, и `Honorverse_Docs.zip` были удалены из папки
   проекта — они не часть исходников и не нужны как отдельный референс.

## Десятая сверка — обновление ТЗ из Honorverse_Docs.zip (второй заход): AGENTS.md §61 "Combat Philosophy"

Пользователь передал второй `Honorverse_Docs.zip` с примечаниями по боям.
Сравнение с текущими файлами (AGENTS.md/ARCHITECTURE.md/ASSUMPTIONS.md/
BUILD.md/CANON_RULES.md/CHANGELOG.md/CLOUD.md/README.md) через `diff`:

1. Новое, реально отличающееся содержимое — ТОЛЬКО одна новая секция в
   AGENTS.md: **§61 "Combat Philosophy — 'Nelson in a Skirt'"** (полный
   текст перенесён в AGENTS.md как есть, английский оригинал). Это
   ФОРМАЛИЗАЦИЯ дизайн-ориентира, который пользователь уже сообщал ранее
   в этой сессии открытым текстом ("Харингтон — Нельсон в юбке... бои на
   основе эскадренных боёв 18-19 века") и который был записан как
   ASSUMPTION-заметка в ASSUMPTIONS.md/ARCHITECTURE.md ДО получения
   этого архива. Теперь это часть самого ТЗ (AGENTS.md), не просто
   пожелание в диалоге — статус повышен с "заметка пользователя" до
   "раздел ТЗ".
2. Добавлен краткий кросс-референс в CLOUD.md §2.7 (конденсированная
   версия §61 + практическое указание, как применять её к открытым
   пробелам §26/Milestone 10).
3. Более короткие ARCHITECTURE.md/ASSUMPTIONS.md/BUILD.md/CANON_RULES.md/
   CHANGELOG.md/README.md из этого второго zip НЕ содержат другого нового
   содержимого сверх §61/CLOUD.md-кросс-референса (проверено diff'ом
   построчно) — они остаются черновиками-конденсатами, не заменяют
   накопленные версии.
4. Распакованная папка `Honorverse_Docs/` и сам `Honorverse_Docs.zip`
   удалены из папки проекта после переноса §61 в AGENTS.md — как и в
   прошлый раз, это не часть исходников.

Статус: §61 теперь ЧАСТЬ ТЗ проекта (AGENTS.md), не отдельная
несформализованная заметка. Дальнейшая работа над Milestone 9 (остаток
§26 — управление построением, деконфликт целей ракет, реакция на потерю
кораблей отряда) и Milestone 10 (Formation Command) должна явно
опираться на §61 при принятии дизайн-решений, где канон/ТЗ молчат в
остальном, и явно это помечать (design-mandate §61, не канон построчно
из книг).

## Одиннадцатая сверка — Инерция, масса корпуса, компенсатор, масштаб времени (§62)

По запросу пользователя ("Дополни ТЗ про инерцию и масштаб времени, с
учётом масс кораблей и их ускорений по книгам") проверены источники
(WebSearch/WebFetch, 2026-09-18) и добавлена новая AGENTS.md §62:

1. **Масса корпуса по классам** (Honorverse Wiki "Ship Types"):
   Destroyer ~65-80 тыс. тонн, Light Cruiser ~90-150 тыс., Heavy Cruiser
   ~160-350 тыс., Battlecruiser ~780 тыс.-2.5 млн, Battleship ~2-4 млн,
   Superdreadnought ~7-9 млн тонн. CANON, источник процитирован в §62.1.
2. **Инерциальный компенсатор** (Honorverse Wiki "Inertial compensator"):
   гравитационные генераторы САМИ ПО СЕБЕ (без клина) дают до ~50G
   (потолок ускорения корабля ~51G в этом режиме); без клина
   компенсация резко хуже — пример "150G сводится к ощущаемым 5G";
   довоенная доктрина — не более 80% от максимальной эффективности
   компенсатора как запас безопасности; обе стороны отказались от этого
   консервативного запаса во время Первой Манти-Хевенской войны в
   пользу более агрессивных профилей ускорения (ЭТО — доктринальный
   выбор, не константа); отказ компенсатора при значительном ускорении
   = мгновенная смерть экипажа. Всё CANON, источник процитирован в
   §62.2.
3. **Ускорения курьерских катеров/dispatch boats до ~800G** (Honorverse
   Wiki "Ship Types") — CANON, объясняет разброс ускорений через массу/
   нагрузку корпуса (§62.1/§62.3). Конкретных канонических цифр G для
   классов destroyer..superdreadnought в этом заходе НЕ найдено —
   явно помечено как UNKNOWN в §62.3, а не выдумано.
4. **Масштаб времени** (§62.4) — разграничены: фиксированный тик
   симуляции (60Hz, инженерный выбор, не канон) и презентационный
   множитель скорости просмотра (§44, уже существовал, здесь явно
   подтверждено "не меняет физику"); явно зафиксирована граница объёма
   проекта — только тактическое реальное время боя, НЕ компрессия
   времени межзвёздных гипер-переходов (дни/недели) — это отдельная,
   пока не начатая (UNKNOWN) задача, если вообще понадобится.

**Честно зафиксированный текущий разрыв реализации** (не новая работа
в этом заходе, просто задокументированный факт): `ShipPhysicsState.mass_kg`
существует как поле, но `effective_max_acceleration()`/`integrate()`
НЕ используют его для вычисления ускорения через F=ma — ускорение
задаётся напрямую через `max_acceleration_mps2` на корабль, а не
выводится из массы и тяги. Это означает, что требование §62.1 ("масса
должна реально влиять на достижимое ускорение") ПОКА не реализовано в
физике, только продекларировано в ТЗ. См. соответствующую запись в
ASSUMPTIONS.md — открытый пункт для будущего прохода (вероятно,
Milestone 8/дальнейшая доработка Ship Database, §8/§48).


---

## Двенадцатая сверка — Wall of Battle / Command Lag (§33 Formation Leader, по запросу перепроверки из "Второй сверки")

Перепроверка отложенного пункта ("Wall-of-battle формация / command lag
со скоростью света" — ранее статус INTERPRETATION, см. "Вторая сверка"
выше, с пометкой "перепроверить при реализации Milestone формаций/AI",
что и происходит в этом Milestone-проходе).

* **Wall of Battle — CONFIRMED CANON.** Wikipedia-контент-зеркало
  (en-academic.com, отражающее статью "Spacecraft in the Honorverse")
  прямой цитатой: "The most common fleet battle formation is the 'wall
  of battle' in which the vulnerable bow and stern of the ships present
  are perpendicular to the enemy's weapons." Подтверждает уже
  реализованную мотивацию (§61, ARCHITECTURE.md) — строй существует,
  чтобы прикрыть уязвимые нос/корму бортовыми sidewall'ами, подставив
  врагу защищённые борта. Статус повышен: INTERPRETATION → **CONFIRMED
  CANON**.
* **Command Lag (скорость-света задержка команд) — статус НЕ изменён,
  остаётся INTERPRETATION.** Прямая cURL/WebFetch-проверка
  honorverse.fandom.com (основной источник CANON_RULES.md для этой темы)
  вернула HTTP 402 в этой сессии на нескольких релевантных страницах
  (та же проблема, что и в "Вторая сверка" для gravitic sensor) —
  недоступно для перепроверки этим способом сейчас. Веб-поиск нашёл
  косвенно релевантный канонический термин **COLAC** (Combined Local
  Attack Coordination — координация огня по цели между кораблями
  эскадры в бою) как реальную механику Honorverse, но НЕ удалось
  получить содержимое его wiki-страницы (тот же HTTP 402) для проверки,
  упоминает ли она явно задержку по скорости света. Пункт 7 верхнего
  списка CANON_RULES.md ("Command Lag: Orders are bound by the speed of
  light") остаётся НЕ подтверждён прямой цитатой ни в этой, ни в
  предыдущей сверке — статус явно понижается с ошибочного [CANON] тега
  секции (унаследованного от общего заголовка "7. FORMATIONS & COMMAND
  HIERARCHY [CANON]", который относится к секции целиком, а не к каждому
  отдельному пункту) до **INTERPRETATION**: правдоподобно (реальный
  термин "light-speed lag" используется в жанре и, по косвенным
  признакам поиска, в самой серии), но без прямой цитаты источника в
  руках. НЕ ИСПОЛЬЗОВАТЬ как обоснование для точной цифры задержки —
  см. ASSUMPTIONS.md: `COMMAND_TRANSFER_DELAY_S` в реализации §33 —
  ЯВНО инженерная константа (процедура распознавания потери командира
  экипажем), НЕ модель задержки по скорости света, чтобы не путать эти
  два разных, но тематически смежных понятия.

Источники:
- https://en-academic.com/dic.nsf/enwiki/2910958 (зеркало "Spacecraft in
  the Honorverse", прямая цитата про wall of battle получена)
- https://honorverse.fandom.com/wiki/COLAC (существование страницы
  подтверждено поиском, содержимое НЕ получено — HTTP 402)
- https://honorverse.fandom.com/wiki/Honorverse:Wikipedia_content/Spacecraft_in_the_Honorverse
  (то же зеркало на fandom, НЕ получено напрямую — HTTP 402, использован
  en-academic.com зеркало вместо этого)
