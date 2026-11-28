# Half-Life: Abaddon · синхронизация Agent 2

23 ноября 2026 г.

| Вход | Коммит |
|---|---|
| Актуальный `main` с Granada и Windows-лаунчером | `d9cf3c15e3f9fdeaa1c3e608eaa2a3f21791697d` |
| Реактор | `28656ac7f2a4c989d208a066b78f6c280cfcd5e1` |
| Нативный полёт с реактором в истории | `5849463a3d3417a16d3cb98e32f8b13e83557bb9` |
| Сохранённая рабочая ветка `feat/abaddon-launcher` | `9314adc01bfc537b93ef13c1d8e92656e20659ab` |
| Интеграционный worktree | `integration/abaddon-agent2-sync` |

До слияния исходники рабочего лаунчера и новые файлы были сохранены отдельным коммитом. Проверена целостность всех 41 записей SHA-256 пакета передачи. Исходники Flight Lab и Reactor совпали с закреплёнными Git-объектами. Reactor уже входит в сохранённую ветку через `feat/abaddon-native-flight`.

В `d6_autoload.lua` объединены загрузка реактора и саппортов, а в `tests/replay_ui.lua` оставлены оба набора интерфейсных сценариев. Конфликты `launcher/go.mod` и `launcher/main_windows.go` разрешены в пользу единого публикуемого приложения с форматами конфигурации и установки из `main` и экспериментальным профилем Flight Lab. Отдельная реализация сохранена в истории рабочего коммита. Карты реактора, VMF и генератор совпадают с коммитом Reactor. Патч SDK и карта Flight Lab совпадают с нативной веткой.

## Проверки объединённой ветки

| Проверка | Результат |
|---|---|
| Выделенный GMod x64 Sandbox | 119/119. Арена 79, Сити 17 и Reactor 28, roguelike-шахта 9, Vault 3. |
| Саппорты на отдельном GMod x64 | 40/40 проверок штатной диагностики и 11/11 сценариев с живыми игровыми сущностями. Призма перенаправила снаряд в настоящего бойца Альянса, сохранив владельца. |
| Lua | 8 наборов модульных проверок прошли, включая саппорты, геометрию, выстрелы, боеприпасы, мины, крепления и захват. |
| HUD | 42 прогона в трёх разрешениях и 9 дополнительных прогонов реактора с активной панелью Granada. |
| Нативный C++ | 18/18 тестов повторно пройдены на x86-64 с UBSan и на Linux i386 под QEMU. Повторно загружены обе ранее собранные библиотеки ELF32 через `CreateInterface`. SHA исходников SDK overlay и BSP совпадают с проверенной сборкой. |
| Лаунчер | 14 тестов Go и 11 подтестов прошли. Windows CI собрала x64 EXE, открыла окно и проверила переключение трёх профилей. [Первый прогон PR](https://github.com/terminaldetector/RayLight-/actions/runs/45235110515) |
| Графические клиенты | Запуск Steam-клиентов Garry’s Mod и SDK Base 2013 Singleplayer остаётся непроверенным из-за доступа к клиентским депо. |

Режим **HL2 · карты** монтирует BSP, модели и материалы в установленный Half-Life 2. Режим **Flight Lab** — отдельный эксперимент, для которого нужна собранная пара Win32 `client.dll` и `server.dll`. Нативный слой пока охватывает полёт и геометрию стенда.

```yaml
game_main_sha: d9cf3c15e3f9fdeaa1c3e608eaa2a3f21791697d
reactor_sha: 28656ac7f2a4c989d208a066b78f6c280cfcd5e1
native_flight_sha: 5849463a3d3417a16d3cb98e32f8b13e83557bb9
agent_original_branch: feat/abaddon-launcher
agent_original_head: 9314adc01bfc537b93ef13c1d8e92656e20659ab
agent_head_before_checkpoint: 5849463a3d3417a16d3cb98e32f8b13e83557bb9
status: SYNC_DONE
agent_uncommitted_work_preserved: true
integration_branch: integration/abaddon-agent2-sync
resolved_conflicts:
  - DRMD-6DOF/descent_scanner/lua/autorun/d6_autoload.lua
  - DRMD-6DOF/tests/replay_ui.lua
  - DRMD-6DOF/launcher/go.mod
  - DRMD-6DOF/launcher/main_windows.go
unresolved_conflicts: []
gmod_tests: "119/119 карты и режимы, 51/51 саппорты"
native_build_and_test: "18/18 математика, повторная загрузка ранее собранных Linux i386 client.so и server.so"
live_hl2_run: not-run
```

[Лаунчер](launcher/README_RU.md) · [Исходный отчёт нативной сборки](native/hl2/BUILD_RESULTS_RU.txt) · [Клиентские проверки](tests/GRAPHICS_QA_RU.md)
