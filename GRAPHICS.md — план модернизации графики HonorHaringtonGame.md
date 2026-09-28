# GRAPHICS.md

## Цель

Улучшить графику `HonorHaringtonGame` до уровня реалистичного cinematic hard-SF, сохранив текущий Godot 4.x и существующую архитектуру симуляции.

**Движок пока НЕ менять на Unreal Engine.**

Главная задача — определить и реализовать визуальный pipeline, который позволит получить реалистичный Honorverse:

- реалистичные металлические корпуса;
- детализированные военные космические корабли;
- корректное освещение в космосе;
- масштабные дистанции;
- реалистичный Impeller Wedge;
- качественные missile trails;
- laserhead effects;
- cinematic camera;
- tactical camera;
- strategic camera;
- LOD;
- PBR;
- post-processing;
- повреждения;
- эффект масштабности.

---

# 1. Основной визуальный принцип

Не использовать стилистику:

- Star Wars;
- Star Trek;
- яркого arcade sci-fi;
- пластиковых игрушечных моделей;
- чрезмерно светящихся объектов;
- огромных цветных лазеров;
- чрезмерных engine trails.

Нужен визуальный язык:

> realistic military hard science fiction / cinematic space warfare.

Корабли должны выглядеть как тяжёлая военная техника, а не как фантастические самолёты.

---

# 2. Godot оставить

Текущий Godot-проект не переносить на Unreal Engine на этом этапе.

Godot используется как:

```text
Rendering
Camera
Input
UI
Particles
Shaders
Scene management
```

Simulation остаётся независимой от rendering.

Сохранять принцип:

```text
Simulation
    ↓
Render Adapter
    ↓
Godot Node3D
```

Simulation не должна зависеть от:

```text
Node3D
MeshInstance3D
Camera3D
GPUParticles3D
```

---

# 3. Главная визуальная проблема текущего проекта

Текущие procedural meshes являются техническим прототипом.

Не пытаться решить качество только увеличением количества полигонов.

Нужно создать полноценный visual pipeline:

```text
High quality mesh
        +
PBR material
        +
Normal map
        +
Roughness map
        +
Metallic map
        +
Panel/decal details
        +
Lighting
        +
LOD
        +
Post-processing
```

---

# 4. Материалы кораблей

Создать базовый материал:

```text
ManticoranHullMaterial
```

Он должен использовать PBR.

Основные характеристики:

```text
dark military metal
medium/high metallic
variable roughness
subtle micro scratches
subtle panel variation
small edge wear
low-emission hull
```

Не использовать полностью однородный серый цвет.

Корпус должен иметь небольшие различия:

```text
armor plates
maintenance panels
weapon galleries
structural seams
heat-stressed areas
sensor panels
hatches
access panels
```

Большинство мелких деталей реализовывать через:

```text
normal maps
roughness maps
decals
detail textures
```

а не дополнительной геометрией.

---

# 5. Цветовая палитра

Основной корпус:

```text
dark grey
charcoal grey
cold metallic grey
```

Не делать корпус почти чёрным.

Он должен оставаться читаемым на фоне космоса благодаря отражениям и градиентам освещения.

Emission использовать умеренно.

---

# 6. Освещение

Космическая сцена не должна выглядеть как:

```text
серый корабль
+
равномерная подсветка
+
чёрный фон
```

Нужно добиться:

```text
strong key light
+
deep shadow
+
subtle rim light
+
controlled specular highlights
```

Корабль должен иметь очень тёмную сторону.

Солнечный источник должен создавать выраженный directional light.

Не использовать равномерную ambient illumination.

---

# 7. Space Environment

Создать отдельный environment:

```text
SpaceEnvironment
```

Он должен включать:

- HDR environment;
- stars;
- controlled ambient light;
- subtle background nebula only where appropriate;
- bloom;
- tonemapping;
- optional volumetric effects.

Звёзды не должны выглядеть как густая декоративная текстура.

---

# 8. Post-processing

Проверить и настроить:

```text
HDR
Tonemapping
Bloom/Glow
SSAO/SSIL
SSR where useful
Depth of Field
Color grading
Volumetric Fog where appropriate
```

Не использовать эффекты ради самих эффектов.

Особенно осторожно:

```text
Bloom
Glow
Chromatic aberration
Lens flare
```

Нужен реалистичный cinematic look.

---

# 9. Cinematic camera

Создать три режима камеры.

## Strategic

Масштаб:

```text
millions of km
```

Корабли могут быть представлены simplified meshes или markers.

Показывать:

```text
formations
fleet positions
missile vectors
target vectors
```

## Tactical

Масштаб:

```text
hundreds of thousands → millions of km
```

Показывать:

```text
ships
formations
missiles
wedge
weapon effects
```

## Cinematic

Масштаб:

```text
hundreds → tens of thousands of km
```

Показывать:

```text
detailed hull
weapon galleries
engines
damage
missile launches
laserhead attack
wedge
```

Камера должна плавно переходить между уровнями.

---

# 10. LOD

Обязательно реализовать несколько уровней детализации.

Например:

```text
LOD0
Full detailed ship

LOD1
Reduced geometry

LOD2
Simplified hull

LOD3
Very simplified tactical representation

LOD4
Icon / marker
```

LOD выбирается по:

```text
distance from camera
screen-space size
camera mode
```

Не использовать full-detail mesh для корабля, который находится в миллионах километров.

---

# 11. Manticoran ship design

Для крупных кораблей придерживаться визуального языка Honorverse.

Не добавлять:

```text
wings
fighter-like fins
bridge towers
Star Wars-style superstructure
```

Для Sphinx-class и других кораблей использовать:

```text
elongated cylindrical/spindle hull
military engineering
recessed weapon galleries
minimal external protrusions
dark grey armor
```

Корабль должен восприниматься как огромный военный космический аппарат.

---

# 12. Impeller Wedge

Wedge — один из важнейших визуальных элементов.

Не делать его обычным:

```text
transparent triangle
```

Создать отдельный shader/material:

```text
ImpellerWedgeMaterial
```

Использовать:

```text
Fresnel
subtle emission
controlled transparency
edge highlighting
very subtle distortion
```

Wedge должен быть:

```text
очень тонким
почти незаметным
```

и становиться заметнее только при подходящем угле камеры/освещении.

Не превращать его в яркий sci-fi shield.

---

# 13. Missile visuals

Ракеты должны быть маленькими и очень быстрыми.

Не использовать огромные Star Wars-style plasma trails.

Предпочтительный вид:

```text
MISSILE
    ●────────────
```

Вблизи:

```text
missile body
+
small engine plume
+
hot exhaust
+
subtle particles
+
faint trail
```

Вдали:

```text
small bright point
+
very short trail
```

Использовать GPUParticles3D и shaders там, где это повышает производительность/качество.

---

# 14. Missile launch

При запуске ракеты показать:

```text
launch flash
+
short exhaust
+
acceleration
+
transition to small tactical object
```

Не создавать огромный огненный взрыв при каждом запуске.

---

# 15. Laserhead

Laserhead должен выглядеть не как постоянный Star Wars laser beam.

Эффект:

```text
Missile
    ↓
Laserhead
    ↓
short laser pulse
    ↓
target
    ↓
impact flash
    ↓
damage/debris
```

Beam должен быть очень коротким и интенсивным.

Использовать:

```text
shader
particle burst
light flash
post-processing
```

вместо постоянной светящейся линии.

---

# 16. Point Defense

PD должен быть визуально читаемым, но не превращаться в фейерверк.

При поражении ракеты:

```text
small flash
+
short energy effect
+
missile breakup
```

Если рядом находится дружественный корабль, визуально можно показать работу PD через:

```text
short firing pulses
```

но не создавать постоянные beams.

---

# 17. Engine effects

Основные двигатели должны быть:

```text
bright core
+
subtle glow
+
controlled exhaust effect
```

Не делать:

```text
гигантский огненный хвост
```

поскольку это не атмосферный реактивный двигатель.

---

# 18. Damage system visuals

Создать визуальные состояния:

```text
HEALTHY
DAMAGED
HEAVILY_DAMAGED
CRITICAL
DESTROYED
```

При повреждении использовать:

```text
localized emissive damage
sparks
small debris
darkened armor
heat discoloration
```

Не использовать постоянный огонь вокруг корпуса.

---

# 19. Tactical battle visualization

Тактический бой должен оставаться читаемым.

Основные визуальные элементы:

```text
ships
formations
velocity vectors
missile vectors
target lines
sensor contacts
weapon ranges
```

Но UI не должен превращать экран в набор разноцветных линий.

Использовать визуальную иерархию:

```text
selected unit
    ↓
primary target
    ↓
weapon solution
    ↓
secondary information
```

---

# 20. Sensor contacts

Не показывать истинную позицию неизвестной цели.

Визуально различать:

```text
UNKNOWN
DETECTED
TRACKED
ESTIMATED
LOST
```

Например:

```text
TRACKED
solid marker

ESTIMATED
dashed marker

LOST
fading marker
```

Это должно соответствовать simulation state.

---

# 21. Tactical UI

Основной интерфейс должен быть рассчитан на управление:

```text
Fleet
    ↓
Squadron
    ↓
Formation
    ↓
Ship
```

Пример:

```text
┌───────────────────────────────────────────────────────────────┐
│  1st Squadron             TIME 25x            T+ 00:14:32    │
├───────────────────────────────────────────────────────────────┤
│                                                               │
│              ● ● ● ● ●                                        │
│                                                               │
│                         ╲                                     │
│                          ╲ MISSILE SALVO                      │
│                           ╲                                   │
│                            × × × × ×                          │
│                                                               │
│                    ● ● ● ● ●                                  │
│                                                               │
├───────────────────────────────────────────────────────────────┤
│ SELECTED: 1st Squadron                                       │
│                                                               │
│ [MOVE] [FORMATION] [ENGAGE] [MISSILES] [PD] [SENSORS]        │
└───────────────────────────────────────────────────────────────┘
```

---

# 22. Visual scale

Очень важно не потерять ощущение масштаба.

При tactical zoom:

```text
корабль должен быть маленьким
```

При cinematic zoom:

```text
корабль должен становиться огромным
```

Не использовать постоянный размер корабля на экране.

---

# 23. Performance

Каждый visual feature должен проверяться на:

```text
100 ships
1000 missiles
10000 missiles
```

Не допускать:

```text
one Node3D per particle
one expensive shader per missile
full-detail mesh at all distances
```

Использовать:

```text
GPUParticles
LOD
MultiMesh
instancing
object pooling
```

где это необходимо.

---

# 24. Architecture

Не смешивать rendering и simulation.

Правильно:

```text
Simulation State
       ↓
Render Adapter
       ↓
Visual Representation
```

Неправильно:

```text
Simulation
    ↓
Node3D
    ↓
get_global_position()
```

Simulation должна оставаться тестируемой без запуска renderer.

---

# 25. Порядок реализации

Не пытаться сделать всё одновременно.

## Phase 1 — Lighting

Сначала:

```text
SpaceEnvironment
Directional Light
Tonemapping
Bloom
SSAO/SSIL
```

Создать одну демонстрационную сцену с одним кораблём.

---

## Phase 2 — Hull material

Создать:

```text
ManticoranHullMaterial
```

Добавить:

```text
metallic
roughness
normal
detail
panel variation
```

---

## Phase 3 — Ship model

Создать один качественный демонстрационный корабль.

Не создавать сразу весь флот.

Цель:

> один корабль должен выглядеть убедительно.

---

## Phase 4 — Wedge

Создать:

```text
ImpellerWedgeMaterial
ImpellerWedgeVisual
```

и интегрировать его с текущей simulation state.

---

## Phase 5 — Missile effects

Добавить:

```text
MissileVisual
MissileTrail
MissileLaunchEffect
MissileInterceptEffect
```

---

## Phase 6 — Laserhead

Добавить:

```text
LaserheadFlash
LaserPulse
ImpactEffect
```

---

## Phase 7 — Damage

Добавить:

```text
DamageVisualState
HeatDamage
Debris
Sparks
```

---

## Phase 8 — LOD

Добавить:

```text
LOD0
LOD1
LOD2
LOD3
LOD4
```

---

## Phase 9 — Tactical camera

Реализовать:

```text
Strategic
Tactical
Cinematic
```

---

## Phase 10 — Tactical UI

После того как визуальная сцена выглядит хорошо, обновить UI.

---

# 26. Benchmark scene

Создать отдельную сцену:

```text
graphics_benchmark.tscn
```

В ней:

```text
1 superdreadnought
10 ships
100 missiles
1000 missiles
weapon effects
wedge
damage effects
```

Добавить возможность переключать:

```text
LOW
MEDIUM
HIGH
ULTRA
```

и:

```text
TACTICAL
CINEMATIC
```

---

# 27. Не делать пока

Не переходить на Unreal Engine.

Не переписывать simulation.

Не менять physics только ради graphics.

Не добавлять новые виды оружия ради демонстрации.

Не делать огромные Star Wars-style explosions.

Не использовать чрезмерный bloom.

Не использовать яркие neon colors без необходимости.

---

# 28. Acceptance criteria

Работа считается успешной, если:

### Ship

Один корабль:

- выглядит металлическим;
- имеет читаемые панели;
- имеет believable roughness;
- не выглядит пластиковым;
- имеет реалистичные specular highlights;
- сохраняет читаемость в тени.

### Space

Сцена:

- имеет глубокий чёрный космос;
- имеет реалистичное directional lighting;
- не выглядит плоской;
- сохраняет масштаб.

### Wedge

Wedge:

- виден;
- не выглядит пластиковым;
- не выглядит энергетическим щитом;
- не перекрывает корабль;
- реагирует на положение камеры.

### Missiles

Ракеты:

- визуально читаются;
- не имеют гигантских trails;
- сохраняют производительность.

### Combat

Missile interception:

```text
launch
→ flight
→ intercept
→ flash
→ debris
```

выглядит как единый визуальный процесс.

### Camera

Можно переключаться:

```text
Strategic
Tactical
Cinematic
```

без нарушения simulation.

---

# 29. Главное правило

Не пытаться сделать графику «дорогой» количеством эффектов.

Нужны:

```text
good models
+
good materials
+
good lighting
+
good scale
+
good camera
+
restrained effects
```

Это важнее количества particle effects.

---

# 30. Первый практический шаг для Claude

Перед внесением изменений:

1. Просмотреть весь существующий rendering code.
2. Найти все `MeshInstance3D`.
3. Найти все материалы.
4. Найти все lights.
5. Найти `WorldEnvironment`.
6. Найти particles.
7. Найти camera.
8. Найти procedural ship generation.
9. Найти текущий wedge renderer.
10. Найти missile renderer.
11. Найти damage visuals.
12. Найти LOD/visibility logic.

Затем создать:

```text
GRAPHICS_AUDIT.md
```

с таблицей:

```text
System | Current implementation | Problem | Proposed solution | Files
```

**Не переписывать проект до завершения аудита.**

После аудита реализовать Phase 1–3 и показать результат на одной benchmark-сцене.

Только после проверки benchmark переходить к missile effects, wedge, damage и tactical presentation.