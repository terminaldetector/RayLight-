//go:build windows

package main

// A native Windows launcher. Only the Go standard library and Windows APIs are
// required; Steam supplies the game clients. No elevated process is requested.
import (
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"sync"
	"syscall"
	"time"
	"unsafe"
)

var (
	user32                     = syscall.NewLazyDLL("user32.dll")
	kernel32                   = syscall.NewLazyDLL("kernel32.dll")
	gdi32                      = syscall.NewLazyDLL("gdi32.dll")
	shell32                    = syscall.NewLazyDLL("shell32.dll")
	ole32                      = syscall.NewLazyDLL("ole32.dll")
	advapi32                   = syscall.NewLazyDLL("advapi32.dll")
	createWindow               = user32.NewProc("CreateWindowExW")
	sendMessage                = user32.NewProc("SendMessageW")
	setWindowText              = user32.NewProc("SetWindowTextW")
	getWindowText              = user32.NewProc("GetWindowTextW")
	messageBox                 = user32.NewProc("MessageBoxW")
	mainWindow, instance, font uintptr
	controls                   = map[int]uintptr{}
	uiScale                    = 1.0
	bundleRoot                 string
	buildRevision              = "development"
	prefs                      preferences
	detected                   []Installation
	steamRoots                 []string
	busy                       bool
	smokeUI                    bool
	workResult                 string
	workErr                    error
	resultMu                   sync.Mutex
)

const (
	idTarget      = 101
	idPath        = 102
	idDetect      = 103
	idBrowse      = 104
	idMap         = 105
	idGraphics    = 106
	idResolution  = 107
	idWindowed    = 108
	idConsole     = 109
	idStatus      = 110
	idModeInfo    = 111
	idInstallRun  = 201
	idInstall     = 202
	idRun         = 203
	idRollback    = 204
	idOpen        = 205
	idDiagnostics = 206
	wmFinished    = 0x8001
)

type preferences struct {
	Target          Target `json:"target"`
	GModPath        string `json:"gmod_path"`
	HL2Path         string `json:"hl2_path"`
	MapIndex        int    `json:"map_index"`
	GraphicsIndex   int    `json:"graphics_index"`
	ResolutionIndex int    `json:"resolution_index"`
	Windowed        bool   `json:"windowed"`
	Console         bool   `json:"console"`
}

type point struct{ X, Y int32 }
type winMessage struct {
	Window         uintptr
	Message        uint32
	WParam, LParam uintptr
	Time           uint32
	Point          point
	Private        uint32
}
type windowClass struct {
	Size, Style                        uint32
	WndProc                            uintptr
	ClassExtra, WindowExtra            int32
	Instance, Icon, Cursor, Background uintptr
	MenuName, ClassName                *uint16
	SmallIcon                          uintptr
}
type browseInfo struct {
	Owner, Root        uintptr
	DisplayName, Title *uint16
	Flags              uint32
	Callback, Param    uintptr
	Image              int32
}

func wide(s string) *uint16 { p, _ := syscall.UTF16PtrFromString(s); return p }
func send(h uintptr, m uint32, w, l uintptr) uintptr {
	r, _, _ := sendMessage.Call(h, uintptr(m), w, l)
	return r
}
func textOf(h uintptr) string {
	n, _, _ := user32.NewProc("GetWindowTextLengthW").Call(h)
	b := make([]uint16, n+1)
	getWindowText.Call(h, uintptr(unsafe.Pointer(&b[0])), uintptr(len(b)))
	return syscall.UTF16ToString(b)
}
func setText(h uintptr, s string) { setWindowText.Call(h, uintptr(unsafe.Pointer(wide(s)))) }
func status(s string)             { setText(controls[idStatus], strings.ReplaceAll(s, "\n", "\r\n")) }
func choice(id int) int           { return int(int32(send(controls[id], 0x0147, 0, 0))) }
func setChoice(id, index int)     { send(controls[id], 0x014E, uintptr(index), 0) }
func checked(id int) bool         { return send(controls[id], 0x00F0, 0, 0) == 1 }
func check(id int, v bool) {
	n := uintptr(0)
	if v {
		n = 1
	}
	send(controls[id], 0x00F1, n, 0)
}
func scaled(n int) uintptr { return uintptr(int(float64(n) * uiScale)) }

func control(class, title string, id, x, y, w, h int, style uintptr) uintptr {
	handle, _, e := createWindow.Call(0, uintptr(unsafe.Pointer(wide(class))), uintptr(unsafe.Pointer(wide(title))),
		0x50000000|style, scaled(x), scaled(y), scaled(w), scaled(h), mainWindow, uintptr(id), instance, 0)
	if handle == 0 {
		panic(fmt.Sprintf("CreateWindow %d: %v", id, e))
	}
	if id != 0 {
		controls[id] = handle
	}
	send(handle, 0x0030, font, 1)
	return handle
}
func combo(id, x, y, w int, items []string, editable bool) {
	style := uintptr(0x00200000 | 0x00010000 | 3)
	if editable {
		style = 0x00200000 | 0x00010000 | 2
	}
	h := control("COMBOBOX", "", id, x, y, w, 240, style)
	for _, s := range items {
		send(h, 0x0143, 0, uintptr(unsafe.Pointer(wide(s))))
	}
	setChoice(id, 0)
}
func label(s string, x, y, w, h int) { control("STATIC", s, 0, x, y, w, h, 0) }

func selectedTarget() Target {
	if choice(idTarget) == 1 {
		return TargetHL2
	}
	return TargetGMod
}
func selectedOptions() LaunchOptions {
	maps := []string{"", "d6_city17_drain", "d6_reactor_escape", "d6_relay_vault"}
	graphics := []string{"default", "balanced", "high"}
	mi, gi := choice(idMap), choice(idGraphics)
	if mi < 0 || mi >= len(maps) {
		mi = 0
	}
	if gi < 0 || gi >= len(graphics) {
		gi = 0
	}
	o := LaunchOptions{Map: maps[mi], Graphics: graphics[gi], Windowed: checked(idWindowed), Console: checked(idConsole)}
	switch choice(idResolution) {
	case 1:
		o.Width, o.Height = 1280, 720
	case 2:
		o.Width, o.Height = 1920, 1080
	case 3:
		o.Width, o.Height = 2560, 1440
	}
	return o
}
func rememberPath() {
	if prefs.Target == TargetHL2 {
		prefs.HL2Path = textOf(controls[idPath])
	} else {
		prefs.GModPath = textOf(controls[idPath])
	}
}
func chooseTarget() {
	t := selectedTarget()
	prefs.Target = t
	send(controls[idPath], 0x014B, 0, 0)
	for _, i := range detected {
		if i.Target == t {
			send(controls[idPath], 0x0143, 0, uintptr(unsafe.Pointer(wide(i.Root))))
		}
	}
	path := prefs.GModPath
	if t == TargetHL2 {
		path = prefs.HL2Path
	}
	if path != "" {
		setText(controls[idPath], path)
	} else if send(controls[idPath], 0x0146, 0, 0) > 0 {
		setChoice(idPath, 0)
	}
	info := "GMod: 6DOF, оружие, мины и 3 саппорта Granada. Запуск через установленный клиент."
	if t == TargetHL2 {
		info = "HL2: просмотр карт и моделей. GLua, 6DOF-бой и саппорты здесь не исполняются."
	}
	setText(controls[idModeInfo], info)
}
func detect() {
	steamRoots = windowsSteamRoots()
	detected = DiscoverInstallations(steamRoots)
	chooseTarget()
	if len(detected) == 0 {
		status("Steam-игры не найдены автоматически. Выберите папку игры кнопкой «Обзор» или вставьте путь вручную.")
	} else {
		status(fmt.Sprintf("Найдено установок: %d. Проверьте выбранный путь. Если библиотек несколько, пути доступны в списке.", len(detected)))
	}
}
func browse() {
	display := make([]uint16, 32768)
	bi := browseInfo{Owner: mainWindow, DisplayName: &display[0], Title: wide("Выберите папку GarrysMod или Half-Life 2 (можно garrysmod / hl2)"), Flags: 0x0041}
	id, _, _ := shell32.NewProc("SHBrowseForFolderW").Call(uintptr(unsafe.Pointer(&bi)))
	if id == 0 {
		return
	}
	defer ole32.NewProc("CoTaskMemFree").Call(id)
	buf := make([]uint16, 32768)
	ok, _, _ := shell32.NewProc("SHGetPathFromIDListW").Call(id, uintptr(unsafe.Pointer(&buf[0])))
	if ok != 0 {
		setText(controls[idPath], syscall.UTF16ToString(buf))
		rememberPath()
	}
}
func prefsDir() string {
	p := os.Getenv("LOCALAPPDATA")
	if p == "" {
		p, _ = os.UserConfigDir()
	}
	return filepath.Join(p, "AbaddonLauncher")
}
func loadPreferences() {
	prefs = preferences{Target: TargetGMod, MapIndex: 3, Windowed: true}
	if b, e := os.ReadFile(filepath.Join(prefsDir(), "settings.json")); e == nil {
		_ = json.Unmarshal(b, &prefs)
	}
	if prefs.Target != TargetHL2 {
		prefs.Target = TargetGMod
	}
}
func savePreferences() error {
	rememberPath()
	prefs.Target = selectedTarget()
	prefs.MapIndex = choice(idMap)
	prefs.GraphicsIndex = choice(idGraphics)
	prefs.ResolutionIndex = choice(idResolution)
	prefs.Windowed = checked(idWindowed)
	prefs.Console = checked(idConsole)
	if smokeUI {
		return nil
	}
	if e := os.MkdirAll(prefsDir(), 0700); e != nil {
		return e
	}
	b, err := json.MarshalIndent(prefs, "", "  ")
	if err != nil {
		return err
	}
	return writeAtomic(filepath.Join(prefsDir(), "settings.json"), b, "")
}
func setBusy(v bool) {
	busy = v
	enabled := uintptr(1)
	if v {
		enabled = 0
	}
	for id, h := range controls {
		if id != idStatus && id != idModeInfo {
			user32.NewProc("EnableWindow").Call(h, enabled)
		}
	}
}
func resolveInstallation() (Installation, error) {
	i, e := ValidateInstallation(strings.TrimSpace(textOf(controls[idPath])), selectedTarget())
	if e != nil {
		return i, e
	}
	for _, d := range detected {
		if strings.EqualFold(d.Root, i.Root) && d.Target == i.Target {
			i.SteamRoot = d.SteamRoot
			break
		}
	}
	// A manually selected copy must not silently launch a different Steam copy.
	// Only a matching appmanifest discovered above can establish SteamRoot.
	return i, nil
}
func logResult(s string) {
	if smokeUI {
		return
	}
	_ = os.MkdirAll(prefsDir(), 0700)
	f, e := os.OpenFile(filepath.Join(prefsDir(), "launcher.log"), os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0600)
	if e == nil {
		defer f.Close()
		fmt.Fprintf(f, "%s %s\n", time.Now().Format(time.RFC3339), s)
	}
}
func action(id int) {
	if smokeUI {
		status("UI smoke: установка, откат и запуск игры отключены.")
		return
	}
	if busy {
		return
	}
	preferenceErr := savePreferences()
	i, e := resolveInstallation()
	if id == idDiagnostics {
		m, err := LoadManifest(bundleRoot)
		msg := fmt.Sprintf("Цель: %s\nСборка: %s\nМатериалы: штатные Source; полноценный PBR отсутствует.\nГрафический клиент игры: здесь не проверен.", selectedTarget(), buildRevision)
		if e != nil {
			msg += "\nУстановка: " + e.Error()
		} else {
			msg += "\nУстановка подтверждена: " + i.Root
		}
		if err != nil {
			msg += "\nПакет: " + err.Error()
		} else {
			msg += fmt.Sprintf("\nManifest: %s / %s; %d файлов.", m.Channel, m.Revision, len(m.Files))
		}
		if preferenceErr != nil {
			msg += "\nНастройки не сохранены: " + preferenceErr.Error()
		}
		msg += "\nДиагностика локальная; ничего не отправляется в сеть."
		status(msg)
		return
	}
	if e != nil {
		status("Папка игры не подтверждена: " + e.Error())
		return
	}
	if id == idOpen {
		shell32.NewProc("ShellExecuteW").Call(mainWindow, uintptr(unsafe.Pointer(wide("open"))), uintptr(unsafe.Pointer(wide(i.GameDir))), 0, 0, 1)
		return
	}
	if activeGame() {
		status("Закройте HL2 / Garry’s Mod перед установкой, откатом или запуском нового сеанса.")
		return
	}
	if id == idRollback {
		r, _, _ := messageBox.Call(mainWindow, uintptr(unsafe.Pointer(wide("Вернуть предыдущую установленную сборку? Текущая копия останется в резерве."))), uintptr(unsafe.Pointer(wide("Откат Abaddon"))), 0x00000004|0x00000020)
		if r != 6 {
			return
		}
	}
	o := selectedOptions()
	setBusy(true)
	status("Проверка пакета и выбранной установки…")
	go func() {
		var msg string
		var err error
		switch id {
		case idInstall, idInstallRun:
			var dest string
			dest, err = InstallBundle(bundleRoot, i)
			if err == nil {
				msg = "Установлено: " + dest
			}
		case idRollback:
			var dest string
			dest, err = RollbackInstallation(i)
			if err == nil {
				msg = "Восстановлено: " + dest
			}
		case idRun:
			msg = "Запуск установленной копии."
		}
		if err == nil && (id == idRun || id == idInstallRun) {
			var executable string
			var args []string
			executable, args, err = ConfigureLaunch(i, o)
			if err == nil {
				c := exec.Command(executable, args...)
				c.Dir = i.Root
				err = c.Start()
				if err == nil {
					_ = c.Process.Release()
					msg += "\nКоманда запуска передана клиенту. Состояние игры проверяйте в её окне."
				}
			}
		}
		if err != nil {
			msg = "Операция не завершена: " + err.Error()
		}
		if preferenceErr != nil {
			msg += "\nВыбор параметров не сохранён: " + preferenceErr.Error()
		}
		logResult(msg)
		resultMu.Lock()
		workResult, workErr = msg, err
		resultMu.Unlock()
		user32.NewProc("PostMessageW").Call(mainWindow, wmFinished, 0, 0)
	}()
}

func wndProc(hwnd uintptr, msg uint32, w, l uintptr) uintptr {
	switch msg {
	case 0x0111: // WM_COMMAND
		id, event := int(w&0xffff), int((w>>16)&0xffff)
		if id == idTarget && event == 1 {
			rememberPath()
			chooseTarget()
			return 0
		}
		if event == 0 {
			switch id {
			case idDetect:
				rememberPath()
				detect()
			case idBrowse:
				browse()
			case idInstallRun, idInstall, idRun, idRollback, idOpen, idDiagnostics:
				action(id)
			}
		}
	case wmFinished:
		resultMu.Lock()
		s := workResult
		resultMu.Unlock()
		setBusy(false)
		status(s)
		return 0
	case 0x0113: // WM_TIMER, CI smoke only
		if smokeUI {
			user32.NewProc("DestroyWindow").Call(hwnd)
			return 0
		}
	case 0x0010: // WM_CLOSE
		if busy {
			status("Дождитесь завершения установки или отката.")
			return 0
		}
		if err := savePreferences(); err != nil {
			messageBox.Call(hwnd, uintptr(unsafe.Pointer(wide("Параметры лаунчера не сохранены: "+err.Error()))), uintptr(unsafe.Pointer(wide("Abaddon Launcher"))), 0x30)
		}
		user32.NewProc("DestroyWindow").Call(hwnd)
		return 0
	case 0x0002: // WM_DESTROY
		user32.NewProc("PostQuitMessage").Call(0)
		return 0
	}
	r, _, _ := user32.NewProc("DefWindowProcW").Call(hwnd, uintptr(msg), w, l)
	return r
}

func buildUI() error {
	user32.NewProc("SetProcessDPIAware").Call()
	dc, _, _ := user32.NewProc("GetDC").Call(0)
	dpi, _, _ := gdi32.NewProc("GetDeviceCaps").Call(dc, 88)
	user32.NewProc("ReleaseDC").Call(0, dc)
	if dpi > 0 {
		uiScale = float64(dpi) / 96
	}
	// Fit the complete compact form within the current work area at high DPI.
	var workArea struct{ Left, Top, Right, Bottom int32 }
	if ok, _, _ := user32.NewProc("SystemParametersInfoW").Call(0x0030, 0, uintptr(unsafe.Pointer(&workArea)), 0); ok != 0 {
		for _, fit := range []float64{float64(workArea.Right-workArea.Left-24) / 800, float64(workArea.Bottom-workArea.Top-24) / 650} {
			if fit > 0 && fit < uiScale {
				uiScale = fit
			}
		}
	}
	instance, _, _ = kernel32.NewProc("GetModuleHandleW").Call(0)
	cursor, _, _ := user32.NewProc("LoadCursorW").Call(0, 32512)
	icon, _, _ := user32.NewProc("LoadIconW").Call(0, 32512)
	wc := windowClass{WndProc: syscall.NewCallback(wndProc), Instance: instance, Cursor: cursor, Icon: icon, SmallIcon: icon, Background: 6, ClassName: wide("AbaddonLauncherWindow")}
	wc.Size = uint32(unsafe.Sizeof(wc))
	if r, _, e := user32.NewProc("RegisterClassExW").Call(uintptr(unsafe.Pointer(&wc))); r == 0 {
		return e
	}
	mainWindow, _, _ = createWindow.Call(0, uintptr(unsafe.Pointer(wc.ClassName)), uintptr(unsafe.Pointer(wide("Half-Life: Abaddon — Launcher"))), 0x00CA0000, 0x80000000, 0x80000000, scaled(800), scaled(650), 0, 0, instance, 0)
	if mainWindow == 0 {
		return fmt.Errorf("не удалось создать окно")
	}
	height := int32(-float64(15) * uiScale)
	font, _, _ = gdi32.NewProc("CreateFontW").Call(uintptr(height), 0, 0, 0, 400, 0, 0, 0, 1, 0, 0, 5, 0, uintptr(unsafe.Pointer(wide("Segoe UI"))))
	defer gdi32.NewProc("DeleteObject").Call(font)
	label("HALF-LIFE: ABADDON", 20, 16, 750, 26)
	label("Локальная установка и запуск · "+buildRevision, 20, 45, 750, 24)
	label("Клиент", 20, 84, 120, 24)
	combo(idTarget, 145, 80, 425, []string{"Garry’s Mod — игровая сборка", "Half-Life 2 — карты и модели"}, false)
	control("BUTTON", "Найти игры", idDetect, 585, 79, 175, 29, 0x00010000)
	control("STATIC", "", idModeInfo, 20, 116, 740, 34, 0)
	label("Папка игры", 20, 160, 120, 24)
	combo(idPath, 145, 156, 485, nil, true)
	control("BUTTON", "Обзор…", idBrowse, 640, 155, 120, 29, 0x00010000)
	label("Старт", 20, 203, 120, 24)
	combo(idMap, 145, 199, 615, []string{"Меню игры", "Эпизод — City 17", "Реактор — Escape", "Арена — Relay Vault"}, false)
	label("Графика", 20, 246, 120, 24)
	combo(idGraphics, 145, 242, 615, []string{"Настройки игры — не менять", "Сбалансированный — тени 1024, фильтрация 8×", "Высокий — тени 2048, фильтрация 16×"}, false)
	label("Материалы: штатные Source. PBR отсутствует. Профиль не добавляет недостающие тени или отражения.", 20, 278, 740, 40)
	label("Разрешение", 20, 326, 120, 24)
	combo(idResolution, 145, 322, 250, []string{"Из настроек игры", "1280 × 720", "1920 × 1080", "2560 × 1440"}, false)
	control("BUTTON", "В окне", idWindowed, 420, 321, 145, 29, 0x00010003)
	control("BUTTON", "Консоль", idConsole, 590, 321, 165, 29, 0x00010003)
	control("BUTTON", "Установить и запустить", idInstallRun, 20, 370, 285, 36, 0x00010001)
	control("BUTTON", "Только установить", idInstall, 318, 370, 215, 36, 0x00010000)
	control("BUTTON", "Запустить", idRun, 546, 370, 214, 36, 0x00010000)
	control("BUTTON", "Откатить установку", idRollback, 20, 417, 240, 32, 0x00010000)
	control("BUTTON", "Папка игры", idOpen, 273, 417, 240, 32, 0x00010000)
	control("BUTTON", "Диагностика", idDiagnostics, 526, 417, 234, 32, 0x00010000)
	control("EDIT", "", idStatus, 20, 465, 740, 130, 0x00800000|0x00200000|0x00000804|0x00000040)
	if prefs.Target == TargetHL2 {
		setChoice(idTarget, 1)
	}
	for id, value := range map[int]int{idMap: prefs.MapIndex, idGraphics: prefs.GraphicsIndex, idResolution: prefs.ResolutionIndex} {
		count := int(send(controls[id], 0x0146, 0, 0))
		if value < 0 || value >= count {
			value = 0
		}
		setChoice(id, value)
	}
	check(idWindowed, prefs.Windowed)
	check(idConsole, prefs.Console)
	detect()
	if smokeUI {
		for _, id := range []int{idInstallRun, idInstall, idRun, idRollback, idOpen} {
			user32.NewProc("EnableWindow").Call(controls[id], 0)
		}
		for _, id := range []int{idTarget, idPath, idMap, idGraphics, idResolution, idStatus, idInstallRun, idRollback} {
			if controls[id] == 0 {
				return fmt.Errorf("missing control %d", id)
			}
		}
		if choice(idGraphics) < 0 || choice(idMap) < 0 {
			return fmt.Errorf("invalid combo selection")
		}
		user32.NewProc("SetTimer").Call(mainWindow, 1, 300, 0)
	}
	user32.NewProc("ShowWindow").Call(mainWindow, 1)
	user32.NewProc("UpdateWindow").Call(mainWindow)
	var m winMessage
	for {
		r, _, e := user32.NewProc("GetMessageW").Call(uintptr(unsafe.Pointer(&m)), 0, 0, 0)
		if int32(r) == -1 {
			return e
		}
		if r == 0 {
			break
		}
		// Native dialog navigation gives tab, arrows and access to every control.
		handled, _, _ := user32.NewProc("IsDialogMessageW").Call(mainWindow, uintptr(unsafe.Pointer(&m)))
		if handled == 0 {
			user32.NewProc("TranslateMessage").Call(uintptr(unsafe.Pointer(&m)))
			user32.NewProc("DispatchMessageW").Call(uintptr(unsafe.Pointer(&m)))
		}
	}
	return nil
}

func registryString(hive uintptr, subkey, name string, view uintptr) string {
	var key uintptr
	r, _, _ := advapi32.NewProc("RegOpenKeyExW").Call(hive, uintptr(unsafe.Pointer(wide(subkey))), 0, 0x20019|view, uintptr(unsafe.Pointer(&key)))
	if r != 0 {
		return ""
	}
	defer advapi32.NewProc("RegCloseKey").Call(key)
	var typ, size uint32
	r, _, _ = advapi32.NewProc("RegQueryValueExW").Call(key, uintptr(unsafe.Pointer(wide(name))), 0, uintptr(unsafe.Pointer(&typ)), 0, uintptr(unsafe.Pointer(&size)))
	if r != 0 || size == 0 || size > 65536 || (typ != 1 && typ != 2) {
		return ""
	}
	b := make([]uint16, size/2+1)
	r, _, _ = advapi32.NewProc("RegQueryValueExW").Call(key, uintptr(unsafe.Pointer(wide(name))), 0, uintptr(unsafe.Pointer(&typ)), uintptr(unsafe.Pointer(&b[0])), uintptr(unsafe.Pointer(&size)))
	if r != 0 {
		return ""
	}
	return syscall.UTF16ToString(b)
}
func windowsSteamRoots() []string {
	var paths []string
	paths = append(paths, registryString(0x80000001, `Software\Valve\Steam`, "SteamPath", 0))
	for _, view := range []uintptr{0x0200, 0x0100} {
		paths = append(paths, registryString(0x80000002, `SOFTWARE\Valve\Steam`, "InstallPath", view))
	}
	for _, env := range []string{"ProgramFiles(x86)", "ProgramFiles"} {
		if p := os.Getenv(env); p != "" {
			paths = append(paths, filepath.Join(p, "Steam"))
		}
	}
	seen := map[string]bool{}
	var result []string
	for _, p := range paths {
		if p != "" && !seen[strings.ToLower(p)] {
			seen[strings.ToLower(p)] = true
			result = append(result, p)
		}
	}
	return result
}

type processEntry struct {
	Size, Usage, ProcessID             uint32
	DefaultHeapID                      uintptr
	ModuleID, Threads, ParentProcessID uint32
	Priority                           int32
	Flags                              uint32
	Exe                                [260]uint16
}

func activeGame() bool {
	h, _, _ := kernel32.NewProc("CreateToolhelp32Snapshot").Call(2, 0)
	if h == ^uintptr(0) {
		return false
	}
	defer kernel32.NewProc("CloseHandle").Call(h)
	p := processEntry{}
	p.Size = uint32(unsafe.Sizeof(p))
	r, _, _ := kernel32.NewProc("Process32FirstW").Call(h, uintptr(unsafe.Pointer(&p)))
	for r != 0 {
		name := strings.ToLower(syscall.UTF16ToString(p.Exe[:]))
		if name == "gmod.exe" || name == "hl2.exe" || name == "garrysmod.exe" {
			return true
		}
		r, _, _ = kernel32.NewProc("Process32NextW").Call(h, uintptr(unsafe.Pointer(&p)))
	}
	return false
}

func main() {
	runtime.LockOSThread()
	_, _, _ = ole32.NewProc("CoInitializeEx").Call(0, 2)
	defer ole32.NewProc("CoUninitialize").Call()
	executable, e := os.Executable()
	if e != nil {
		os.Exit(1)
	}
	bundleRoot = filepath.Dir(executable)
	for _, arg := range os.Args[1:] {
		if arg == "--smoke-ui" {
			smokeUI = true
		}
	}
	if !smokeUI {
		mutex, _, err := kernel32.NewProc("CreateMutexW").Call(0, 0, uintptr(unsafe.Pointer(wide(`Local\AbaddonLauncher_v1`))))
		if mutex == 0 {
			messageBox.Call(0, uintptr(unsafe.Pointer(wide("Не удалось создать блокировку лаунчера."))), uintptr(unsafe.Pointer(wide("Abaddon Launcher"))), 0x10)
			os.Exit(1)
		}
		defer kernel32.NewProc("CloseHandle").Call(mutex)
		if err == syscall.Errno(183) {
			messageBox.Call(0, uintptr(unsafe.Pointer(wide("Лаунчер уже открыт. Используйте существующее окно."))), uintptr(unsafe.Pointer(wide("Abaddon Launcher"))), 0x40)
			return
		}
	}
	if smokeUI {
		p, e := os.MkdirTemp("", "abaddon-ui-smoke-")
		if e != nil {
			os.Exit(2)
		}
		defer os.RemoveAll(p)
		_ = os.Setenv("LOCALAPPDATA", p)
	}
	if m, err := LoadManifest(bundleRoot); err == nil {
		buildRevision = m.Revision[:12]
	}
	loadPreferences()
	if e = buildUI(); e != nil {
		logResult(e.Error())
		if !smokeUI {
			messageBox.Call(0, uintptr(unsafe.Pointer(wide(e.Error()))), uintptr(unsafe.Pointer(wide("Abaddon Launcher"))), 0x10)
		}
		os.Exit(1)
	}
}
