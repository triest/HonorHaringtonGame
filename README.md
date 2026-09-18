# Honorverse 3D Tactical Combat Simulator

Автономный (без Claude/LLM/интернета в рантайме) Windows 3D тактический
симулятор космических боёв во вселенной Honor Harrington. ТЗ: `AGENTS.md`
(60 разделов) + дополнение `CLOUDE.md` (impeller wedge, кинематика).

## Статус

Milestone 1 (engine skeleton + 3D world + simulation loop) — в разработке.
См. `CHANGELOG.md` за текущий прогресс, `ASSUMPTIONS.md` за все
инженерные допущения, не подтверждённые каноном.

## Стек (ASSUMPTION, см. ASSUMPTIONS.md)

Godot 4.3 (GDScript), экспорт в standalone Windows .exe.

## Структура

```
project/            — Godot-проект (открывать в Godot 4.3+)
  simulation/        — симуляционное ядро (без зависимости от рендера/UI)
  scripts/           — рендер-слой (читает simulation state, не решает правила)
  scenes/            — .tscn сцены
(ARCHITECTURE.md, CANON_RULES.md, ASSUMPTIONS.md, BUILD.md, CHANGELOG.md, CLOUD.md — в корне репозитория, по структуре §5 ТЗ)
```

## Сборка / запуск

См. `BUILD.md`.
