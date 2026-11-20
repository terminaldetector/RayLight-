# Карты Abaddon в Hammer

Исходники `.vmf` и скомпилированные `.bsp` находятся в `descent_scanner/maps/`. Карты собраны для Source с помощью VBSP++, VVIS++ и VRAD++ в LDR. Геометрию, объекты и цепочки ввода и вывода можно редактировать в Hammer.

| Карта | Маршрут |
|---|---|
| `d6_city17_drain` | Станция, ЭМИ, улица с патрулём и страйдерами, ступенчатый спуск к каналу, лазерный коридор и переход в реактор. |
| `d6_reactor_escape` | Гравитационный рой, бой на подвесных площадках, реакторное ядро и выход через поднявшийся шлюз. |

В городе `d6_emp_path` запускает `d6_emp` при входе. `d6_city_exit` и `d6_drain_link` заданы для штатного перехода Source. В Garry’s Mod отдельный триггер `d6_city_transfer_path` вызывает смену карты через Sandbox.

В реакторе уничтожение `d6_reactor_core` активирует реле `d6_core_failure`. Реле открывает дверь, включает лазер в эвакуационном туннеле и активирует выход. Garry’s Mod дополнительно запускает 58-секундный таймер, мины и облака для восстановления. Триггеры `d6_swarm_enter` и `d6_guard_enter` обозначают места появления боевых групп Abaddon.

## Первые карты Half-Life 2

Скрипт `descent_scanner/lua/d6_campaign.lua` находит рабочую область перед игроком через трассы, проверяет её на пересечения с объектами и обходит места перехода. Стенд живёт 45 секунд. Его можно разместить на следующих смонтированных картах Garry’s Mod.

| Исходная карта | Состав стенда |
|---|---|
| `d1_trainstation_01` | Перехватчик, лазерный дрон, Грависканер |
| `d1_trainstation_02` | Штурмовик, ремонтный дрон, зенитный дрон |
| `d1_trainstation_03` | Планер, Бочкарь, Сборщик |

Имена карт сверены со списком кампании. В облаке трассировка стенда проверена на BSP `gm_flatgrass`. [Список карт](https://steamcommunity.com/sharedfiles/filedetails/?id=3531456419) · [InitPostEntity](https://wiki.facepunch.com/gmod/GM%3AInitPostEntity) · [PlayerSpawn](https://wiki.facepunch.com/gmod/GM%3APlayerSpawn)

Для проверки двух новых карт в оригинальном Half-Life 2 предназначены каталоги `maps`, `models` и `materials` из `descent_scanner`. Их можно смонтировать как собственный контент через `hl2/custom/drmd` и загрузить `map d6_city17_drain`. Штатная логика работает через сущности карты. GLua-бой и HUD требуют Garry’s Mod. Совместимость отдельного клиента HL2 с этими BSP ещё не проверена.

## Сборка из VMF

Папку игры с `gameinfo.txt` передайте инструментам Hammer через `-game`. Для каждой карты выполните VBSP с VMF, затем VVIS и VRAD с результатом BSP. В комплекте есть генератор `tools/build_episode.py` с зависимостью `srctools`. Ручную правку в Hammer удобнее продолжать в существующих VMF.

Исходники моделей хранятся в `descent_scanner/lua`. Команда `texlua export_art.lua` из каталога `tests` экспортирует сетки в `art-models.json`. Для компиляции передайте JSON, путь к StudioMDL++ и каталог игры скрипту `tools/compile_models.py`. [Hammer++](https://ficool2.github.io/HammerPlusPlus-Website/tools.html)
