# Abaddon — модели, материалы и подключение к игре

Технический handoff для второго агента. Срез `main`: **`d9cf3c15e3f9fdeaa1c3e608eaa2a3f21791697d`**, дата проверки — 23.11.2026. Все ссылки на проект ниже закреплены на этом SHA. Документ описывает существующий код и отдельно отмечает работу, которую ещё предстоит сделать. [Зафиксированный коммит][commit].

## 1. Что уже есть

| Слой | Фактическое состояние этого среза |
|---|---|
| Процедурная геометрия | 84 именованных mesh, суммарно 292 803 треугольника во всём экспортированном наборе. Это инвентарь ассетов, а не стоимость одного кадра. |
| Оружие | 29 определений в `D6_Arsenal.Models/Entries`; 12 доступны через игровой `Order/Playable`, остальные 17 сохранены для совместимости. |
| Мобы | 24 варианта в `D6_Drones.Types`, включая двух боссов и три машины Сопротивления. |
| Granada-саппорты игрока | 5 самостоятельных процедурных моделей; одновременно используется до 3 устройств. |
| Собранные Source-модели | 79 комплектов `.mdl` + `.vvd` + `.dx80.vtx` + `.dx90.vtx`; все четыре файла каждого комплекта присутствуют. `.phy` в этом наборе нет. |
| Разница между Lua и MDL | Только пять `support_*.mdl` ещё отсутствуют. Их геометрия уже работает через Lua. |
| Материалы | 31 VMT в `materials/models/drmd/`, 8 текстур `materials/drmd/drmd_finish_*.vtf`. |
| Исходники Blender/GLB | Готовые пары для `heavy_elite` и `arc_elite`; общего обратного импортера Blender → Lua в пайплайне нет. |
| Карты | Три пары VMF/BSP: `d6_city17_drain`, `d6_reactor_escape`, `d6_relay_vault`. |

Числа получены из закреплённого дерева и запуском существующего `tests/export_art.lua` во временной копии этого SHA. Экспорт прошёл проверки конечности координат, ключей материалов и наличия каталожной геометрии. Проверка клиентского изображения, теней и FPS этим не заменяется. Источники: [экспорт][export], [каталог оружия][arsenal], [каталог дронов][drones], [саппорты][supports], [готовые MDL][mdl-dir], [материалы][materials-dir], [карты][maps-dir].

В этом проходе MDL не перекомпилировались: подтверждена комплектность файлов, а соответствие их геометрии текущему Lua надо сохранять пересборкой при изменении модели.

Пути в тексте, если не указан иной корень, отсчитываются от `DRMD-6DOF/`. Устанавливаемый addon — `descent_scanner/`. GMod исполняет Lua и показывает процедурные корпуса; обычный HL2 получает только `maps/`, `models/`, `materials/` и штатную логику карты. Работа всех GLua-систем внутри HL2 не реализована. [Описание карт и границы HL2][maps-doc].

## 2. Реестр оружия

Ключ SWEP — полное имя `weapon_d6_<suffix>`. Для каждого mesh из таблицы уже существует **`descent_scanner/models/drmd/<mesh>.mdl`** со спутниками VVD/VTX. Геометрия, которая сейчас видна в GMod, берётся из Lua, а не автоматически из этого MDL.

Обозначения источников: **M** = [`lua/d6_art_models.lua`][models], **O** = [`lua/d6_art_ordnance.lua`][ordnance]. В O функция `mount(spec)` строит корпус из записи `D6_Arsenal.Models`; поля `body`, `bore`, `width`, `shells`, `skin`, `ports`, `depth` лежат в [каталоге][arsenal].

### Двенадцать игровых систем

| SWEP | Название в каталоге | Mesh / имя MDL без расширения | Источник |
|---|---|---|---|
| `weapon_d6_mg` | Пульсар | `mount_pulse` | M: `pulse` |
| `weapon_d6_flak` | Флак | `gun_flak` | O: `mount(A.Models.flak)` |
| `weapon_d6_plasma` | Плазменный излучатель | `mount_arc` | M: `arc` |
| `weapon_d6_heavy` | Штурмовая мортира | `gun_heavy` | O: `mount(A.Models.heavy)` |
| `weapon_d6_rockets` | Ракетный блок | `mount_rack` | M: `rack` |
| `weapon_d6_gravy_railgun` | Гравирельс | `mount_rail` | M: `rail` |
| `weapon_d6_railmk2` | Рельсотрон Mk II | `gun_railmk2` | O: `mount(A.Models.railmk2)` |
| `weapon_d6_bfg` | Ионный реактор | `gun_bfg` | O: `mount(A.Models.bfg)` |
| `weapon_d6_whiplash` | Луч сцепления | `gun_whiplash` | O: `mount(A.Models.whiplash)` |
| `weapon_d6_phasegate` | Фазовая пушка | `gun_phasegate` | O: `mount(A.Models.phasegate)` |
| `weapon_d6_plasmamine` | Плазменная мина | `mount_mine` | M: `bay` |
| `weapon_d6_gravmine` | Гравитационная мина | `gun_gravmine` | O: `mount(A.Models.gravmine)` |

### Семнадцать совместимых старых определений

Наличие готовой модели не делает систему дополнительным выбором в новом арсенале. `ResolveClass` переводит старые сохранённые классы в текущие. Здесь ключи и замены сокращены до suffix; у обоих сторон префикс `weapon_d6_`. [Правила миграции][arsenal].

| Старый suffix | Mesh / MDL | Источник | Текущая замена |
|---|---|---|---|
| `vulcan` | `gun_vulcan` | O | `mg` |
| `laser` | `gun_laser` | O | `plasma` |
| `quad_laser` | `gun_quad_laser` | O | `plasma` |
| `overdrive` | `gun_overdrive` | O | `plasma` |
| `concussion` | `gun_concussion` | O | `rockets` |
| `homing` | `gun_homing` | O | `rockets` |
| `smart_missile` | `gun_smart_missile` | O | `rockets` |
| `mega_missile` | `gun_mega_missile` | O | `rockets` |
| `frag` | `gun_frag` | O | `heavy` |
| `darklance` | `gun_darklance` | O | `railmk2` |
| `shockwave` | `gun_shockwave` | O | `bfg` |
| `energytrap` | `gun_energytrap` | O | `gravmine` |
| `darkfield` | `gun_darkfield` | O | `gravmine` |
| `telefrag` | `gun_telefrag` | O | `phasegate` |
| `warp` | `gun_warp` | O | `whiplash` |
| `reactor` | `gun_reactor` | O | `bfg` |
| `hyperbeam` | `mount_optic` | M: `capacitor` | `plasma` |

`weapon_d6_reactor` здесь — старое оружие «Сброс реактора», а не модель реакторного босса. Для старого pickup-награждения `hyperbeam` есть отдельный `RewardAliases` → `bfg`; его не следует менять вместе с визуальной заменой корпуса. [Каталог][arsenal].

## 3. Реестр мобов

`key` — значение `D6_ArtVariant` / ключ `D6_Drones.Types`, а не всегда engine classname. Для каждой строки уже есть `models/drmd/<mesh>.mdl`. Масштаб ниже — `D6_Drones.Types[key].scale`, применяемый процедурным `DrawDrone`; это не универсальный множитель физического hull. Источники: [данные/rig][drones], [M][models], [элитные модели E][elites], [размеры боссов][session].

| Key | Mesh / MDL | Масштаб рендера | Исходник / сборка |
|---|---|---:|---|
| `assault` | `assault` | 1 | M: `bioHull` + `bioEmitter` |
| `mg` | `combine_gunner` | 0.93 | M: `bioHull` + `bioEmitter` |
| `laser` | `combine_laser` | 0.91 | M: `bioHull`, секция `Focusing cage` |
| `interceptor` | `interceptor` | 0.97 | M: `bioHull` + `bioEmitter` |
| `rpg` | `combine_rocketeer` | 1.04 | M: `bioHull` + `bioEmitter` |
| `artillery` | `artillery` | 0.96 | M: `bioHull` + `bioEmitter` |
| `rocket_elite_homing` | `elite_homing` | 1.12 | M: `chassis` от `combine_seeker` + кассета |
| `rocket_elite_aa` | `elite_aa` | 1.16 | M: отдельный `G.New` |
| `grav` | `grav` + `grav_gimbal` | 1.16 | M: корпус и отдельное кольцо; рендер рисует три кольца |
| `support` | `support` | 0.94 | M: ремонтный NPC, `bioHull` + `bioEmitter` |
| `heavy` | `heavy` | 1.02 | M: отдельный `G.New` |
| `heavy_elite` | `combine_elite` | 4.2 | E: `siege`; Blender/GLB `citadel-enforcer` |
| `arc_elite` | `combine_arc_elite` | 5.3 | E: `arc`; Blender/GLB `arc-elite` |
| `seeker` | `combine_seeker` | 1.22 | M: `bioHull` + `bioEmitter` |
| `rocket_strider` | `rocket_strider` | 1.35 | M: `chassis` от `heavy` + разнесённые кассеты |
| `plasma_strider` | `plasma_strider` | 1.48 | M: `chassis` от `heavy` + плазменная система |
| `manhack_fast` | `cutter` + `cutter_rotor` | 0.78 | M: два mesh; вращение ротора в рендере |
| `wheatley` | `cutting_probe` | 0.91 | M: отдельный `G.New` |
| `chopper` | `combine_gunship` | 1.28 | M: отдельный `G.New` |
| `worm` | `worm` | 1 | M: отдельный `G.New` |
| `mine` | `mine` | 0.85 | M: отдельный `G.New` |
| `resistance_scout` | `resistance_scout` | 0.88 | M: `scout`, самодельный планер |
| `resistance_raider` | `resistance_raider` | 1 | M: `raider`, Бочкарь |
| `resistance_hauler` | `resistance_hauler` | 1.17 | M: `hauler`, Сборщик |

`support` в этой таблице — ремонтный противник/роль. Пять устройств игрока из следующего раздела принадлежат `D6_Supports` и сущности `d6_support`. Не смешивать эти ключи и сетевые поля. [Каталоги дронов][drones] и [саппортов][supports].

## 4. Пять саппортов игрока

Все пять созданы в [`lua/d6_support_art.lua`][support-art] и зарегистрированы в [`lua/d6_supports.lua`][supports]. Это функциональные greybox-модели с разными силуэтами и рабочими точками. В текущей поставке **ни один из пяти `support_*.mdl` не собран**; ожидаемый путь после компиляции — `models/drmd/<mesh>.mdl`.

| ID / имя | Mesh | Форма и рабочие точки `ports`, в координатах модели |
|---|---|---|
| `reflector` / Призма | `support_reflector` | Разомкнутая плоская подкова; стеклянный рецептор `(16,0,0)` |
| `bulwark` / Створ | `support_bulwark` | Две широкие створки; `(18,-10,-6)`, `(18,10,-6)`, `(18,-10,6)`, `(18,10,6)` |
| `interceptor` / Клык | `support_interceptor` | Узкий механический клин; `(24,-5,0)`, `(24,5,0)` |
| `missile` / Кассета | `support_missile` | Два неравных ракетных короба; `(20,-7,-5)`, `(20,7,-5)`, `(20,-7,5)`, `(20,7,5)` |
| `resonator` / Резонатор | `support_resonator` | Заряд в трёх открытых рёбрах; сплошная ударная пластина `(14,0,0)` |

Общая стыковочная плоскость — **x = −18**. Излучатели и индикаторы небольшие; у Призмы — рецептор, у Резонатора — пластина, поэтому нельзя превращать каждую переднюю точку в одинаковое дуло. Привязка створок/сопел и ограниченная светящаяся площадь уже проверяются существующим [support_art_unit.lua][support-test].

`entities/d6_support/cl_init.lua` рисует `D6_Art.Draw(def.mesh, …, scale=1, …)` с render bounds ±32. Серверный носитель — `models/hunter/misc/sphere025x025.mdl`, `SOLID_NONE`, collision bounds ±28, `DrawShadow(false)`. Боевые трассы/размещение рассчитывает менеджер саппортов. Изменение визуального габарита не должно молча менять его геометрию взаимодействия. [Client][support-client-ent], [server][support-server-ent], [менеджер][supports].

## 5. Остальные mesh, которые нельзя потерять при перепаковке

Это ещё 26 mesh сверх 29 оружейных, 24 основных корпусов NPC и пяти саппортов. Все перечисленные ниже уже имеют MDL-комплекты. [M][models], [O][ordnance], [дерево моделей][mdl-dir].

| Группа | Mesh / MDL | Источник |
|---|---|---|
| Игрок | `scanner_player` | M |
| Дополнительные детали NPC | `cutter_rotor`, `grav_gimbal` | M |
| Крепления и общий модуль | `mount_joint`, `mine_hatch`, `mount_field` | M |
| Общие снаряды | `shot_kinetic`, `shot_energy`, `shot_rocket`, `shot_exotic` | M |
| Инструменты | `tool_deployer`, `mech_receiver` | O |
| Мины / узлы | `mine_plasma`, `mine_gravity`, `mine_air`, `node_snare`, `node_dark` | O |
| Именованные боеприпасы | `shot_shell`, `shot_cluster`, `shot_homing`, `shot_mega`, `shot_shard`, `shot_arcpulse`, `shot_ion` | O |
| Груз / припасы | `supply`, `salvage_ballast` | O |

У `D6_Arsenal.Ordnance` 14 записей — последние три группы. `ToolVisual` используется `weapon_d6_deployer` и `weapon_d6_spawn_*`; `MechVisual` — `weapon_combine_mech_drone`. Не создавать новый корпус для каждого такого alias без необходимости. [Маршрутизация Visual][arsenal].

## 6. Авторинг, экспорт, материалы

### Две цепочки из общего источника

1. **Игровой GMod-рендер:** `d6_art_geometry.lua` → геометрические Lua-файлы → `G.models[mesh].parts` → `d6_art_render.lua` → `Mesh():BuildFromTriangles` → `D6_Art.Draw/DrawDrone`.
2. **Source / Hammer / внешнее 3D:** те же Lua-файлы → `tests/export_art.lua` → `tests/art-models.json` → `tools/compile_models.py` для Source либо `tools/build_elite_studio.py` для двух Blender/GLB-сцен. [Geometry][geometry], [renderer][render], [export][export], [compiler][compiler], [studio builder][studio].

Внутренний face: `{v1, v2, v3, normal, section}`; ключ `parts[material]` должен существовать в `G.palette`. `G.finishes` выбирает общую покрывающую текстуру. UV вычисляются проекцией по доминирующей оси нормали с делением координат на 24 — это текущая схема, а не индивидуальная художественная развёртка каждого корпуса. [Geometry][geometry], [compiler][compiler].

Для повторной сборки выполнять из копии нужного коммита:

```bash
cd DRMD-6DOF/tests
texlua export_art.lua
cd ..
python tools/compile_models.py tests/art-models.json /path/to/studiomdl /path/to/staging/game
```

Третий аргумент — подготовленный каталог игры для `studiomdl -game` с нужным `gameinfo.txt`; сначала собирать туда и переносить проверенные ассеты в addon. Скрипт перегенерирует **все** VMT из палитры, поэтому ручное улучшение только готового VMT будет затёрто следующей сборкой. Менять нужно также `write_materials()`. [Компилятор][compiler].

QC/SMD создаются во временной папке и после сборки удаляются; отдельных сохранённых `.qc` в этом наборе нет. Сгенерированный QC содержит `$staticprop`, один `$body`, `$cdmaterials "models/drmd"`, `$surfaceprop "metal"`, неподвижную `idle`-последовательность. SMD имеет единственную кость `root`; QC не пишет `$attachment`, collision mesh и анимацию банков. **Эти MDL — статический экспорт геометрии, а не экспорт всего процедурного rig.** [Компилятор][compiler].

Если поставка второго агента должна содержать авторские QC, attachments, collision mesh или анимацию, их необходимо действительно сохранить и подключить в воспроизводимую цепочку; наличие нынешнего MDL этого не подтверждает. `.phy` не возникает из одной таблицы `ports`.

### Готовые внешние 3D-ассеты

| Вариант | Редактируемый файл | Проверочный файл | Первичный геометрический источник |
|---|---|---|---|
| `heavy_elite` | [`art/elites/citadel-enforcer.blend`][enforcer-blend] | [`citadel-enforcer.glb`][enforcer-glb] | [d6_art_elites.lua][elites] |
| `arc_elite` | [`art/elites/arc-elite.blend`][arc-blend] | [`arc-elite.glb`][arc-glb] | [d6_art_elites.lua][elites] |

В студийном экспорте `units = craft.scale * 0.0254`; координаты Blender уже включают масштаб конкретного дрона и перевод Source units в метры по принятому скриптом коэффициенту. Нельзя возвращать такую сцену в игровой путь и повторно умножать её на 4.2/5.3. `Socket · …` — Blender empties; сами по себе они не становятся Source attachments. [Studio builder][studio], [описание ассетов][elite-readme].

Покрытия: `coating`, `alloy`, `polymer`, `glass`, `salvage`, `siege_plate`, `arc_shell`, `turned_steel`. Последние три генерирует `tools/build_elite_finishes.py`: для Source он пишет 512 px VTF **только albedo**; для Blender — 1024 px PNG albedo/roughness/normal. Текстуры для сцены можно воспроизвести; текущий скрипт не импортирует изменённый GLB обратно в `G.models`. [Палитра][geometry], [finish builder][finishes], [studio builder][studio].

```bash
# Из DRMD-6DOF; нужны NumPy/Pillow и Blender для второй команды.
python tools/build_elite_finishes.py descent_scanner/materials/drmd textures
blender -b -P tools/build_elite_studio.py -- tests/art-models.json textures studio --render
```

## 7. Оси, sockets и подвижные банки

### Не перепутать два соглашения

| Данные | Оси | Преобразование в мир |
|---|---|---|
| Вершины mesh, оружейные `ports`, `D6_Drones.Types.guns`, саппортные `ports` | +X вперёд, +Y влево модели, +Z вверх | `origin + Forward*x - Right*y + Up*z` |
| `D6_Arsenal.Mounts.pos`, `D6_ViewMounts.Slots.pos`, старые `{fwd,rgt,up}` / SCK muzzle offsets | Вперёд, вправо, вверх | `origin + Forward*x + Right*y + Up*z` |

Это прямо следует из `A.Port`, `A.MountOrigin`, `D.Socket`, `S.SocketAt` и `D6_Wep.MuzzleFor`. Ошибка знака Y зеркалит ствол и вспышку при крене. [Arsenal][arsenal], [drones][drones], [supports][supports], [weapon core][weapon-core], [view mounts][view].

Основные контракты:

- Оружие: `D6_Arsenal.Models[suffix].ports` → `Entries[class].ports` → `D6_Wep.MuzzleFor` → `A.MountOrigin/Port`. В полёте используется полный угол для смещения дул; `ShootAng` отдельно задаёт направление без roll. Явный SCK muzzle override имеет приоритет. [Weapon core][weapon-core], [SCK bridge][sck].
- NPC: `D6_Drones.Types[key].guns` задаёт локальные точки. `D.Rigs[mesh]` связывает `section` геометрии с банком; `PortBank`, `BankPose`, `Socket`, `Muzzle` используют ту же отдачу и поворот, что рендер деталей. Точное имя секции — часть контракта. [Drones][drones], [renderer][render].
- У `combine_arc_elite` есть `hinges`, `rotors`, `ports`, `travel`; нельзя переименовать `Port arc emitter and carriage`, `Starboard rotary barrels` и другие секции без обновления `Rigs.sections`. У `combine_elite` свои банки пушек и ракет. [Drones][drones], [элитная геометрия][elites].
- `heavy_elite` не имеет обычного массива `guns` в `Types`: `EnforcerBattery` в [d6_modules.lua][modules] вызывает `D6_Patterns.Enforcer`. Именно [d6_patterns.lua][patterns] задаёт координаты пушек/кассет и передаёт их в `D6_Drones.Socket` вместе с банком. Не подставлять произвольный общий `guns[1]`. Студийный builder также содержит свои точки тяжёлой элиты; при замене сверить оба представления. [Studio][studio].
- Корпус игрока: `A.Scanner` хранит native-модель сканера, `mesh="scanner_player"`, eye и `yawOffset=90`; native сканер и оружейные mesh имеют разную исходную ориентацию. Сохранять существующее преобразование `ScannerAngles/ScannerEye`, не добавлять ещё один поворот «на глаз». [Arsenal][arsenal].
- После изменения масштаба сверять **видимый габарит, render bounds и боевой hull**. Для боссов hull задан в `D6_Session.Enforcer/ArcElite`, для ролей — `d6_ai_roles.lua`; generic discover рендера использует bounds `42*skin.scale`. Масштаб в художественном ТЗ не является готовым значением этих полей. [Session][session], [roles][roles], [renderer][render].

В текущем runtime точки — Lua-данные; общего автоматического переноса всех Blender attachments в эти таблицы и QC нет. Историческое требование «экспортировать точки из модели» остаётся задачей дальнейшего пайплайна. При новой модели сохранить один воспроизводимый источник координат и явно показать получившиеся Lua/Source-данные. [Текущее устройство экспорта][export], [compiler][compiler], [историческое ТЗ][art-task].

## 8. Как подключить замену или новую модель

### А. Замена существующего процедурного корпуса

1. Сохранить ключ варианта/SWEP/support ID. Изменить `G.New(existing_mesh)` в соответствующем M/O/E/support-файле; при новом mesh-имени обновить ссылку в каталоге. Так существующие сохранения, фабрики и меню продолжат использовать тот же игровой ID.
2. Совместно обновить форму, `ports/guns` и при необходимости `Rigs.sections/hinges/rotors`. Для оружия отдельно проверить реальные выстрелы и декоративный flash в `drawMount`: визуальный эффект не должен становиться вторым источником урона.
3. Если добавлен отдельный Lua-файл геометрии, включить его в `clientFiles` после `d6_art_geometry.lua` и до `d6_art_render.lua`, а также в `tests/export_art.lua`. Autoload отправляет `clientFiles` клиентам через `AddCSLuaFile`.
4. Повторить экспорт и при необходимости компиляцию MDL, забрать полный комплект и материалы. Замена только MDL не меняет процедурный GMod-корпус; замена только Lua не обновляет статическую модель в Hammer/HL2.
5. Перезапустить клиентский addon/карту для чистого построения mesh/RT-кэшей и проверить world, первый вид и меню. Локальные кэши привязаны к mesh/ключу и не следят за редактированием вершин в файле.

Точки входа этих шагов: [autoload][autoload], [export][export], [renderer][render], [preview helper][previews].

### Б. Добавление нового игрового ID

- **Оружие:** запись в `A.Models`, `weapon(...)`, рабочий SWEP `lua/weapons/weapon_d6_<suffix>.lua`. Для появления в текущем арсенале нужны `selected/Playable`, `Operating` и осмысленная выдача. Добавление одной модели не делает оружие игровым; изменение перечня — отдельное изменение состава арсенала. Обычная визуальная замена этого не требует. [Arsenal][arsenal], [пример SWEP][mg-swep].
- **NPC:** запись в `D6_Drones.Types` обеспечивает art, но для спавна необходима существующая роль/фабрика. `autorun/d6_npc_list.lua` регистрирует пункт и маршрутизирует `d6_spawn_unit` через `basic`, `roles`, `factories`; `d6_session.lua` назначает `D6_ArtVariant`. Новое mesh-имя существующего key не требует создавать новый AI. [NPC menu][npc-menu], [session][session], [roles][roles].
- **Саппорт:** данные в `S.Order/Definitions`, геометрия в `d6_support_art.lua`. Меню собирается из `S.Order`. Замена одной из пяти форм не требует новой сущности; сохранять `D6_SupportKind`, `D6_SupportPower`, `ports`, существующие состояния и размер взаимодействия. [Supports][supports], [client entity][support-client-ent], [spawnmenu][spawnmenu].

### В. Авторский MDL из Blender

Это возможное направление следующей работы, но готового переключателя «любая новая MDL заменяет procedural art везде» нет. Нужны реальный Source export/QC, пути материалов, scale/bounds, attachments/rig, а затем согласованное подключение рендера.

Для ролей `loadout.model` с валидной моделью уже отключает назначение procedural `D6_ArtVariant` в `D6_Session.SetVariant`. Этот путь надо проверить вместе с построением роли; он не обновляет `D6_Drones.Types` и не переводит карточку меню на MDL автоматически. Для оружия просто `SWEP.ViewModel/WorldModel` недостаточно: существующий рендер скрывает стандартный viewmodel и вызывает `D6_Art.DrawWorldWeapon`. [Session][session], [roles][roles], [renderer][render], [пример SWEP][mg-swep].

Если выбран native MDL-путь, превью также должно рисовать этот MDL в существующий кэш RT или получать соответствующее процедурное представление. Не оставлять в меню старый корпус после замены игрового. Сейчас helper умеет именно `G.models`, без fallback на произвольный `.mdl`. [Preview helper][previews].

## 9. World, cockpit и карточки меню

| Место | Где подключено | Что сохранить |
|---|---|---|
| Корпуса NPC | `d6_art_render.lua`: `discover` → `RenderOverride=drawAssigned` → `DrawDrone` | Variant, banks, rotor/gimbal, bounds |
| Саппорты в мире | `entities/d6_support/cl_init.lua`: `ENT:Draw` | Каталог `S.Definitions`, pose, power, sockets |
| Оружие вне полёта | SWEP `DrawWorldModel` → `D6_Art.DrawWorldWeapon` | Привязка к `anim_attachment_RH` или позиции оружия |
| Корпус игрока / мировые крепления | `PrePlayerDraw` / `PostPlayerDraw`, `drawScannerMounts` | Пять физических мест из `A.Mounts`, native orientation сканера |
| Первый вид полёта | `D6_ViewMounts.Collect/Pose`, hook `D6_ArtViewMount` | Четыре видимых оружия, собственные состояние и отдача каждого, полный roll |
| Q → Abaddon и обычные Weapons/NPC | `autorun/d6_spawnmenu.lua`, `autorun/d6_npc_list.lua` | Настоящее изображение текущего корпуса, ID фабрики, локальные 2D-координаты |
| Бестиарий | `d6_bestiary.lua` / команда `d6_bestiary` | Интерактивный просмотр фактической геометрии |

Источники: [renderer][render], [view][view], [support entity][support-client-ent], [spawnmenu][spawnmenu], [NPC menu][npc-menu], [bestiary][bestiary].

Рабочий API карточки:

```lua
D6_SpawnPreview.Draw({kind="npc", key="assault"}, x, y, w, h)
D6_SpawnPreview.Draw({kind="weapon", class="weapon_d6_mg"}, x, y, w, h)
D6_SpawnPreview.Draw({kind="support", key="reflector"}, x, y, w, h)
```

Можно явно передать `mesh` и `color`. Возврат — готовность cached image. Helper строит один видимый item за кадр в `PreRender`; static 3/4 изображение 192×128 хранится в RT 256×128. В `Paint/PaintOver` остаётся только 2D-рисование с сохранённым VGUI clipping; не переносить туда полный рендер каждой модели каждый кадр. Нынешние карточки Abaddon имеют размер 184×160, область картинки — `w-8` × 103. [Helper][previews], [карточки][spawnmenu].

Последние принятые настройки обзора уже находятся в `main`: `d6_rearview=0` по умолчанию; выключенная камера не вызывает `RenderView`, RT создаётся лениво. V используется как fallback только при свободной клавише, реальный bind `d6_rearview_toggle` имеет приоритет. `d6_view_mount_spread=1.125`, диапазон 1…1.5: боковые пушки раздвинуты на 12.5%; мировые sockets и траектории от этого не сдвигаются. Сохранять возможность скрыть задний обзор и свободную центральную зону при дальнейшей работе над cockpit. [Rear view][rearview], [renderer][render], [view geometry][view], [настройки Q][spawnmenu].

## 10. Материалы, PBR и тени арены

### Что действительно реализовано

- Процедурные корпуса используют создаваемые в `d6_art_render.lua` **UnlitGeneric**-материалы. Геометрический оттенок запекается в vertex color формулой от нормали; для `lit=true` добавляется один коэффициент `GetLightColor(position)` с ограничением 0.56…1.25. Это не физически корректный свет по поверхности и не полноценный приём теней на корпусе. [Renderer][render].
- Готовые VMT: `VertexLitGeneric` для большинства материалов, `UnlitGeneric` для `emit/hot/lamp/siege_eye`; генератор пишет `$basetexture` и `$color`. Normal, roughness, metalness, `$phong` и `$envmap` в этом генераторе не подключены. Добавление новых VTF без соответствующей настройки шейдера ничего не подключает. [Compiler/write_materials][compiler], [готовые VMT][vmt-dir].
- Blender/GLB-студия имеет Principled BSDF, roughness/metallic и normal maps. Это отдельное представление ассета; оно не превращает GMod/HL2-материалы в тот же PBR. [Studio][studio], [finish builder][finishes].

### Конкретные причины слабого/несовпадающего затенения

| Место | Наблюдение по закреплённой поставке | Где исправлять |
|---|---|---|
| `d6_relay_vault` | В генераторе 20 обычных `light`, две повторяющиеся линии источников; отсутствуют `env_cubemap`, `shadow_control`, `env_projectedtexture` | `tools/build_episode.py::vault()` и соответствующий VMF |
| Все три BSP | Есть LDR lighting lump 8; длина HDR lighting lump 53 = 0 и cubemap-sample lump 42 = 0 | Свет/образцы в VMF, затем реальная пересборка и проверка отражений |
| Видимый процедурный корпус | Его отрисовка и native-модель носителя — разные пути; одинаковое соответствие силуэта в shadow pass не обеспечено специальной реализацией | `d6_art_render.lua`, entity renderer/native visual model |
| Саппорты / ordnance / projectile | Есть явные `DrawShadow(false)`; у саппорта native carrier — сфера | Соответствующие `entities/*/init.lua`; сначала выбрать корректный shadow caster |
| «Студийный металл» в игре | Source получает albedo, а roughness/normal из Blender-пайплайна в игровые VMT не перенесены | `build_elite_finishes.py`, `compile_models.py::write_materials`, GLua materials |

Источники: [генератор карт][map-builder], [VMF/BSP][maps-dir], [renderer][render], [support init][support-server-ent], [ordnance init][ordnance-init], [projectile init][projectile-init], [finish builder][finishes]. Значения BSP lumps проверены чтением бинарных заголовков именно этого SHA. Это не визуальный замер теней на клиенте.

### Практический следующий проход

1. Выбрать один материал и один корпус на `d6_relay_vault`, зафиксировать одинаковый ракурс. Отдельно проверить материал на готовом MDL и на процедурном mesh. Так видно, какой путь действительно меняется.
2. Для обычного Source-материала подготовить normal map и подходящий specular/Phong/envmap-вариант, если он нужен выбранному визуалу; менять и шаблон VMT, и источник текстур. Называть результат улучшенным Source-материалом до появления настоящего PBR shader path.
3. Для процедурного пути отдельно решить освещение IMesh. Простая смена строки на `VertexLitGeneric` недостаточна для устойчивого света: Facepunch описывает повторное использование lighting state предыдущей модели и необходимость корректной инициализации освещения. Проверять normals/UV, material vertex format, lighting state и восстановление render state. [IMesh:Draw — первичная документация](https://wiki.facepunch.com/gmod/IMesh:Draw).
4. Сначала совместить видимую геометрию и её shadow caster, включая поворачивающиеся банки; затем настраивать источники. Включать тень native-сферы саппорта вместо его корпуса — непроверенная подмена силуэта.
5. Для арены пересмотреть расстановку/контраст обычного света, локально необходимые lightmap settings, добавить и собрать подходящие cubemap samples. `tools/build_episode.py` генерирует VMF, а BSP собирается VBSP → VVIS → VRAD. Изменение одного исходника не обновляет уже лежащий BSP. [Карты/сборка][maps-doc], [генератор][map-builder].
6. Если потребуется `ProjectedTexture`, начать с малого числа реально нужных источников. В API указан стандартный лимит 8 теневых projected textures, включая фонарь; множество таких источников снижает FPS. В текущем addon этот путь для аренной системы света не реализован. [Первичная документация](https://wiki.facepunch.com/gmod/ProjectedTexture:SetEnableShadows).

Профили launcher `low/balanced/high` уже задают штатные `r_shadows`, `r_shadowrendertotexture`, flashlight depth, `mat_bumpmap`, `mat_specular`, anisotropy. В `balanced/high` depth resolution — 1024/2048. Они не создают отсутствующие текстуры, HDR-данные, cubemap samples и shadow casters. `default` не является сбросом предыдущих пользовательских настроек. Не выдавать этот выбор за переключатель PBR. [Реальный CFG-контракт][launcher-core].

## 11. Историческое ТЗ и визуальные цели

[`DRONE_ART_TASK_RU.md`][art-task] — **отдельное художественное задание**, а не отчёт о готовности девяти новых производственных моделей. Оно задаёт три лёгких, три средних, три тяжёлых корпуса; существующие `heavy_elite` и `arc_elite` сохраняются отдельно, реактор не входит в эти девять. Текущие записи с теми же ID и процедурные формы уже существуют, но это не доказывает выполнение всего нового задания с исходниками, масштабным листом, анимацией и экспортируемыми attachments.

Для следующего прохода сохраняются следующие цели из этого ТЗ и переданного контекста:

- Узнаваемые Half-Life-формы, крупные читаемые массы, назначение машины видно по силуэту, а не только цвету. Масштабовые диапазоны ТЗ — ориентир макета; фактические Source units сверять с игроком, двумя боссами и проходами.
- Различимые лёгкие/средние/тяжёлые формы при полном 6DOF: сверху, снизу, сзади и с креном. Девять новых корпусов не должны стать девятью перекрашенными сканерами.
- Саппорты — компактные устройства между визуальным языком Half-Life и Granada: стык, механизм, рабочая поверхность и читаемое состояние; три места в строю, пять текущих ролей.
- Ствол, socket, вспышка и начало снаряда относятся к одному работающему блоку. Отдача/поворот банка должны перемещать его точку; bright flare не должен скрывать несовпадение.
- Тёмный промышленный материал с локальными функциональными акцентами; умеренное свечение, читаемость центрального обзора. Для меню уже принят путь картинок реальных моделей; текстовые заглушки не должны возвращаться.

Источники целей и действующих ограничений: [историческое ТЗ][art-task], [два сохранённых босса][elite-readme], [support art][support-art], [новый spawnmenu][spawnmenu], [cockpit projection][view]. Дальнейшая переработка AI, баланса, реактора и native-flight не является следствием простой замены модели.

## 12. Минимальная проверка после изменения ассета

Использовать уже существующие проверки, относящиеся к изменению; новый зеркальный тестовый набор не нужен.

```bash
cd DRMD-6DOF/tests
texlua export_art.lua             # реальная геометрия, материалы, каталог, конечные координаты
texlua support_art_unit.lua       # если менялись пять саппортов/их рабочие поверхности
texlua verify_mines_and_view.lua   # если затронуты проекции креплений/минный отсек
```

В `export_art.lua` есть предел `<65535` вершин на material-part и проверка абсолютных координат `<500`; изменяя крупную геометрию, понимать эти существующие ограничения. Source-компиляция отдельно подтверждается полным набором файлов и `util.IsValidModel` в GMod; GLB-картинка не подтверждает пригодность MDL. [Export][export], [support geometry test][support-test], [view/mine test][view-test], [существующий GMod probe][cloud-test].

Достаточный короткий клиентский проход: открыть модель в бестиарии и обеих вкладках Q, увидеть тот же корпус в мире, выполнить выстрел при нулевом и полном крене, проверить pivot/отдачу и ближайшую стену. Для саппорта — стыковка/вынос/возврат и своя рабочая точка; для cockpit — четыре пушки, свободный прицел, переключение заднего вида и 16:9/широкий экран. Для материалов/теней — один и тот же ракурс на открытой части арены и в затенённом проходе. Сохранить короткий результат и известные ограничения; не объявлять отсутствие визуальных дефектов по одному успешному Lua-export.

Для саппортов уже есть read-only GMod probe [drmd_support_verify.lua][support-probe] с командами `d6_support_verify` / `d6_support_verify_client`; он не заменяет наблюдение выстрелов и возвращения. На этапе составления этого MD новый GMod-клиентский прогон не выполнялся.

## Ссылки на закреплённые исходники

Быстрые входы: [каталоги оружия][arsenal] / [дронов][drones] / [саппортов][supports]; [рендер][render] / [геометрия][geometry]; [экспорт][export] / [Source compiler][compiler]; [историческое художественное ТЗ][art-task]. Все внутрипроектные ссылки этого документа используют полный SHA выше.

[commit]: https://github.com/terminaldetector/RayLight-/commit/d9cf3c15e3f9fdeaa1c3e608eaa2a3f21791697d
[arsenal]: https://github.com/terminaldetector/RayLight-/blob/d9cf3c15e3f9fdeaa1c3e608eaa2a3f21791697d/DRMD-6DOF/descent_scanner/lua/d6_arsenal.lua
[drones]: https://github.com/terminaldetector/RayLight-/blob/d9cf3c15e3f9fdeaa1c3e608eaa2a3f21791697d/DRMD-6DOF/descent_scanner/lua/d6_drone_catalog.lua
[supports]: https://github.com/terminaldetector/RayLight-/blob/d9cf3c15e3f9fdeaa1c3e608eaa2a3f21791697d/DRMD-6DOF/descent_scanner/lua/d6_supports.lua
[geometry]: https://github.com/terminaldetector/RayLight-/blob/d9cf3c15e3f9fdeaa1c3e608eaa2a3f21791697d/DRMD-6DOF/descent_scanner/lua/d6_art_geometry.lua
[models]: https://github.com/terminaldetector/RayLight-/blob/d9cf3c15e3f9fdeaa1c3e608eaa2a3f21791697d/DRMD-6DOF/descent_scanner/lua/d6_art_models.lua
[ordnance]: https://github.com/terminaldetector/RayLight-/blob/d9cf3c15e3f9fdeaa1c3e608eaa2a3f21791697d/DRMD-6DOF/descent_scanner/lua/d6_art_ordnance.lua
[elites]: https://github.com/terminaldetector/RayLight-/blob/d9cf3c15e3f9fdeaa1c3e608eaa2a3f21791697d/DRMD-6DOF/descent_scanner/lua/d6_art_elites.lua
[support-art]: https://github.com/terminaldetector/RayLight-/blob/d9cf3c15e3f9fdeaa1c3e608eaa2a3f21791697d/DRMD-6DOF/descent_scanner/lua/d6_support_art.lua
[render]: https://github.com/terminaldetector/RayLight-/blob/d9cf3c15e3f9fdeaa1c3e608eaa2a3f21791697d/DRMD-6DOF/descent_scanner/lua/d6_art_render.lua
[session]: https://github.com/terminaldetector/RayLight-/blob/d9cf3c15e3f9fdeaa1c3e608eaa2a3f21791697d/DRMD-6DOF/descent_scanner/lua/d6_session.lua
[roles]: https://github.com/terminaldetector/RayLight-/blob/d9cf3c15e3f9fdeaa1c3e608eaa2a3f21791697d/DRMD-6DOF/descent_scanner/lua/d6_ai_roles.lua
[modules]: https://github.com/terminaldetector/RayLight-/blob/d9cf3c15e3f9fdeaa1c3e608eaa2a3f21791697d/DRMD-6DOF/descent_scanner/lua/d6_modules.lua
[patterns]: https://github.com/terminaldetector/RayLight-/blob/d9cf3c15e3f9fdeaa1c3e608eaa2a3f21791697d/DRMD-6DOF/descent_scanner/lua/d6_patterns.lua
[weapon-core]: https://github.com/terminaldetector/RayLight-/blob/d9cf3c15e3f9fdeaa1c3e608eaa2a3f21791697d/DRMD-6DOF/descent_scanner/lua/d6_weapon_core.lua
[view]: https://github.com/terminaldetector/RayLight-/blob/d9cf3c15e3f9fdeaa1c3e608eaa2a3f21791697d/DRMD-6DOF/descent_scanner/lua/d6_view_mounts.lua
[rearview]: https://github.com/terminaldetector/RayLight-/blob/d9cf3c15e3f9fdeaa1c3e608eaa2a3f21791697d/DRMD-6DOF/descent_scanner/lua/d6_rearview.lua
[sck]: https://github.com/terminaldetector/RayLight-/blob/d9cf3c15e3f9fdeaa1c3e608eaa2a3f21791697d/DRMD-6DOF/descent_scanner/lua/autorun/d6_sck_bridge.lua
[mg-swep]: https://github.com/terminaldetector/RayLight-/blob/d9cf3c15e3f9fdeaa1c3e608eaa2a3f21791697d/DRMD-6DOF/descent_scanner/lua/weapons/weapon_d6_mg.lua
[autoload]: https://github.com/terminaldetector/RayLight-/blob/d9cf3c15e3f9fdeaa1c3e608eaa2a3f21791697d/DRMD-6DOF/descent_scanner/lua/autorun/d6_autoload.lua
[previews]: https://github.com/terminaldetector/RayLight-/blob/d9cf3c15e3f9fdeaa1c3e608eaa2a3f21791697d/DRMD-6DOF/descent_scanner/lua/d6_spawnmenu_icons.lua
[spawnmenu]: https://github.com/terminaldetector/RayLight-/blob/d9cf3c15e3f9fdeaa1c3e608eaa2a3f21791697d/DRMD-6DOF/descent_scanner/lua/autorun/d6_spawnmenu.lua
[npc-menu]: https://github.com/terminaldetector/RayLight-/blob/d9cf3c15e3f9fdeaa1c3e608eaa2a3f21791697d/DRMD-6DOF/descent_scanner/lua/autorun/d6_npc_list.lua
[bestiary]: https://github.com/terminaldetector/RayLight-/blob/d9cf3c15e3f9fdeaa1c3e608eaa2a3f21791697d/DRMD-6DOF/descent_scanner/lua/d6_bestiary.lua
[support-client-ent]: https://github.com/terminaldetector/RayLight-/blob/d9cf3c15e3f9fdeaa1c3e608eaa2a3f21791697d/DRMD-6DOF/descent_scanner/lua/entities/d6_support/cl_init.lua
[support-server-ent]: https://github.com/terminaldetector/RayLight-/blob/d9cf3c15e3f9fdeaa1c3e608eaa2a3f21791697d/DRMD-6DOF/descent_scanner/lua/entities/d6_support/init.lua
[ordnance-init]: https://github.com/terminaldetector/RayLight-/blob/d9cf3c15e3f9fdeaa1c3e608eaa2a3f21791697d/DRMD-6DOF/descent_scanner/lua/entities/d6_ordnance/init.lua
[projectile-init]: https://github.com/terminaldetector/RayLight-/blob/d9cf3c15e3f9fdeaa1c3e608eaa2a3f21791697d/DRMD-6DOF/descent_scanner/lua/entities/d6_projectile/init.lua
[export]: https://github.com/terminaldetector/RayLight-/blob/d9cf3c15e3f9fdeaa1c3e608eaa2a3f21791697d/DRMD-6DOF/tests/export_art.lua
[compiler]: https://github.com/terminaldetector/RayLight-/blob/d9cf3c15e3f9fdeaa1c3e608eaa2a3f21791697d/DRMD-6DOF/tools/compile_models.py
[studio]: https://github.com/terminaldetector/RayLight-/blob/d9cf3c15e3f9fdeaa1c3e608eaa2a3f21791697d/DRMD-6DOF/tools/build_elite_studio.py
[finishes]: https://github.com/terminaldetector/RayLight-/blob/d9cf3c15e3f9fdeaa1c3e608eaa2a3f21791697d/DRMD-6DOF/tools/build_elite_finishes.py
[map-builder]: https://github.com/terminaldetector/RayLight-/blob/d9cf3c15e3f9fdeaa1c3e608eaa2a3f21791697d/DRMD-6DOF/tools/build_episode.py
[maps-doc]: https://github.com/terminaldetector/RayLight-/blob/d9cf3c15e3f9fdeaa1c3e608eaa2a3f21791697d/DRMD-6DOF/MAPS_RU.md
[maps-dir]: https://github.com/terminaldetector/RayLight-/tree/d9cf3c15e3f9fdeaa1c3e608eaa2a3f21791697d/DRMD-6DOF/descent_scanner/maps
[mdl-dir]: https://github.com/terminaldetector/RayLight-/tree/d9cf3c15e3f9fdeaa1c3e608eaa2a3f21791697d/DRMD-6DOF/descent_scanner/models/drmd
[materials-dir]: https://github.com/terminaldetector/RayLight-/tree/d9cf3c15e3f9fdeaa1c3e608eaa2a3f21791697d/DRMD-6DOF/descent_scanner/materials
[vmt-dir]: https://github.com/terminaldetector/RayLight-/tree/d9cf3c15e3f9fdeaa1c3e608eaa2a3f21791697d/DRMD-6DOF/descent_scanner/materials/models/drmd
[elite-readme]: https://github.com/terminaldetector/RayLight-/blob/d9cf3c15e3f9fdeaa1c3e608eaa2a3f21791697d/DRMD-6DOF/art/elites/README.md
[enforcer-blend]: https://github.com/terminaldetector/RayLight-/blob/d9cf3c15e3f9fdeaa1c3e608eaa2a3f21791697d/DRMD-6DOF/art/elites/citadel-enforcer.blend
[enforcer-glb]: https://github.com/terminaldetector/RayLight-/blob/d9cf3c15e3f9fdeaa1c3e608eaa2a3f21791697d/DRMD-6DOF/art/elites/citadel-enforcer.glb
[arc-blend]: https://github.com/terminaldetector/RayLight-/blob/d9cf3c15e3f9fdeaa1c3e608eaa2a3f21791697d/DRMD-6DOF/art/elites/arc-elite.blend
[arc-glb]: https://github.com/terminaldetector/RayLight-/blob/d9cf3c15e3f9fdeaa1c3e608eaa2a3f21791697d/DRMD-6DOF/art/elites/arc-elite.glb
[art-task]: https://github.com/terminaldetector/RayLight-/blob/d9cf3c15e3f9fdeaa1c3e608eaa2a3f21791697d/DRMD-6DOF/DRONE_ART_TASK_RU.md
[launcher-core]: https://github.com/terminaldetector/RayLight-/blob/d9cf3c15e3f9fdeaa1c3e608eaa2a3f21791697d/DRMD-6DOF/launcher/core.go
[support-test]: https://github.com/terminaldetector/RayLight-/blob/d9cf3c15e3f9fdeaa1c3e608eaa2a3f21791697d/DRMD-6DOF/tests/support_art_unit.lua
[view-test]: https://github.com/terminaldetector/RayLight-/blob/d9cf3c15e3f9fdeaa1c3e608eaa2a3f21791697d/DRMD-6DOF/tests/verify_mines_and_view.lua
[support-probe]: https://github.com/terminaldetector/RayLight-/blob/d9cf3c15e3f9fdeaa1c3e608eaa2a3f21791697d/DRMD-6DOF/tests/drmd_support_verify.lua
[cloud-test]: https://github.com/terminaldetector/RayLight-/blob/d9cf3c15e3f9fdeaa1c3e608eaa2a3f21791697d/DRMD-6DOF/tests/drmd_cloud_verify.lua
