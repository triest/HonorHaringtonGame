# BUILD.md

## Требования

* Godot Engine 4.3 (stable), редактор или headless-бинарь.
  https://godotengine.org/download

## Запуск в редакторе

1. Открыть Godot 4.3.
2. Import Project → выбрать `project/project.godot`.
3. Run (F5) — запускает `scenes/main.tscn`.

## Headless self-test симуляционного ядра

```
godot4 --headless --script res://simulation/tests/test_ship_physics_state.gd
```
(запускать из каталога `project/`). Печатает `ALL TESTS PASSED` и завершается
с кодом 0 при успехе, иначе печатает `N TEST(S) FAILED` и код возврата > 0.

Проверено в этой сессии: Godot v4.3-stable_linux.x86_64, exit code 0.

## Экспорт в Windows .exe

Экспорт ещё не настроен (нет export preset в project.godot) — будет добавлен
после Milestone 1. Требует Godot export templates для Windows (устанавливаются
из редактора, не требуют интернета в рантайме готового .exe).
