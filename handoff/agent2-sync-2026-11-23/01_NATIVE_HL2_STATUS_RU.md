# HL2 native: что уже есть и что предстоит синхронизировать

Источник: feat/abaddon-native-flight @ 5849463a3d3417a16d3cb98e32f8b13e83557bb9. В архиве фактическое дерево native/hl2, в том числе двоичный BSP.

## Файлы

- source-2013-sp.patch: изменения клиентских/серверных исходников Valve Source SDK 2013 SP.
- abaddon_flight_math.h: общая математика 6DOF, тяга, инерция и ограничения.
- abaddon_flight_input.h: локальный input, roll и относительное мышиное вращение.
- setup_hl2.py: dry check и применение overlay, развертывание DLL/so + карты.
- maps/d6_native_flightlab.vmf и .bsp: тестовый уровень.
- gameinfo.txt, README.md: оформление native sourcemod, запуск.
- tests/flight_math_test.cpp и sdk_module_loader.c: тесты.
- linux_gcc14_compat/: специфические сборочные исправления GCC14.
- BUILD_RESULTS_RU.txt, LICENSE, thirdpartylegalnotices.txt: результаты и условия.

SDK закреплён на Valve source-sdk-2013 singleplayer коммите 77567eb4bce8d7b6b7f73e929fcde3a331c0216e; для запуска нужен установленный Source SDK Base 2013 Singleplayer, Steam App 243730.

Журнал ветки сообщает: компиляция Linux i386 client.so/server.so прошла, 18 тестов flight math прошли, интерфейсы динамических библиотек проверены. Но Steam клиент и реальный игровой рендер НЕ ПРОВЕРЕНЫ; тестовому аккаунту не удалось получить app 243730. **В репозитории НЕТ готовых нативных Windows client.dll/server.dll**. Не подменять эту стадию утверждением о готовом порте.

Команды для чистой копии SDK:

    cd HL2_NATIVE_PORT/DRMD-6DOF/native/hl2
    python3 setup_hl2.py patch /path/to/source-sdk-2013 --check
    python3 setup_hl2.py patch /path/to/source-sdk-2013
    g++ -std=c++11 -Wall -Wextra -Werror tests/flight_math_test.cpp -o flight-test
    ./flight-test

Развёртывание setup_hl2.py deploy требует СОБРАННЫХ client/server DLL или so; исходники в ZIP не являются готовым модом. Если второй агент уже менял свой SDK, сначала сохранить его патчи и выполнить трёхстороннее сравнение. Нельзя слепо накатывать patch поверх изменённого SDK.

## Реактор

Ветка native-flight наследует reactor-этап и содержит d6_reactor.lua, d6_reactor_hazards.lua, d6_reactor_visual.lua, entities/d6_reactor_node, d6_rogue_reactor.vmf/.bsp, новый reactor_escape.vmf/.bsp, инструменты сборки эпизода и тесты. Эти реальные файлы включены в BRANCH_DELTAS/NATIVE; это **Lua/карты GMod**, а не автоматический C++-порт.

## Механики

Native flight lab реализует движение, инерцию, ось подъёма, крен и скольжение. Флаг переключается abaddon_flight; смерть, загрузка, спавн, транспорт выключают полёт. В README указан предел скорости 2200 SU/с и ускорения 4200 SU/с².

Требование пользователя: в будущем полноценные ветви HL2 и GMod с сопоставимым 6DOF и AI. Пока GMod содержит боевую механику, 4 оружейных крепления, мины, BFG, рейл, гравирейл, крюк, порталы, саппорты Granada. **Native HL2 ещё не содержит полноценного переноса этих систем**. Синхронизировать state/input/events и переносить движковые границы отдельно, не копируя Lua как C++ и не смешивая старый режим launcher hl2-content с будущим hl2-native.
