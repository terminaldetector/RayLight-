# Нативный HL2 и Reactor: исходники, подключение, границы

## Что выполнено

Ветка `feat/abaddon-native-flight`: C++ overlay к **Valve Source SDK 2013 Singleplayer**. Команда `abaddon_flight` включает/выключает 6DOF, `abaddon_flight_status` выводит положение, скорость и углы. Реализованы инерция, тяга по локальным осям, крен Z/X, локальный mouse-look, скольжение вдоль стен. Предел скорости 2200 SU/s, ускорения 4200 SU/s². Сеть: флаг `DT_HL2_Player`; корпус коллизии остаётся вертикальным. Смерть, спавн, транспорт и загрузка сохранения сбрасывают режим.

Это **первый полётный срез, не полный порт GMod механик**. Оружие 4 креплений, мины, саппорты, новые AI-мобы, бои с реактором, HUD и прогрессия остаются HL2-native backlog. GLua Reactor-файлы в истории ветки не исполняются в HL2 автоматически.

## Что упаковано внутрь

`HL2_NATIVE_PORT_SOURCE.zip` сохраняет исходные пути `DRMD-6DOF/native/hl2/`, включая:

- `source-2013-sp.patch`: C++ изменения client/server, player move, mouse/input, ConCommand.
- `abaddon_flight_math.h`, `abaddon_flight_input.h`, `setup_hl2.py`, `gameinfo.txt`.
- `maps/d6_native_flightlab.vmf` и `.bsp`, `tests/`, `linux_gcc14_compat/`.
- `README.md`, `BUILD_RESULTS_RU.txt`, `LICENSE`, `thirdpartylegalnotices.txt`.
- `DRMD-6DOF/tools/build_native_flightlab.py` и зависимость `tools/build_episode.py` из Reactor.

`REACTOR_BRANCH_CHANGED_FILES.zip` хранит изменённые в Reactor файлы, включая `d6_reactor.lua`, `d6_reactor_hazards.lua`, `d6_reactor_visual.lua`, `d6_reactor_node/*`, `d6_rogue_reactor.vmf/.bsp`, изменённую карту `d6_reactor_escape`, миссии и тесты. Эти версии **нельзя массово копировать на main**.

## Настоящее подключение

1. Отдельно получить Valve `source-sdk-2013` singleplayer на `77567eb4bce8d7b6b7f73e929fcde3a331c0216e`. Нужен Steam Source SDK Base 2013 Singleplayer **appid 243730**.
2. Из каталога `DRMD-6DOF/native/hl2` выполнить `python3 setup_hl2.py patch /path/to/source-sdk-2013 --check`, потом `python3 setup_hl2.py patch /path/to/source-sdk-2013`.
3. Собрать `client` и `server` штатными SDK проектами: под Windows требуются **Win32** `client.dll/server.dll`, не Win64; Linux использует i386 `.so`.
4. `python3 setup_hl2.py deploy /path/to/source-sdk-2013/game/mod_hl2/bin /path/to/steamapps/sourcemods/abaddon_native`.
5. Перезапустить Steam, запустить `Half-Life: Abaddon | Native Flight Lab`, `map d6_native_flightlab`, проверить flight state, hull/коллизии и отключение режима.

По историческому `BUILD_RESULTS_RU.txt` заявлены 18/18 математических тестов, сборка Linux i386 `client.so/server.so` и загрузка `CreateInterface`; **живой клиент HL2 не проверен** из-за недоступности app 243730. Это отчёт исходной ветки, не результаты нового прогона.

## Паритет механик

Согласовывать два движковых адаптера по контракту: `6DOF input / local basis` → `ship state` → `mount+socket+projectile event` → `ammo/mines` → `support AI` → `enemy role/targeting` → `mission events`. Не симулировать порт кнопкой запуска или скопированными Lua-файлами. Учитывать 79 compiled MDL, procedural support-модели, свет и реальные дульные точки из MD-handoff; не объявлять Source phong PBR без shader/материалов.
