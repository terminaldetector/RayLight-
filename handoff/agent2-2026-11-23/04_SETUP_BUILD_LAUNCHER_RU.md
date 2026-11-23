# Abaddon: окружение, подключение, сборка и Windows launcher

Срез для второго агента: **23.11.2026**. Документ сверён с кодом `main` на коммите **`d9cf3c15e3f9fdeaa1c3e608eaa2a3f21791697d`**. Команды ниже — инструкция для следующего рабочего окружения; при подготовке этого документа сборка и игровые тесты повторно не запускались.

## 1. Точная исходная точка

| Поле | Значение |
|---|---|
| Репозиторий | [terminaldetector/RayLight-](https://github.com/terminaldetector/RayLight-) |
| Закреплённые исходники | [`d9cf3c15e3f9fdeaa1c3e608eaa2a3f21791697d`](https://github.com/terminaldetector/RayLight-/tree/d9cf3c15e3f9fdeaa1c3e608eaa2a3f21791697d) |
| Готовый релиз | [abaddon-2026-11-22-ui-hotfix](https://github.com/terminaldetector/RayLight-/releases/tag/abaddon-2026-11-22-ui-hotfix) |
| Полный архив | `Half-Life-Abaddon-Full-Windows.zip` |
| Размер опубликованного полного архива | **71 574 974 байт** |
| SHA-256 опубликованного полного архива | `30080c375faed7c9464940a4de6fcfde723612d9494d1c2abd2096ca62c3358e` |

Полный ZIP содержит исходники, готовый payload, EXE, документы и необязательный SCK. Он не содержит установленную игру, Git-историю, Go/Python/Blender или компиляторы Source. Для запуска готовой сборки инструменты разработчика не нужны. Для повторной упаковки через `package_windows.py` нужен настоящий Git checkout: распакованного ZIP без `.git` недостаточно. [L1] [L3]

### Что считать актуальным при расхождении документов

1. Исходники закреплённого коммита и `abaddon-build.json` конкретной поставки задают фактическую реализацию и состав.
2. `ABADDON_QUICKFIX_2026-11-22_RU.md` уточняет меню, выдачу оружия/NPC, заднюю камеру и ширину креплений поверх предыдущей сборки.
3. `launcher/README_RU.md` описывает реально существующий EXE. Разделы с формулировкой «должен» в старом handoff нельзя принимать за список ещё не написанных функций: установка, обнаружение, запуск и rollback уже реализованы.
4. `GRANADA_SUPPORTS_RU.md` описывает реализованный платный G-цикл саппортов; `GRANADA_SUPPORT_AI_RESEARCH_RU.md` отделяет поведение оригинала от текущего прототипа и задаёт дальнейшее исследование. Предложения из исследования ещё не реализованы.
5. Старый `tests/RESULTS.txt` — исторический прогон предыдущего состояния. Он не доказывает новый визуальный результат UI-hotfix. Старое число «29 оружий» не является актуальным обычным арсеналом: сейчас в каталоге 12 систем. [L4] [L5] [L6]

Обе игровые ветки PR #1/PR #2 уже объединены. Отдельно накладывать их папки друг на друга не надо. Ветки `feat/abaddon-reactor` и `feat/abaddon-native-flight` не входят в этот срез; их дополнительные возможности нельзя обещать для данного релиза. [L2]

## 2. Два разных runtime

| Режим | Устанавливаемые данные | Реальная функция |
|---|---|---|
| **Garry’s Mod / `gmod`** | Весь `DRMD-6DOF/descent_scanner` → `<GMod>/garrysmod/addons/descent_scanner` | GLua: полёт 6DOF, оружие, саппорты, HUD, враги, арена, прогрессия и эпизод. |
| **Half-Life 2 / `hl2-content`** | Только `maps`, `models`, `materials` → `<HL2>/hl2/custom/drmd` | Карты и ресурсный контент штатного Source. GLua-полёт, AI, саппорты, HUD и бой из GMod здесь не исполняются. |

**`d6_profile campaign` — профиль внутри GMod**, включая смонтированные карты HL2. Это не переключение на настоящий клиент Half-Life 2. Отдельная native-flight ветка и Source SDK Base 2013 SP не являются скрытой третьей возможностью текущего EXE. [L1] [L2] [L7]

В payload данного коммита присутствуют **3 BSP, 3 VMF, 79 MDL и 8 VTF**. Пять саппортов дополнительно отрисовываются процедурно из GLua; отсутствие пяти отдельных support-MDL не мешает их текущей реализации в GMod. Совместимость этих BSP с реальным HL2-клиентом ещё нуждается в игровом прогоне. [L7] [L8] [L12]

## 3. Первый запуск готового пакета

На машине игрока нужны Windows x64 10/11, установленный выбранный Steam-клиент игры и доступ текущего пользователя на запись в его каталог. Лаунчер не требует Go, Python, .NET или WebView и не запрашивает повышение прав. [L1]

1. Скачать полный ZIP и при необходимости проверить SHA-256. Например, в PowerShell:

   ```powershell
   Get-FileHash -Algorithm SHA256 .\Half-Life-Abaddon-Full-Windows.zip
   ```

2. Распаковать **весь** архив. Запускать `Half-Life-Abaddon\AbaddonLauncher.exe` из обычной папки, где рядом находятся `abaddon-build.json` и `DRMD-6DOF`.
3. Выбрать GMod или HL2-content. Нажать «Найти игры», выбрать обнаруженную установку либо указать ручной путь.
4. Для арены выбрать `d6_relay_vault`, для начала эпизода — `d6_city17_drain`. Также доступны `d6_reactor_escape` и запуск меню без `+map`.
5. Выбрать разрешение/оконный режим и графический профиль. Начальное значение профиля — «Настройки игры — не менять».
6. Закрыть ранее запущенный GMod/HL2 и нажать «Установить и запустить». Сообщение о передаче команды означает запуск процесса/Steam; оно не подтверждает успешную загрузку игрового уровня.

EXE не является самораспаковывающимся установщиком: отдельный файл EXE без полного payload не заменяет ZIP. «Автозапуск» здесь означает обнаружение игры и передачу команды её запуска. Лаунчер не регистрирует себя в автозагрузке Windows. [L1] [L9]

### Как работают auto/manual detection

- Windows-обёртка читает Steam из HKCU/HKLM и проверяет стандартные Program Files как дополнительные кандидаты.
- Ядро разбирает современный и старый формат `libraryfolders.vdf`, в том числе дополнительные библиотеки. Нужны `appmanifest_4000.acf` для GMod или `appmanifest_220.acf` для HL2 и их `installdir`.
- Ручное поле принимает корень установки, каталог `garrysmod`/`hl2` или путь к EXE. Требуются `gameinfo.txt` и существующий непустой исполняемый файл: для GMod проверяются `bin/win64/gmod.exe`, `gmod.exe`, `hl2.exe`; для HL2 — `hl2.exe`.
- Ручная копия получает запуск через Steam только при совпадении с обнаруженной установкой того же target. Иначе используется EXE именно выбранной копии. Так установка в каталог A не запускает игру B.
- Через Steam используются `-applaunch 4000` или `-applaunch 220`; прямой запуск получает `-game garrysmod`/`-game hl2`. Для GMod задаётся `+gamemode sandbox`.
- Пути GMod и HL2 сохраняются отдельно. Проверки путей отвергают symlink/reparse-переходы; такой каталог не следует использовать как управляемую цель лаунчера.

Для выбранной карты кнопка «Запустить» требует её BSP в управляемом каталоге установки. Если пакет ещё не установлен, следует сначала установить его. Меню без карты допускается и без addon. [L9] [L10]

## 4. Установка, обновление, откат и удаление

| Операция | Что есть сейчас |
|---|---|
| Первая установка | «Только установить» либо «Установить и запустить» из распакованного полного пакета. |
| Обновление | Скачать новый полный ZIP, распаковать отдельно, открыть его EXE и установить в ту же подтверждённую игру. Это обновляет управляемый payload. |
| Запуск без установки | Кнопка «Запустить» использует уже установленную копию и выбранные параметры. |
| Откат | «Откатить установку» возвращает наиболее свежую сохранённую предыдущую копию; вытесненная текущая копия остаётся резервной. |
| Удаление | **Кнопки uninstall нет.** Отключение/удаление выполняется вручную по каталогам ниже. |
| Автоматическое скачивание обновлений | **Не реализовано.** Клиент не проверяет GitHub Releases и не скачивает патчи. |
| Управление Workshop-подписками | **Не реализовано.** Одновременно активную стороннюю копию пользователь отключает самостоятельно. |

Установщик проверяет manifest, размеры и SHA-256 до смены версии. Staging, резервные копии и журнал транзакции находятся в `<GameDir>/abaddon-launcher-state`, **вне** `addons`/`custom`. При обновлении сохраняются неизвестные прежнему manifest файлы, а старые управляемые файлы удаляются по собственному списку. Управляемый файл, вручную изменённый пользователем, при обновлении заменится версией пакета; прежняя копия каталога остаётся в backup. Это не механизм слияния исходников. [L10]

В случае прерванной транзакции программа останавливает следующую операцию и показывает путь к журналу/резерву. Не удалять `transaction.json`, lock или backup по общему совету «почистить всё»: восстановление зависит от фактической стадии, указанной в диагностике. Штатная ошибка второго переименования имеет отдельную попытку восстановления. [L10]

### Ручное отключение/удаление

Закрыть игру. Для обратимого отключения **переместить** нужный каталог в архивную папку вне любых путей монтирования:

- GMod: `<GMod>/garrysmod/addons/descent_scanner`.
- HL2-content: `<HL2>/hl2/custom/drmd`.
- Необязательный SCK: `<GMod>/garrysmod/addons/swep_construction_kit`, только если требуется убрать и редактор.

Переименование `descent_scanner` в `descent_scanner_old` внутри `addons` недостаточно: папка может остаться смонтированной. После проверки отключения архивную копию можно удалить вручную. Не затрагивать другие addon, сейвы или общие конфиги.

Это действие не очищает пользовательские данные в `garrysmod/data/`, параметры `%LOCALAPPDATA%\AbaddonLauncher` и резерв `abaddon-launcher-state`. Они сохраняются отдельно. Для полной ручной очистки проверять принадлежность каждого такого каталога; SCK-профили могут быть нужны и без Abaddon. Отдельный `cfg/abaddon_launcher.cfg` можно убрать, если он принадлежит лаунчеру и больше не используется. Общие `autoexec.cfg`/`config.cfg` и bind не являются файлами установщика. [L1] [L10] [L13]

## 5. Подключение аддона и SCK для разработки

### Рабочая копия исходников

В новом каталоге, без сброса существующей работы:

```sh
git clone https://github.com/terminaldetector/RayLight-.git RayLight-agent2
cd RayLight-agent2
git switch -c agent2/work d9cf3c15e3f9fdeaa1c3e608eaa2a3f21791697d
git rev-parse HEAD
git status --short
```

Ожидаемый HEAD — SHA из раздела 1, исходное рабочее дерево чистое. Для собственного продолжения новые изменения коммитятся в рабочую ветку; этот документ не требует merge, push или публикации.

Для запуска в тестовом GMod используется **папка payload**, а не весь репозиторий:

| Источник из checkout | Назначение |
|---|---|
| `DRMD-6DOF/descent_scanner/` | `<GMod>/garrysmod/addons/descent_scanner/` |
| `DRMD-6DOF/swep_construction_kit/` | `<GMod>/garrysmod/addons/swep_construction_kit/` |

У папки `descent_scanner` непосредственно внутри должны находиться `lua`, `maps`, `models`, `materials`, а не ещё один уровень `descent_scanner`. При первой ручной установке копировать в свободное назначение; при последующих заменах либо использовать полный пакет/лаунчер, либо заранее убирать прежнюю тестовую копию из монтируемых путей, чтобы не оставлять устаревшие файлы. Полёт/бой не требуют SCK. [L7]

**SCK входит в полный архив, но лаунчер его автоматически не устанавливает и не обновляет.** Рядом с аддоном нужна одна копия редактора. Для возможностей мастерской этого проекта ориентироваться на вложенный `swep_construction_kit`: произвольная Workshop-версия с тем же названием не гарантирует наличие расширений Clusters/Stats/Projectile/Flak/Guidance. [L1] [L13] [L14]

### Проверка загрузки и вход в инструменты

В Sandbox на `d6_relay_vault`:

```text
6dof_toggle
d6_menu_toggle
d6_bestiary
```

`6dof_toggle` — именно переключатель: не вызывать повторно, если полёт уже включён. Новая вкладка **Q → Abaddon** содержит оружие, 24 типа юнитов, пять саппортов и настройки обзора. Для испытания/забега использовать отдельно `d6_trial_start` либо `d6_rogue_start 38271`; запуск обоих одновременно не является проверкой базовой установки. Административные команды имеют штатные проверки владельца/администратора и режима. [L4] [L7]

Редактор оружия:

```text
give swep_construction_kit
```

Взять выданный SCK в руки. В разделе мастерской оружия Q-меню выбрать класс → «Загрузить в редактор SCK» → изменить Clusters → «Применить кластеры SCK → выбранный класс». Если кнопка сначала выдала SCK, взять его и повторить загрузку. Применение визуального override требует администратора или хозяина локальной игры и распространяется сервером всем игрокам. Для возврата штатного вида есть «Сбросить переопределение выбранного класса». [L13] [L14]

Данные разделены:

- SCK-пресеты: `garrysmod/data/swep_construction_kit/`.
- Конфигурации механики SCK: `garrysmod/data/drmd_weapons/<class>.txt`.
- Серверный визуальный override: `garrysmod/data/drmd_weapons/visual/<class>.txt`.

Bridge меняет внешний вид и точки дул существующего класса; сохранение пресета не является автоматическим коммитом Lua-файла в репозиторий. `D6_Wep.Cfg()` предоставляет opt-in чтение параметров из SCK: оружие должно реально обращаться к этому API. Старые захардкоженные значения не становятся автоматически live-tunable только от наличия SCK. Генерация нового SWEP и редактирование внешнего вида существующего — разные операции. [L13] [L14]

После смены аддона/каталогов перезапускать карту или игру. Старые уже созданные боевые сущности не обязаны мигрировать через hot reload. [L7]

## 6. Go, EXE и полный пакет

### Минимальные инструменты

| Задача | Инструменты |
|---|---|
| Использовать готовый ZIP | Windows x64 и установленный клиент игры. |
| Собирать EXE | Go; `launcher/go.mod` объявляет Go 1.22, проверенный workflow использует **Go 1.27.4**. Только standard library. |
| Упаковать полный ZIP | Git checkout, Python 3 standard library, Go. |
| Выполнить Lua fixtures / экспорт геометрии | `texlua`, как в инструкциях проекта. Произвольная замена на другой Lua runtime отдельно не подтверждена этим документом. |
| Создать/собрать модели и карты | Внешние Source tools; для отдельных генераторов дополнительные зависимости из раздела 7. |

### Только EXE, Windows PowerShell

Из корня checkout:

```powershell
$AbaddonOut = [System.IO.Path]::GetFullPath("..\abaddon-build")
New-Item -ItemType Directory -Force -Path $AbaddonOut | Out-Null
Set-Location .\DRMD-6DOF\launcher
go test ./...
$env:GOOS = 'windows'
$env:GOARCH = 'amd64'
$env:CGO_ENABLED = '0'
go build -trimpath '-ldflags=-H=windowsgui -s -w' -o "$AbaddonOut\AbaddonLauncher.exe" .
```

Из этого каталога вернуться в корень checkout командой `Set-Location ..\..` перед следующей операцией. Новый EXE сам по себе не содержит игровой payload. [L1] [L9]

Linux/macOS cross-build из каталога `DRMD-6DOF/launcher`:

```sh
go test ./...
GOOS=windows GOARCH=amd64 CGO_ENABLED=0 go build -trimpath -ldflags="-H=windowsgui -s -w" -o /absolute/path/abaddon-build/AbaddonLauncher.exe .
```

Родительская папка вывода должна существовать. Проверка окна возможна только в Windows:

```powershell
& "$AbaddonOut\AbaddonLauncher.exe" --smoke-ui
```

Smoke создаёт/проверяет окно и закрывает его; операции установки, отката и запуска игры отключены, настройки изолированы. Это не прохождение установки и не GMod-тест. [L2] [L11]

### Полный ZIP

Из корня **чистого** checkout:

```sh
git status --short
python3 DRMD-6DOF/tools/package_windows.py --go go --out ../abaddon-build
```

В Windows с Python Launcher эквивалентно:

```powershell
git status --short
py -3 .\DRMD-6DOF\tools\package_windows.py --go go --out ..\abaddon-build
```

Вместо `go` можно передать полный путь к нужному toolchain. Упаковщик отказывается от dirty tree, включая обычные untracked-файлы, затем копирует **все Git-tracked файлы**, собирает Windows/amd64 EXE и создаёт:

- внутри `Half-Life-Abaddon/`: EXE, весь tracked source/payload, `abaddon-build.json`, `BUILD_INFO.json`, `START_HERE_RU.md`, `SHA256SUMS`;
- рядом с ZIP: `AbaddonLauncher.exe`, `ABADDON_WINDOWS_LAUNCHER_HANDOFF.md`, `abaddon-build.json`, `SHA256SUMS.txt`.

Manifest перечисляет именно файлы `DRMD-6DOF/descent_scanner`, а не весь архив и не SCK. `BUILD_INFO.json` записывает текущую revision, версию Go, `gmod=addon`, `hl2=content-only`, `pbr=not-implemented` и отсутствие игрового прогона этой интеграции. Выход держать вне checkout. [L3]

**Различие локального packager и опубликованного релиза:** сам `package_windows.py` создаёт пять внешних файлов, считая ZIP и checksum. Два новых MD находятся внутри полного ZIP, потому что tracked. Одноразовая процедура публикации дополнительно вынесла `ABADDON_QUICKFIX_2026-11-22_RU.md` и `GRANADA_SUPPORT_AI_RESEARCH_RU.md` наружу и пересчитала checksum: поэтому у релиза семь вложений. Не считать отсутствие этих двух отдельных копий после локальной упаковки потерей документации внутри ZIP.

Повторная упаковка должна указывать правильную revision и содержимое, но побайтовое совпадение нового ZIP с опубликованным здесь не обещано: архив сохраняет временные метки файлов, а `BUILD_INFO.json` отражает реально использованный toolchain. SHA в разделе 1 относится к опубликованному файлу.

## 7. Модели, материалы и карты: какие команды действительно есть

Готовые MDL/BSP уже включены; пересобирать их для запуска текущего аддона не требуется. В репозитории находятся генераторы и wrappers, **но нет поставки исполняемых StudioMDL++/VBSP++/VVIS++/VRAD++**. `modeltools` ниже — выбранная агентом внешняя папка инструментов, а не существующий каталог проекта. [L8] [L12]

### Экспорт GLua-геометрии

```sh
cd DRMD-6DOF/tests
texlua export_art.lua
```

Результат — `DRMD-6DOF/tests/art-models.json`. Экспорт включает `d6_support_art.lua`. Файл генерируется в рабочей папке: после использования перенести его во внешний каталог сборки, иначе packager увидит untracked-файл и откажется упаковывать HEAD. Не включать автоматически в коммит случайные результаты генерации. [L12]

### Source MDL

CLI из корня репозитория:

```text
python3 DRMD-6DOF/tools/compile_models.py GEOMETRY_JSON STUDIOMDL_EXECUTABLE GAME_DIRECTORY
```

Пример для PowerShell; пути заменить на существующие локальные:

```powershell
$AbaddonModelTools = 'C:\Tools\modeltools'
$AbaddonTestGame = 'D:\AbaddonTest\garrysmod'
py -3 .\DRMD-6DOF\tools\compile_models.py `
  ..\abaddon-build\art-models.json `
  "$AbaddonModelTools\studiomdl.exe" `
  $AbaddonTestGame
```

`GAME_DIRECTORY` — отдельная тестовая Source game-directory с подходящим `gameinfo.txt`; одного произвольного пустого каталога недостаточно для нормальной конфигурации Source compiler. Исполняемый файл компилятора должен запускаться в текущей ОС: wrapper сам не подключает Wine.

Скрипт создаёт временные SMD/QC и вызывает компилятор как `studiomdl -game GAME QC`. Он **пишет** `materials/models/drmd/*.vmt` и `models/drmd/*` в переданный game-directory. Использовать тестовую установку/подготовленный build game, затем осознанно переносить нужные результаты в payload. Компилируются все модели JSON; экспорт с новыми саппортами может расширить прежний набор из 79 MDL, хотя эти дополнительные MDL не нужны текущему GLua-рендеру. Скрипт не переносит автоматически результат назад в `descent_scanner`. [L12]

### Blender и покрытия элит

Для `build_elite_finishes.py` нужны NumPy и Pillow; для `build_elite_studio.py` — Blender с Python API. Вложенные `.blend` подготовлены для Blender 4.3. Для генератора карт нужен `srctools`. Репозиторий не фиксирует версии этих Python-пакетов отдельным lockfile; при новом воспроизводимом арт-проходе записать фактические версии. Установка этих зависимостей не нужна packager. [L8] [L15]

Из `DRMD-6DOF`, с внешними каталогами результатов:

```sh
python3 tools/build_elite_finishes.py /absolute/path/abaddon-build/materials/drmd /absolute/path/abaddon-build/textures
blender -b -P tools/build_elite_studio.py -- /absolute/path/abaddon-build/art-models.json /absolute/path/abaddon-build/textures /absolute/path/abaddon-build/studio --render
```

Первый скрипт генерирует VTF albedo и отдельные PNG для Blender; наличие roughness/normal в студийной сцене **не делает игровой рендер PBR**. GLB/BLEND — рабочие художественные форматы, не непосредственно исполняемый формат модели GMod. [L15]

### VMF/BSP

Генератор создаёт три VMF; для сохранения ручных правок Hammer сначала выводить в отдельную папку:

```sh
python3 DRMD-6DOF/tools/build_episode.py /absolute/path/abaddon-build/maps --preview-data /absolute/path/abaddon-build/maps-preview.json
```

Для существующего отредактированного VMF генератор запускать не нужно. Сборка каждой карты проходит VBSP → VVIS → VRAD. Пример PowerShell для одной арены, с теми же внешними tools и тестовым game-directory:

```powershell
$AbaddonMap = 'D:\AbaddonBuild\maps\d6_relay_vault'
& "$AbaddonModelTools\vbsp.exe" -game $AbaddonTestGame "$AbaddonMap.vmf"
& "$AbaddonModelTools\vvis.exe" -game $AbaddonTestGame "$AbaddonMap.bsp"
& "$AbaddonModelTools\vrad.exe" -game $AbaddonTestGame "$AbaddonMap.bsp"
```

Перед следующим этапом убедиться, что предыдущий завершился успешно. Повторить для `d6_city17_drain`/`d6_reactor_escape` только при их изменении. Текущая поставка собрана с LDR; HDR и локальные cubemap samples этими документами не заявлены. После сборки проверить материалы/модели и только затем переносить BSP в payload. [L8]

## 8. Проверки: команды, известный результат и предел доказательства

### Семь исходных Lua fixtures

Все команды выполняются из `DRMD-6DOF/tests`:

```sh
texlua actors_unit.lua
texlua weapon_feed_unit.lua
texlua arsenal_progression_unit.lua
texlua verify_mines_and_view.lua
texlua supports_unit.lua
texlua support_projectiles_unit.lua
texlua support_art_unit.lua
```

Документированный результат интеграции PR #1/#2 — **326 checks**: 22 + 36 + 32 + 62 + 72 + 35 + 67. Это настоящие модули Lua с подменёнными границами движка, а не запуск игры. Для изменения одного механизма выбирать соответствующие проверки; полный повтор нужен только при затронутом общем контракте. [L2] [L5] [L6]

UI fixtures и экспорт:

```sh
texlua replay_ui.lua 640 480 supports
texlua replay_ui.lua 640 480 support_cockpit
texlua replay_ui.lua 1600 900 hangar
texlua export_art.lua
```

`replay_ui.lua` воспроизводит команды отрисовки на тестовых состояниях. Сценарии не являются новыми скриншотами из GMod. Экспорт геометрии также не проверяет тени в движке. [L6]

### Что документировано для UI-hotfix

`ABADDON_QUICKFIX_2026-11-22_RU.md` фиксирует 62 проверки мин/ввода/проекции, 19 проверок маршрута NPC и 64 проверки выдачи оружия/меню. Число 62 повторяет соответствующий существующий fixture; его не нужно складывать с исходными 326 как новую независимую группу. Отдельные временные harness для 19/64 не включены в `DRMD-6DOF/tests` этого SHA, поэтому не приводим несуществующие команды их запуска. [L4]

### Launcher

`go test ./...` проверяет установку, обнаружение, manifest/пути, повреждённый source, сохранение неизвестных файлов, удаление устаревших управляемых файлов, HL2 filtering, rollback, блокировки и параметры запуска. Документированный Windows CI: [run 44942885052](https://github.com/terminaldetector/RayLight-/actions/runs/44942885052), commit `2a97e14b93d7c8bac5ef91eaa80649c92ccb0d2a`: тесты, native build и реальное создание/закрытие Win32-окна прошли. Это результат прежнего launcher-среза; UI-hotfix игровой Lua не менял EXE/установочный протокол. Не переименовывать тот run в новый прогон на `d9cf...`. [L2] [L4] [L11]

### Настоящий GMod

Для точечной диагностики саппортов скопировать `DRMD-6DOF/tests/drmd_support_verify.lua` в `garrysmod/lua/` отдельной тестовой установки:

```text
lua_openscript drmd_support_verify.lua
d6_support_verify
lua_openscript_cl drmd_support_verify.lua
d6_support_verify_client
```

Серверные и клиентские команды выполняются в соответствующем контексте разработчика после загрузки карты и включения полёта. Этот скрипт читает сцену и не выдаёт ресурсы/не вызывает атаки. Для полного сценического прогона существуют `drmd_cloud_verify.lua` и `drmd_episode_verify.lua`: ставить их отдельным временным тестовым addon, не в производственную автозагрузку. Они меняют тестовую сцену/профиль. Подробный маршрут — `tests/ПРОВЕРКА.md`. [L6]

После кодового изменения также выполнить `git diff --check`. Ни успешная компиляция EXE, ни checksum ZIP не заменяют проверку карты, звука, управления и сети в игре.

## 9. Материальные ограничения текущего результата

- **Игровой графический runtime данного UI-hotfix не проверен.** Требуется открыть Q-меню, проверить карточки и выдачу, полёт, задний обзор и положение пушек в GMod.
- **PBR не реализован.** GUI предлагает только `default`, `balanced`, `high`; внутренний core содержит ещё `low`, но в текущем UI выбора low нет. Профили включают штатные Source-тени/фильтрацию; они не меняют шейдер процедурного корпуса и не добавляют отсутствующие карты материалов. [L1] [L9] [L10]
- `default` означает «не применять профиль на этом запуске», а не вернуть значения до предыдущего запуска. Отдельный CFG — `cfg/abaddon_launcher.cfg`; движок может сохранить ConVar при выходе. Rollback payload не откатывает персональную графику. [L1] [L10]
- Процедурные корпуса используют `UnlitGeneric` с упрощённой реакцией на свет; совпадение видимого силуэта и реальных теней нужно проверить отдельно. Переставить флажок в EXE недостаточно. [L2]
- Четыре видимых крепления не означают завершённые четыре независимых канала огня; совмещение экранных дул/эффектов и часть боевых задач остаются в плане. [L2] [L7]
- Новые автономные циклы саппортов и персональные циклы мобов из Granada-исследования ещё не добавлены. Текущий hotfix меняет доступность и представление контента, а не переписывает AI. [L4]

Ближайшая техническая работа второго агента: использовать закреплённый срез, подключить одну копию addon и при необходимости SCK, открыть воспроизводимую сцену, затем менять назначенный механизм и проверять именно его. Лаунчер, модельный pipeline и AI имеют разные зоны ответственности; не смешивать изменение баланса с установочным кодом.

## Источники: точные пути на закреплённом SHA

Ссылки ниже указывают на `d9cf3c15e3f9fdeaa1c3e608eaa2a3f21791697d`, а не на подвижный `main`.

- [L1] `DRMD-6DOF/launcher/README_RU.md` — использование готового EXE, SCK, профили и сборка.
- [L2] `DRMD-6DOF/WINDOWS_LAUNCHER_HANDOFF_RU.md` — объединённые ветки, границы runtime, renderer и подтверждённый CI.
- [L3] `DRMD-6DOF/tools/package_windows.py` — точный состав локальной упаковки.
- [L4] `DRMD-6DOF/ABADDON_QUICKFIX_2026-11-22_RU.md` — текущие UI-правки и проверки.
- [L5] `DRMD-6DOF/GRANADA_SUPPORTS_RU.md` — реализованный цикл саппортов и исходные 326 checks.
- [L6] `DRMD-6DOF/tests/ПРОВЕРКА.md` — Lua/UI/движковые сценарии.
- [L7] `DRMD-6DOF/INSTALL_RU.md` — установка, команды, арена/эпизод и campaign-профиль GMod.
- [L8] `DRMD-6DOF/MAPS_RU.md`, `DRMD-6DOF/tools/build_episode.py` — карты, генератор и Source tools.
- [L9] `DRMD-6DOF/launcher/main_windows.go` — реальные GUI-опции, обнаружение Steam, запускаемые операции.
- [L10] `DRMD-6DOF/launcher/core.go` — target validation, установка, rollback, CFG и launch args.
- [L11] `.github/workflows/abaddon-windows.yml` — версия Go, тесты, native build и Win32 smoke.
- [L12] `DRMD-6DOF/tests/export_art.lua`, `DRMD-6DOF/tools/compile_models.py` — экспорт/компиляция моделей.
- [L13] `DRMD-6DOF/descent_scanner/lua/autorun/d6_sck_bridge.lua`, `d6_weaponworkshop.lua`, `d6_wep_cfg.lua` — подключение SCK и реальные зоны влияния.
- [L14] `DRMD-6DOF/WEAPON_WORKSHOP_README.md`, `DRMD-6DOF/swep_construction_kit/lua/weapons/swep_construction_kit/config.lua` — редактор и DATA-конфиги.
- [L15] `DRMD-6DOF/art/elites/README.md`, `DRMD-6DOF/tools/build_elite_finishes.py`, `build_elite_studio.py` — Blender/GLB и покрытия.

[L1]: https://github.com/terminaldetector/RayLight-/blob/d9cf3c15e3f9fdeaa1c3e608eaa2a3f21791697d/DRMD-6DOF/launcher/README_RU.md
[L2]: https://github.com/terminaldetector/RayLight-/blob/d9cf3c15e3f9fdeaa1c3e608eaa2a3f21791697d/DRMD-6DOF/WINDOWS_LAUNCHER_HANDOFF_RU.md
[L3]: https://github.com/terminaldetector/RayLight-/blob/d9cf3c15e3f9fdeaa1c3e608eaa2a3f21791697d/DRMD-6DOF/tools/package_windows.py
[L4]: https://github.com/terminaldetector/RayLight-/blob/d9cf3c15e3f9fdeaa1c3e608eaa2a3f21791697d/DRMD-6DOF/ABADDON_QUICKFIX_2026-11-22_RU.md
[L5]: https://github.com/terminaldetector/RayLight-/blob/d9cf3c15e3f9fdeaa1c3e608eaa2a3f21791697d/DRMD-6DOF/GRANADA_SUPPORTS_RU.md
[L6]: https://github.com/terminaldetector/RayLight-/blob/d9cf3c15e3f9fdeaa1c3e608eaa2a3f21791697d/DRMD-6DOF/tests/ПРОВЕРКА.md
[L7]: https://github.com/terminaldetector/RayLight-/blob/d9cf3c15e3f9fdeaa1c3e608eaa2a3f21791697d/DRMD-6DOF/INSTALL_RU.md
[L8]: https://github.com/terminaldetector/RayLight-/blob/d9cf3c15e3f9fdeaa1c3e608eaa2a3f21791697d/DRMD-6DOF/MAPS_RU.md
[L9]: https://github.com/terminaldetector/RayLight-/blob/d9cf3c15e3f9fdeaa1c3e608eaa2a3f21791697d/DRMD-6DOF/launcher/main_windows.go
[L10]: https://github.com/terminaldetector/RayLight-/blob/d9cf3c15e3f9fdeaa1c3e608eaa2a3f21791697d/DRMD-6DOF/launcher/core.go
[L11]: https://github.com/terminaldetector/RayLight-/blob/d9cf3c15e3f9fdeaa1c3e608eaa2a3f21791697d/.github/workflows/abaddon-windows.yml
[L12]: https://github.com/terminaldetector/RayLight-/blob/d9cf3c15e3f9fdeaa1c3e608eaa2a3f21791697d/DRMD-6DOF/tools/compile_models.py
[L13]: https://github.com/terminaldetector/RayLight-/blob/d9cf3c15e3f9fdeaa1c3e608eaa2a3f21791697d/DRMD-6DOF/descent_scanner/lua/autorun/d6_sck_bridge.lua
[L14]: https://github.com/terminaldetector/RayLight-/blob/d9cf3c15e3f9fdeaa1c3e608eaa2a3f21791697d/DRMD-6DOF/WEAPON_WORKSHOP_README.md
[L15]: https://github.com/terminaldetector/RayLight-/blob/d9cf3c15e3f9fdeaa1c3e608eaa2a3f21791697d/DRMD-6DOF/art/elites/README.md
