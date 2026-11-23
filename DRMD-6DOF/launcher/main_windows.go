package main

import (
	"fmt"
	"math"
	"os"
	"path/filepath"
	"runtime"
	"strconv"
	"strings"
	"unsafe"

	"abaddon/launcher/core"
)

const (
	canvasWidth  = 832
	canvasHeight = 579

	idGMod = 100 + iota
	idContent
	idHL2
	idSteam
	idSteamBrowse
	idGame
	idGameBrowse
	idNative
	idNativeBrowse
	idDisplay
	idWidth
	idHeight
	idMap
	idProfile
	idConsole
	idIntro
	idLog
	idDetect
	idInstall
	idRollback
	idSave
	idLaunch
)

var (
	app             *launcher
	wndProcCallback = syscallWindowProc()
	toneBackground  = color(17, 23, 29)
	tonePanel       = color(27, 36, 44)
	toneField       = color(18, 26, 32)
	toneEdge        = color(59, 77, 88)
	toneText        = color(231, 240, 243)
	toneMuted       = color(170, 186, 194)
	toneAccent      = color(118, 225, 214)
	toneNote        = color(253, 188, 133)
)

type choice struct{ label, value string }

var displays = []choice{
	{"В окне", "windowed"},
	{"На весь экран", "fullscreen"},
	{"Без рамки", "borderless"},
}
var profiles = []choice{
	{"Автоматический", "auto"},
	{"Кампания", "campaign"},
	{"Арена", "arena"},
}
var gmodMaps = []string{
	"d6_city17_drain", "d6_reactor_escape", "d6_rogue_reactor",
	"d6_relay_vault", "gm_flatgrass",
}
var sourceMaps = []string{"d6_native_flightlab"}
var contentMaps = []string{"d6_city17_drain", "d6_reactor_escape"}

type jobResult struct {
	cfg      core.Config
	detected core.Detection
	builds   map[core.Profile]core.BuildInfo
	start    bool
	note     string
	err      error
}

type launcher struct {
	window, instance                                     uintptr
	controls                                             map[int]uintptr
	checkbox                                             map[int]bool
	scale                                                float64
	regular, heading, title, caption                     uintptr
	background, panel, field, edge, button, activeButton uintptr
	titleLabel, captionLabel, engineLabel, nativeLabel   uintptr
	profileLabel, statusLabel, buildLabel                uintptr
	statusInk                                            uintptr
	cfg                                                  core.Config
	detection                                            core.Detection
	builds                                               map[core.Profile]core.BuildInfo
	busy, updating                                       bool
	result                                               chan jobResult
}

func main() {
	runtime.LockOSThread()
	defer runtime.UnlockOSThread()
	if err := run(len(os.Args) == 2 && os.Args[1] == "--self-test-ui"); err != nil {
		if len(os.Args) == 2 && os.Args[1] == "--self-test-ui" {
			fmt.Fprintln(os.Stderr, err)
		} else {
			windowTitle(0, err.Error())
		}
		os.Exit(1)
	}
}

func run(smoke bool) error {
	procSetDPIAware.Call()
	instance, _, _ := procModule.Call(0)
	cursor, _, _ := procLoadCursor.Call(0, 32512)
	icon, _, _ := procLoadIcon.Call(0, 32512)
	name := utf("AbaddonNativeLauncher")
	class := windowClass{
		size: uint32(unsafe.Sizeof(windowClass{})), callback: wndProcCallback,
		instance: instance, icon: icon, smallIcon: icon, cursor: cursor, name: name,
	}
	atom, _, err := procRegisterClass.Call(uintptr(unsafe.Pointer(&class)))
	if atom == 0 {
		return fmt.Errorf("Не удалось зарегистрировать окно лаунчера. %v", err)
	}

	cfg := core.DefaultConfig()
	var loadErr error
	if !smoke {
		cfg, loadErr = core.LoadConfig()
		if loadErr != nil {
			cfg = core.DefaultConfig()
		}
	}
	a := &launcher{
		instance: instance, cfg: cfg, controls: make(map[int]uintptr),
		checkbox: make(map[int]bool), result: make(chan jobResult, 1),
	}
	app = a
	defer func() { app = nil }()
	work := rect{Right: 1280, Bottom: 760}
	procSysParams.Call(0x0030, 0, uintptr(unsafe.Pointer(&work)), 0)
	a.scale = 1
	if procSystemDPI.Find() == nil {
		dpi, _, _ := procSystemDPI.Call()
		if dpi != 0 {
			a.scale = float64(dpi) / 96
		}
	}
	a.scale = math.Min(a.scale, math.Min(
		float64(work.Right-work.Left-20)/canvasWidth,
		float64(work.Bottom-work.Top-54)/canvasHeight))
	if a.scale <= 0 {
		a.scale = 1
	}
	frame := rect{Right: a.px(canvasWidth), Bottom: a.px(canvasHeight)}
	const style = wsCaption | wsSysMenu | wsMinimizeBox | wsClipChildren
	const extendedStyle = wsExControlParent
	procAdjustRect.Call(uintptr(unsafe.Pointer(&frame)), style, 0, extendedStyle)
	width, height := frame.Right-frame.Left, frame.Bottom-frame.Top
	x, y := (work.Left+work.Right-width)/2, (work.Top+work.Bottom-height)/2
	window, _, err := procCreateWindow.Call(extendedStyle, uintptr(unsafe.Pointer(name)),
		uintptr(unsafe.Pointer(utf("Half-Life: Abaddon — лаунчер"))), style,
		uintptr(x), uintptr(y), uintptr(width), uintptr(height), 0, 0, instance, 0)
	if window == 0 {
		return fmt.Errorf("Не удалось открыть окно лаунчера. %v", err)
	}
	a.window = window
	defer a.release()
	defer procDestroyWindow.Call(window)
	a.initialize()
	if smoke {
		return a.smoke()
	}
	show(window, true)
	procFocus.Call(a.controls[idLaunch])
	a.detect()
	if loadErr != nil {
		a.status("Сохранённые настройки не прочитались. Загружены значения по умолчанию.", toneNote)
	}
	var msg message
	for {
		result, _, err := procGetMessage.Call(uintptr(unsafe.Pointer(&msg)), 0, 0, 0)
		switch int32(result) {
		case -1:
			return fmt.Errorf("Ошибка обработки окна лаунчера. %v", err)
		case 0:
			return nil
		}
		handled, _, _ := procDialogMessage.Call(window, uintptr(unsafe.Pointer(&msg)))
		if handled == 0 {
			procTranslate.Call(uintptr(unsafe.Pointer(&msg)))
			procDispatch.Call(uintptr(unsafe.Pointer(&msg)))
		}
	}
}

func (a *launcher) px(value int) int32 { return int32(math.Round(float64(value) * a.scale)) }
func (a *launcher) box(x, y, width, height int) rect {
	return rect{a.px(x), a.px(y), a.px(x + width), a.px(y + height)}
}
func (a *launcher) child(class, title string, id, x, y, width, height int,
	flags, extendedStyle, typeface uintptr) uintptr {
	handle, _, _ := procCreateWindow.Call(extendedStyle,
		uintptr(unsafe.Pointer(utf(class))), uintptr(unsafe.Pointer(utf(title))),
		wsChild|wsVisible|flags, uintptr(a.px(x)), uintptr(a.px(y)),
		uintptr(a.px(width)), uintptr(a.px(height)), a.window, uintptr(id), a.instance, 0)
	if id != 0 {
		a.controls[id] = handle
	}
	send(handle, wmSetFont, typeface, 1)
	return handle
}
func (a *launcher) label(title string, x, y, width, height int, typeface uintptr) uintptr {
	return a.child("STATIC", title, 0, x, y, width, height, 0, 0, typeface)
}
func (a *launcher) buttonControl(title string, id, x, y, width, height int) uintptr {
	return a.child("BUTTON", title, id, x, y, width, height,
		bsOwnerDraw|wsTabStop, 0, a.regular)
}
func (a *launcher) edit(id, x, y, width, height int, number bool) uintptr {
	flags, limit := uintptr(wsTabStop|esAutoHScroll), uintptr(32767)
	if number {
		flags, limit = flags|esNumber, 5
	}
	handle := a.child("EDIT", "", id, x, y, width, height, flags, wsExClientEdge, a.regular)
	send(handle, emSetLimitText, limit, 0)
	return handle
}
func (a *launcher) combo(id, x, y, width int, editable bool) uintptr {
	flags := uintptr(wsTabStop | wsVScroll | cbsDropDownList)
	if editable {
		flags = wsTabStop | wsVScroll | cbsDropDown | cbsAutoHScroll
	}
	handle := a.child("COMBOBOX", "", id, x, y, width, 184, flags, 0, a.regular)
	procCtlTheme.Call(handle, uintptr(unsafe.Pointer(utf("DarkMode_Explorer"))), 0)
	return handle
}
func (a *launcher) setOptions(id int, options []choice) {
	handle := a.controls[id]
	send(handle, cbResetContent, 0, 0)
	for _, option := range options {
		sendText(handle, cbAddString, 0, option.label)
	}
}
func (a *launcher) pick(id int, options []choice, value string) {
	for i, option := range options {
		if option.value == value {
			send(a.controls[id], cbSetCurSel, uintptr(i), 0)
			return
		}
	}
	send(a.controls[id], cbSetCurSel, 0, 0)
}
func (a *launcher) value(id int, options []choice) string {
	i := send(a.controls[id], cbGetCurSel, 0, 0)
	if i >= uintptr(len(options)) {
		return options[0].value
	}
	return options[i].value
}

func (a *launcher) initialize() {
	a.regular, a.heading = font(a.px(14), 400), font(a.px(18), 600)
	a.title, a.caption = font(a.px(31), 600), font(a.px(13), 400)
	a.background, a.panel, a.field = brush(toneBackground), brush(tonePanel), brush(toneField)
	a.edge = brush(toneEdge)
	a.button, a.activeButton = brush(color(37, 51, 61)), brush(toneAccent)
	a.titleLabel = a.label("Half-Life: Abaddon", 26, 21, 560, 44, a.title)

	a.buttonControl("Garry’s Mod", idGMod, 26, 82, 178, 35)
	a.buttonControl("HL2 · карты", idContent, 212, 82, 178, 35)
	a.buttonControl("HL2 · Flight Lab", idHL2, 398, 82, 178, 35)

	a.label("Пути к игре", 44, 145, 331, 26, a.heading)
	a.captionLabel = a.label("Пустое поле использует автопоиск Steam.", 44, 173, 355, 20, a.caption)
	a.label("Steam", 44, 210, 314, 19, a.regular)
	a.edit(idSteam, 44, 231, 332, 29, false)
	a.buttonControl("…", idSteamBrowse, 384, 231, 34, 29)
	a.engineLabel = a.label("", 44, 276, 314, 19, a.regular)
	a.edit(idGame, 44, 297, 332, 29, false)
	a.buttonControl("…", idGameBrowse, 384, 297, 34, 29)
	a.nativeLabel = a.label("Папка мода abaddon_native", 44, 342, 314, 19, a.regular)
	a.edit(idNative, 44, 363, 332, 29, false)
	a.buttonControl("…", idNativeBrowse, 384, 363, 34, 29)

	a.label("Параметры запуска", 474, 145, 310, 26, a.heading)
	a.label("Режим экрана", 474, 184, 140, 19, a.regular)
	a.label("Разрешение", 624, 184, 164, 19, a.regular)
	a.combo(idDisplay, 474, 206, 140, false)
	a.edit(idWidth, 624, 206, 67, 28, true)
	a.label("×", 695, 210, 13, 19, a.regular)
	a.edit(idHeight, 712, 206, 77, 28, true)
	a.label("Карта", 474, 248, 311, 19, a.regular)
	a.combo(idMap, 474, 270, 315, true)

	a.profileLabel = a.label("Профиль аддона", 474, 310, 315, 19, a.regular)
	a.combo(idProfile, 474, 332, 315, false)
	a.buttonControl("Консоль", idConsole, 474, 376, 94, 28)
	a.buttonControl("Без роликов", idIntro, 575, 376, 108, 28)
	a.buttonControl("Журнал", idLog, 690, 376, 99, 28)

	a.statusLabel = a.label("", 44, 446, 745, 40, a.regular)
	a.buildLabel = a.label("", 44, 489, 745, 22, a.caption)
	a.buttonControl("Найти автоматически", idDetect, 26, 527, 185, 33)
	a.buttonControl("Установить пакет…", idInstall, 219, 527, 154, 33)
	a.buttonControl("Откатить", idRollback, 381, 527, 91, 33)
	a.buttonControl("Сохранить", idSave, 550, 527, 115, 33)
	a.buttonControl("Запустить", idLaunch, 673, 527, 133, 33)

	a.setOptions(idDisplay, displays)
	a.setOptions(idProfile, profiles)
	a.setForm()
}

func (a *launcher) release() {
	for _, object := range []uintptr{a.regular, a.heading, a.title, a.caption,
		a.background, a.panel, a.field, a.edge, a.button, a.activeButton} {
		if object != 0 {
			procDelete.Call(object)
		}
	}
}

func (a *launcher) activeOptions() *core.Options {
	switch a.cfg.Selected {
	case core.HL2:
		return &a.cfg.HL2
	case core.HL2Content:
		return &a.cfg.HL2Content
	default:
		return &a.cfg.GMod
	}
}

func (a *launcher) setForm() {
	a.updating = true
	defer func() { a.updating = false }()
	options := a.activeOptions()
	hl2 := a.cfg.Selected == core.HL2
	setText(a.controls[idSteam], a.cfg.SteamPath)
	maps, gamePath, label := gmodMaps, a.cfg.GModPath, "Папка Garry’s Mod"
	if hl2 {
		maps, gamePath, label = sourceMaps, a.cfg.SDKPath, "Папка Source SDK Base 2013"
	} else if a.cfg.Selected == core.HL2Content {
		maps, gamePath, label = contentMaps, a.cfg.ContentPath, "Папка Half-Life 2 · App 220"
	}
	setText(a.engineLabel, label)
	setText(a.controls[idGame], gamePath)
	setText(a.controls[idNative], a.cfg.NativePath)
	for _, widget := range []uintptr{a.nativeLabel, a.controls[idNative], a.controls[idNativeBrowse]} {
		show(widget, hl2)
	}
	show(a.profileLabel, a.cfg.Selected == core.GMod)
	show(a.controls[idProfile], a.cfg.Selected == core.GMod)
	show(a.controls[idInstall], !hl2)
	show(a.controls[idRollback], !hl2)
	for _, id := range []int{idGMod, idContent, idHL2} {
		repaint(a.controls[id])
	}
	mapList := a.controls[idMap]
	send(mapList, cbResetContent, 0, 0)
	for _, mapName := range maps {
		sendText(mapList, cbAddString, 0, mapName)
	}
	setText(mapList, options.Map)
	a.pick(idDisplay, displays, options.Display)
	a.pick(idProfile, profiles, options.GameProfile)
	setText(a.controls[idWidth], strconv.Itoa(options.Width))
	setText(a.controls[idHeight], strconv.Itoa(options.Height))
	a.checkbox[idConsole] = options.Console
	a.checkbox[idIntro] = options.SkipIntro
	a.checkbox[idLog] = options.DebugLog
	for _, id := range []int{idConsole, idIntro, idLog} {
		repaint(a.controls[id])
	}
	a.updateDetection()
}

func (a *launcher) readPaths() {
	a.cfg.SteamPath = strings.TrimSpace(getText(a.controls[idSteam]))
	path := strings.TrimSpace(getText(a.controls[idGame]))
	switch a.cfg.Selected {
	case core.HL2:
		a.cfg.SDKPath = path
		a.cfg.NativePath = strings.TrimSpace(getText(a.controls[idNative]))
	case core.HL2Content:
		a.cfg.ContentPath = path
	default:
		a.cfg.GModPath = path
	}
}

func (a *launcher) readForm() error {
	a.readPaths()
	width, widthErr := strconv.Atoi(strings.TrimSpace(getText(a.controls[idWidth])))
	height, heightErr := strconv.Atoi(strings.TrimSpace(getText(a.controls[idHeight])))
	if widthErr != nil || heightErr != nil {
		return fmt.Errorf("Укажите ширину и высоту экрана целыми числами.")
	}
	if (width != 0 || height != 0) && (width < 640 || width > 7680 || height < 480 || height > 4320) {
		return fmt.Errorf("Разрешение от 640 × 480 до 7680 × 4320. Два нуля оставляют настройки игры.")
	}
	options := a.activeOptions()
	options.Width, options.Height = width, height
	options.Map = strings.TrimSpace(getText(a.controls[idMap]))
	options.Display = a.value(idDisplay, displays)
	options.Console = a.checkbox[idConsole]
	options.SkipIntro = a.checkbox[idIntro]
	options.DebugLog = a.checkbox[idLog]
	if a.cfg.Selected == core.GMod {
		options.GameProfile = a.value(idProfile, profiles)
	}
	return nil
}

func (a *launcher) status(message string, ink uintptr) {
	a.statusInk = ink
	setText(a.statusLabel, message)
	repaint(a.statusLabel)
}
func (a *launcher) updateDetection() {
	auto := a.detection.GModPath
	state := a.detection.GMod
	if a.cfg.Selected == core.HL2 {
		auto, state = a.detection.SDKPath, a.detection.HL2
	} else if a.cfg.Selected == core.HL2Content {
		auto, state = a.detection.ContentPath, a.detection.HL2Content
	}
	statusInk := toneNote
	if state.Ready {
		statusInk = toneAccent
	}
	if state.Message == "" {
		state.Message, statusInk = "Выберите «Найти автоматически» для проверки установок Steam.", toneMuted
	}
	a.status(state.Message, statusInk)
	build := a.builds[a.cfg.Selected]
	caption := "Версия отображается после установки пакета."
	if len(build.Revision) >= 10 {
		caption = fmt.Sprintf("Сборка %s · %s · %s", build.Channel, build.Revision[:10], build.Status)
	} else if a.cfg.Selected == core.HL2 {
		caption = "Экспериментальный полигон полёта Source SDK."
	} else if a.cfg.Selected == core.HL2Content {
		caption = "Режим content-only · карты, модели и материалы Half-Life 2."
	}
	setText(a.buildLabel, caption)
	for id, value := range map[int]string{
		idSteam:  a.detection.SteamPath,
		idGame:   auto,
		idNative: a.detection.NativePath,
	} {
		if value == "" {
			value = "Определить автоматически"
		}
		sendText(a.controls[id], emSetCueBanner, 1, value)
	}
}

func (a *launcher) setBusy(busy bool) {
	a.busy = busy
	enable(a.controls[idDetect], !busy)
	enable(a.controls[idLaunch], !busy)
	enable(a.controls[idInstall], !busy)
	enable(a.controls[idRollback], !busy)
}

func (result *jobResult) refresh() {
	result.detected = core.Detect(result.cfg)
	result.builds = make(map[core.Profile]core.BuildInfo)
	for _, profile := range []core.Profile{core.GMod, core.HL2Content} {
		if build, err := core.InstalledBuild(result.cfg, profile); err == nil {
			result.builds[profile] = build
		}
	}
}

func (a *launcher) runJob(job func() jobResult) {
	window, result := a.window, a.result
	go func() {
		result <- job()
		procPostMessage.Call(window, wmResult, 0, 0)
	}()
}

func (a *launcher) begin(start bool) {
	if a.busy {
		return
	}
	a.readPaths()
	a.setBusy(true)
	if start {
		a.status("Проверка пути и запуск через Steam…", toneMuted)
	} else {
		a.status("Поиск Steam, клиента и файлов мода…", toneMuted)
	}
	snapshot := a.cfg
	a.runJob(func() jobResult {
		var completed jobResult
		completed.cfg, completed.start = snapshot, start
		if start {
			plan, err := core.BuildLaunch(snapshot, snapshot.Selected)
			if err == nil {
				err = plan.Start()
			}
			completed.err = err
		} else {
			completed.refresh()
		}
		return completed
	})
}
func (a *launcher) detect() { a.begin(false) }

func (a *launcher) packageAction(rollback bool) {
	if a.busy || a.cfg.Selected == core.HL2 {
		return
	}
	a.readPaths()
	snapshot := a.cfg
	profile := snapshot.Selected
	destination, err := core.PackageDestination(snapshot, profile)
	if err != nil {
		a.status(err.Error(), toneNote)
		return
	}
	game := "Garry’s Mod"
	if profile == core.HL2Content {
		game = "Half-Life 2 · карты"
	}
	var archive string
	prompt := "Вернуть предыдущий пакет для «" + game + "»?"
	if !rollback {
		if executable, err := os.Executable(); err == nil {
			archive = filepath.Join(filepath.Dir(executable), "Abaddon-Game.zip")
		}
		if _, err := os.Stat(archive); os.IsNotExist(err) {
			folder := chooseFolder(a.window, "Выберите папку с Abaddon-Game.zip.", filepath.Dir(archive))
			if folder == "" {
				return
			}
			archive = filepath.Join(folder, "Abaddon-Game.zip")
		}
		build, err := core.BundleInfo(archive, profile)
		if err != nil {
			a.status("Пакет недоступен. "+err.Error(), toneNote)
			return
		}
		prompt = fmt.Sprintf("Установить сборку %s · %s для «%s»?", build.Channel, build.Revision[:10], game)
	}
	if !confirmAction(a.window, prompt+"\n\n"+destination) {
		return
	}
	a.setBusy(true)
	a.status("Проверка файлов пакета…", toneMuted)
	a.runJob(func() jobResult {
		completed := jobResult{cfg: snapshot, note: "Пакет установлен."}
		if rollback {
			_, completed.err = core.RollbackBundle(snapshot, profile)
			completed.note = "Предыдущий пакет восстановлен."
		} else {
			_, completed.err = core.InstallBundle(snapshot, profile, archive)
		}
		completed.refresh()
		return completed
	})
}

func (a *launcher) onResult() {
	select {
	case completed := <-a.result:
		a.setBusy(false)
		if completed.start {
			if completed.err != nil {
				a.status(completed.err.Error(), toneNote)
			} else {
				a.status("Команда запуска передана Steam.", toneAccent)
			}
			return
		}
		a.readPaths()
		cfg := completed.cfg
		if a.cfg.SteamPath != cfg.SteamPath || a.cfg.GModPath != cfg.GModPath ||
			a.cfg.SDKPath != cfg.SDKPath || a.cfg.NativePath != cfg.NativePath || a.cfg.ContentPath != cfg.ContentPath {
			a.status("Пути изменены. Повторите проверку кнопкой автопоиска.", toneNote)
			return
		}
		a.detection = completed.detected
		a.builds = completed.builds
		a.updateDetection()
		if completed.err != nil {
			a.status(completed.err.Error(), toneNote)
		} else if completed.note != "" {
			a.status(completed.note, toneAccent)
		}
	default:
	}
}

func (a *launcher) selectEngine(profile core.Profile) {
	if a.cfg.Selected == profile || a.busy {
		return
	}
	if err := a.readForm(); err != nil {
		a.status(err.Error(), toneNote)
		return
	}
	a.cfg.Selected = profile
	a.setForm()
}

func (a *launcher) browse(id int) {
	field, initial, heading := idSteam, a.detection.SteamPath, "Выберите папку Steam."
	switch id {
	case idGameBrowse:
		field, initial, heading = idGame, a.detection.GModPath, "Выберите папку Garry’s Mod."
		if a.cfg.Selected == core.HL2 {
			initial, heading = a.detection.SDKPath, "Выберите папку Source SDK Base 2013 Singleplayer."
		} else if a.cfg.Selected == core.HL2Content {
			initial, heading = a.detection.ContentPath, "Выберите папку Half-Life 2."
		}
	case idNativeBrowse:
		field, initial, heading = idNative, a.detection.NativePath, "Выберите папку установленного abaddon_native."
	}
	if manual := getText(a.controls[field]); manual != "" {
		initial = manual
	}
	if strings.EqualFold(filepath.Ext(initial), ".exe") {
		initial = filepath.Dir(initial)
	}
	if chosen := chooseFolder(a.window, heading, initial); chosen != "" {
		setText(a.controls[field], chosen)
		a.detect()
	}
}

func (a *launcher) command(wParam uintptr) {
	id, notification := int(wParam&0xffff), int((wParam>>16)&0xffff)
	if a.updating {
		return
	}
	if (id == idSteam || id == idGame || id == idNative) && notification == enChange {
		a.status("Пути изменены. Автопоиск перепроверит установки.", toneMuted)
		return
	}
	if notification != 0 {
		return
	}
	switch id {
	case idGMod:
		a.selectEngine(core.GMod)
	case idHL2:
		a.selectEngine(core.HL2)
	case idContent:
		a.selectEngine(core.HL2Content)
	case idSteamBrowse, idGameBrowse, idNativeBrowse:
		a.browse(id)
	case idConsole, idIntro, idLog:
		a.checkbox[id] = !a.checkbox[id]
		repaint(a.controls[id])
	case idDetect:
		a.detect()
	case idInstall:
		a.packageAction(false)
	case idRollback:
		a.packageAction(true)
	case idSave, idLaunch:
		if err := a.readForm(); err != nil {
			a.status(err.Error(), toneNote)
			return
		}
		if err := core.SaveConfig(a.cfg); err != nil {
			a.status(err.Error(), toneNote)
			return
		}
		if id == idSave {
			a.status("Настройки профилей сохранены.", toneAccent)
		} else {
			a.begin(true)
		}
	}
}

func (a *launcher) paint() {
	var paint paintState
	dc, _, _ := procBeginPaint.Call(a.window, uintptr(unsafe.Pointer(&paint)))
	defer procEndPaint.Call(a.window, uintptr(unsafe.Pointer(&paint)))
	var client rect
	procClientRect.Call(a.window, uintptr(unsafe.Pointer(&client)))
	fill(dc, client, a.background)
	fill(dc, a.box(26, 132, 409, 288), a.panel)
	stroke(dc, a.box(26, 132, 409, 288), a.edge)
	fill(dc, a.box(456, 132, 350, 288), a.panel)
	stroke(dc, a.box(456, 132, 350, 288), a.edge)
	fill(dc, a.box(26, 435, 780, 77), a.field)
	fill(dc, a.box(26, 435, 3, 77), a.activeButton)
}

func (a *launcher) drawItem(draw *drawState) uintptr {
	if a.controls[int(draw.id)] != draw.window {
		return 0
	}
	switch int(draw.id) {
	case idGMod, idContent, idHL2, idSteamBrowse, idGameBrowse, idNativeBrowse, idConsole, idIntro, idLog,
		idDetect, idInstall, idRollback, idSave, idLaunch:
	default:
		return 0
	}
	dc, area, id := draw.dc, draw.rect, int(draw.id)
	ink, base := toneText, a.button
	highlight := id == idLaunch || id == idGMod && a.cfg.Selected == core.GMod ||
		id == idHL2 && a.cfg.Selected == core.HL2 || id == idContent && a.cfg.Selected == core.HL2Content
	if highlight {
		ink, base = toneBackground, a.activeButton
	}
	if draw.state&odsDisabled != 0 {
		ink, base = toneMuted, a.panel
	} else if draw.state&odsSelected != 0 {
		ink, base = toneAccent, a.field
	}
	fill(dc, area, base)
	stroke(dc, area, a.edge)
	oldFont, _, _ := procSelect.Call(dc, a.regular)
	defer procSelect.Call(dc, oldFont)
	oldText, _, _ := procTextColor.Call(dc, ink)
	defer procTextColor.Call(dc, oldText)
	oldMode, _, _ := procBkMode.Call(dc, 1)
	defer procBkMode.Call(dc, oldMode)
	flags := uintptr(dtCenter | dtVCenter | dtSingleLine | dtNoPrefix | dtEndEllipsis)
	if id == idConsole || id == idIntro || id == idLog {
		box := rect{
			Left: area.Left + a.px(7), Top: area.Top + a.px(9),
			Right: area.Left + a.px(17), Bottom: area.Top + a.px(19),
		}
		if a.checkbox[id] {
			fill(dc, box, a.activeButton)
		} else {
			stroke(dc, box, a.edge)
		}
		area.Left += a.px(16)
	}
	textAt(dc, getText(draw.window), area, flags)
	if draw.state&odsFocus != 0 {
		focus := draw.rect
		focus.Left += 3
		focus.Right -= 3
		focus.Top += 3
		focus.Bottom -= 3
		procDrawFocus.Call(dc, uintptr(unsafe.Pointer(&focus)))
	}
	return 1
}

func (a *launcher) smoke() error {
	for id := idGMod; id <= idLaunch; id++ {
		if a.controls[id] == 0 {
			return fmt.Errorf("Нет элемента окна %d.", id)
		}
	}
	for _, profile := range []core.Profile{core.GMod, core.HL2Content, core.HL2, core.GMod} {
		a.selectEngine(profile)
		if a.cfg.Selected != profile {
			return fmt.Errorf("Переключение профиля %s не прошло.", profile)
		}
		if err := a.readForm(); err != nil || a.activeOptions().Map == "" || a.activeOptions().Width < 1 {
			return fmt.Errorf("Не удалось прочитать параметры профиля %s.", profile)
		}
	}
	setText(a.controls[idWidth], "1280")
	setText(a.controls[idGame], `C:\Steam library\GarrysMod`)
	a.selectEngine(core.HL2)
	setText(a.controls[idWidth], "1920")
	setText(a.controls[idGame], `D:\Steam library\Source SDK`)
	a.selectEngine(core.HL2Content)
	setText(a.controls[idWidth], "1024")
	setText(a.controls[idGame], `E:\Steam library\Half-Life 2`)
	a.selectEngine(core.GMod)
	if a.cfg.Selected != core.GMod || getText(a.controls[idWidth]) != "1280" ||
		getText(a.controls[idGame]) != `C:\Steam library\GarrysMod` ||
		a.cfg.HL2.Width != 1920 || a.cfg.SDKPath != `D:\Steam library\Source SDK` ||
		a.cfg.HL2Content.Width != 1024 || a.cfg.ContentPath != `E:\Steam library\Half-Life 2` {
		return fmt.Errorf("Профили не сохранили независимые параметры в памяти.")
	}
	return nil
}

func windowProc(window uintptr, event uint32, wParam, lParam uintptr) uintptr {
	if app != nil && app.window == window && window != 0 {
		a := app
		switch event {
		case wmPaint:
			a.paint()
			return 0
		case wmEraseBackground:
			return 1
		case wmCommand:
			a.command(wParam)
			return 0
		case wmResult:
			a.onResult()
			return 0
		case wmDrawItem:
			if lParam != 0 {
				return a.drawItem((*drawState)(unsafe.Pointer(lParam)))
			}
		case wmColorEdit, wmColorList:
			procTextColor.Call(wParam, toneText)
			procBkColor.Call(wParam, toneField)
			return a.field
		case wmColorStatic:
			if lParam == a.statusLabel {
				procTextColor.Call(wParam, a.statusInk)
				procBkColor.Call(wParam, toneField)
				return a.field
			}
			ink, background, fill := toneText, tonePanel, a.panel
			if lParam == a.titleLabel {
				background, fill = toneBackground, a.background
			} else if lParam == a.captionLabel {
				ink = toneMuted
			}
			procTextColor.Call(wParam, ink)
			procBkColor.Call(wParam, background)
			procBkMode.Call(wParam, 1)
			return fill
		case wmDestroy:
			a.window = 0
			procPostQuit.Call(0)
			return 0
		}
	}
	result, _, _ := procDefWindow.Call(window, uintptr(event), wParam, lParam)
	return result
}
