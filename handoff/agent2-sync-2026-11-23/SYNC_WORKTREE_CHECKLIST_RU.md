# SYNC protocol: сохранение правок агента и безопасное слияние

## A. Checkpoint в текущем репозитории второго агента

```sh
git rev-parse --show-toplevel
git branch --show-current
git rev-parse HEAD
git status --short --untracked-files=all
git log -5 --oneline --decorate
```

Сначала создать локальный backup **всех** собственных исходников, незафиксированных файлов и untracked моделей/ассетов вне репозитория либо полноценный WIP commit в **своей** ветке. Простой `git stash` без `-u` не сохраняет untracked. Никаких `reset --hard`, `clean -fd`, удаления собственного дерева или force push.

Если собственный worktree отсутствует, статус только `SYNC_PENDING_AGENT_WORKTREE`. Архив не претендует на его замену.

## B. Закрепить refs

```sh
git fetch origin main feat/abaddon-reactor feat/abaddon-native-flight
git rev-parse origin/main origin/feat/abaddon-reactor origin/feat/abaddon-native-flight
git merge-base origin/main origin/feat/abaddon-native-flight
git merge-base --is-ancestor origin/feat/abaddon-reactor origin/feat/abaddon-native-flight
```

SHA сверить с `00_SYNC_FIRST_RU.md`. Если на GitHub появились новые, зафиксировать их отдельно и пересчитать diff. Native включает Reactor, повторно merge Reactor отдельно не нужно.

## C. Синхронизация в новом worktree

Ниже `AGENT_BRANCH` — **реальная** сохранённая ветка агента, а не заглушка для запуска:

```sh
git worktree add -b integration/abaddon-agent2-sync ../Abaddon-agent2-sync AGENT_BRANCH
cd ../Abaddon-agent2-sync
git merge --no-ff origin/main
# Разобрать и закоммитить конфликты.
git merge --no-ff origin/feat/abaddon-native-flight
# Разобрать и закоммитить конфликты.
```

Не запускать второй merge до завершения первого. Никакого blanket `--ours/--theirs`. Если есть конфликт, сохранить новый worktree и список; `git merge --abort` допустим только внутри незавершённого merge на **новой** integration-ветке.

## D. Высокорисковые файлы

См. вычисленные `MERGE_OVERLAPS_RU.md` и `GIT_MERGE_PREVIEW.txt`. В первую очередь:
- `descent_scanner/lua/autorun/d6_qmenu.lua`, `d6_autoload.lua`: новое меню, регистрация модулей.
- `d6_actors.lua`, `d6_modules.lua`, `d6_interface.lua`, `d6_mission.lua`: AI, HUD, состояние миссий.
- `d6_reactor_boss.lua`, `d6_rogue.lua`, `d6_weapon_core.lua`, `entities/d6_combat_drone/init.lua`: бой, смерть и реактор.
- `maps/d6_reactor_escape.vmf/.bsp`, `tools/build_episode.py`: объединить **VMF/генератор**, после чего **пересобрать BSP**, не бинарный overwrite.
- `README.md`, `INSTALL_RU.md`, `MAPS_RU.md`: актуализировать после изменения кода.

Сохранять модельный реестр, размеры/hull, сокеты, event выстрела, server-authority, боезапас, autonomous support AI и текущие Q-menu карточки.

## E. Итог для сдачи

```yaml
game_main_sha: d9cf3c15e3f9fdeaa1c3e608eaa2a3f21791697d
reactor_sha: 28656ac7f2a4c989d208a066b78f6c280cfcd5e1
native_flight_sha: 5849463a3d3417a16d3cb98e32f8b13e83557bb9
agent_original_branch: <реальная ветка>
agent_original_head: <реальный SHA>
agent_uncommitted_work_preserved: true|false|unavailable
integration_branch: <ветка>
resolved_conflicts: <список>
unresolved_conflicts: <список>
gmod_tests: <фактический результат>
native_build_and_test: <фактический результат>
live_hl2_run: <pass|fail|not-run>
status: SYNC_DONE|SYNC_PENDING_AGENT_WORKTREE|SYNC_CONFLICTS|SYNC_UNVERIFIED
```

`SYNC_DONE` допустим только после проверки **собственных** правок агента и полученного интеграционного кода. Не путать unit/CI с игрой в настоящем клиенте; минимум нужных технических проверок, не новый всеобъемлющий аудит.
