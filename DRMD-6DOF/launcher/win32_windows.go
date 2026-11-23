package main

import (
	"runtime"
	"syscall"
	"unsafe"
)

var (
	user32   = syscall.NewLazyDLL("user32.dll")
	kernel32 = syscall.NewLazyDLL("kernel32.dll")
	gdi32    = syscall.NewLazyDLL("gdi32.dll")
	shell32  = syscall.NewLazyDLL("shell32.dll")
	ole32    = syscall.NewLazyDLL("ole32.dll")
	uxtheme  = syscall.NewLazyDLL("uxtheme.dll")

	procRegisterClass = user32.NewProc("RegisterClassExW")
	procCreateWindow  = user32.NewProc("CreateWindowExW")
	procDefWindow     = user32.NewProc("DefWindowProcW")
	procDestroyWindow = user32.NewProc("DestroyWindow")
	procPostQuit      = user32.NewProc("PostQuitMessage")
	procGetMessage    = user32.NewProc("GetMessageW")
	procTranslate     = user32.NewProc("TranslateMessage")
	procDispatch      = user32.NewProc("DispatchMessageW")
	procDialogMessage = user32.NewProc("IsDialogMessageW")
	procSendMessage   = user32.NewProc("SendMessageW")
	procPostMessage   = user32.NewProc("PostMessageW")
	procShowWindow    = user32.NewProc("ShowWindow")
	procEnableWindow  = user32.NewProc("EnableWindow")
	procFocus         = user32.NewProc("SetFocus")
	procSetText       = user32.NewProc("SetWindowTextW")
	procTextLen       = user32.NewProc("GetWindowTextLengthW")
	procGetText       = user32.NewProc("GetWindowTextW")
	procLoadCursor    = user32.NewProc("LoadCursorW")
	procLoadIcon      = user32.NewProc("LoadIconW")
	procAdjustRect    = user32.NewProc("AdjustWindowRectEx")
	procSysParams     = user32.NewProc("SystemParametersInfoW")
	procSetDPIAware   = user32.NewProc("SetProcessDPIAware")
	procSystemDPI     = user32.NewProc("GetDpiForSystem")
	procMessageBox    = user32.NewProc("MessageBoxW")
	procBeginPaint    = user32.NewProc("BeginPaint")
	procEndPaint      = user32.NewProc("EndPaint")
	procClientRect    = user32.NewProc("GetClientRect")
	procFillRect      = user32.NewProc("FillRect")
	procFrameRect     = user32.NewProc("FrameRect")
	procDrawText      = user32.NewProc("DrawTextW")
	procDrawFocus     = user32.NewProc("DrawFocusRect")
	procInvalidate    = user32.NewProc("InvalidateRect")

	procModule    = kernel32.NewProc("GetModuleHandleW")
	procCtlTheme  = uxtheme.NewProc("SetWindowTheme")
	procFont      = gdi32.NewProc("CreateFontW")
	procBrush     = gdi32.NewProc("CreateSolidBrush")
	procSelect    = gdi32.NewProc("SelectObject")
	procDelete    = gdi32.NewProc("DeleteObject")
	procTextColor = gdi32.NewProc("SetTextColor")
	procBkColor   = gdi32.NewProc("SetBkColor")
	procBkMode    = gdi32.NewProc("SetBkMode")

	procBrowseForFolder  = shell32.NewProc("SHBrowseForFolderW")
	procPathFromID       = shell32.NewProc("SHGetPathFromIDListEx")
	procLegacyPathFromID = shell32.NewProc("SHGetPathFromIDListW")
	procCoInitialize     = ole32.NewProc("CoInitializeEx")
	procCoUninitialize   = ole32.NewProc("CoUninitialize")
	procCoFree           = ole32.NewProc("CoTaskMemFree")
)

const (
	wsChild           = 0x40000000
	wsVisible         = 0x10000000
	wsTabStop         = 0x00010000
	wsGroup           = 0x00020000
	wsVScroll         = 0x00200000
	wsClipChildren    = 0x02000000
	wsCaption         = 0x00C00000
	wsSysMenu         = 0x00080000
	wsMinimizeBox     = 0x00020000
	wsExClientEdge    = 0x00000200
	wsExControlParent = 0x00010000

	wmDestroy         = 0x0002
	wmPaint           = 0x000F
	wmEraseBackground = 0x0014
	wmSetFont         = 0x0030
	wmDrawItem        = 0x002B
	wmCommand         = 0x0111
	wmColorEdit       = 0x0133
	wmColorList       = 0x0134
	wmColorStatic     = 0x0138
	wmResult          = 0x8001

	esAutoHScroll  = 0x0080
	esNumber       = 0x2000
	enChange       = 0x0300
	emSetLimitText = 0x00C5
	emSetCueBanner = 0x1501

	bsOwnerDraw = 0x0000000B
	odsSelected = 0x0001
	odsDisabled = 0x0004
	odsFocus    = 0x0010

	cbAddString     = 0x0143
	cbGetCurSel     = 0x0147
	cbResetContent  = 0x014B
	cbSetCurSel     = 0x014E
	cbsDropDown     = 0x0002
	cbsDropDownList = 0x0003
	cbsAutoHScroll  = 0x0040

	dtCenter      = 0x0001
	dtVCenter     = 0x0004
	dtSingleLine  = 0x0020
	dtNoPrefix    = 0x0800
	dtEndEllipsis = 0x8000
)

type rect struct{ Left, Top, Right, Bottom int32 }
type point struct{ X, Y int32 }
type windowClass struct {
	size, style                   uint32
	callback                      uintptr
	classExtra, windowExtra       int32
	instance, icon, cursor, brush uintptr
	menu, name                    *uint16
	smallIcon                     uintptr
}
type message struct {
	window         uintptr
	message        uint32
	wParam, lParam uintptr
	time           uint32
	point          point
	reserved       uint32
}
type paintState struct {
	dc              uintptr
	erase           int32
	rect            rect
	restore, update int32
	reserved        [32]byte
}
type drawState struct {
	controlType, id, itemID, action, state uint32
	window, dc                             uintptr
	rect                                   rect
	itemData                               uintptr
}
type browseInfo struct {
	owner, root            uintptr
	displayName, title     *uint16
	flags                  uint32
	callback, callbackData uintptr
	image                  int32
}

func utf(value string) *uint16 {
	text, err := syscall.UTF16PtrFromString(value)
	if err != nil {
		return syscall.StringToUTF16Ptr("")
	}
	return text
}

func setText(window uintptr, value string) {
	procSetText.Call(window, uintptr(unsafe.Pointer(utf(value))))
}

func getText(window uintptr) string {
	length, _, _ := procTextLen.Call(window)
	value := make([]uint16, length+1)
	procGetText.Call(window, uintptr(unsafe.Pointer(&value[0])), uintptr(len(value)))
	return syscall.UTF16ToString(value)
}

func send(window uintptr, event uint32, wParam, lParam uintptr) uintptr {
	result, _, _ := procSendMessage.Call(window, uintptr(event), wParam, lParam)
	return result
}
func sendText(window uintptr, event uint32, wParam uintptr, value string) {
	procSendMessage.Call(window, uintptr(event), wParam, uintptr(unsafe.Pointer(utf(value))))
}

func show(window uintptr, visible bool) {
	if visible {
		procShowWindow.Call(window, 5)
	} else {
		procShowWindow.Call(window, 0)
	}
}

func enable(window uintptr, enabled bool) {
	if enabled {
		procEnableWindow.Call(window, 1)
	} else {
		procEnableWindow.Call(window, 0)
	}
}
func repaint(window uintptr) { procInvalidate.Call(window, 0, 0) }

func color(r, g, b uintptr) uintptr { return r | g<<8 | b<<16 }
func brush(tone uintptr) uintptr {
	handle, _, _ := procBrush.Call(tone)
	return handle
}
func fill(dc uintptr, area rect, paint uintptr) {
	procFillRect.Call(dc, uintptr(unsafe.Pointer(&area)), paint)
}
func stroke(dc uintptr, area rect, paint uintptr) {
	procFrameRect.Call(dc, uintptr(unsafe.Pointer(&area)), paint)
}
func textAt(dc uintptr, value string, area rect, flags uintptr) {
	procDrawText.Call(dc, uintptr(unsafe.Pointer(utf(value))), ^uintptr(0), uintptr(unsafe.Pointer(&area)), flags)
}
func font(height int32, weight uint32) uintptr {
	handle, _, _ := procFont.Call(uintptr(-height), 0, 0, 0, uintptr(weight), 0, 0, 0, 1, 0, 0, 5, 0,
		uintptr(unsafe.Pointer(utf("Segoe UI"))))
	return handle
}

func windowTitle(owner uintptr, text string) {
	procMessageBox.Call(owner, uintptr(unsafe.Pointer(utf(text))),
		uintptr(unsafe.Pointer(utf("Half-Life: Abaddon"))), 0x10)
}

func confirmAction(owner uintptr, text string) bool {
	result, _, _ := procMessageBox.Call(owner, uintptr(unsafe.Pointer(utf(text))),
		uintptr(unsafe.Pointer(utf("Half-Life: Abaddon"))), 0x0004|0x0020|0x0100)
	return result == 6
}

func chooseFolder(owner uintptr, heading, initial string) string {
	initialized, _, _ := procCoInitialize.Call(0, 2)
	if uint32(initialized) == 0 || uint32(initialized) == 1 {
		defer procCoUninitialize.Call()
	}
	current := utf(initial)
	name := make([]uint16, 260)
	info := browseInfo{
		owner:        owner,
		displayName:  &name[0],
		title:        utf(heading),
		flags:        0x0001 | 0x0010 | 0x0040,
		callback:     folderInitialCallback,
		callbackData: uintptr(unsafe.Pointer(current)),
	}
	id, _, _ := procBrowseForFolder.Call(uintptr(unsafe.Pointer(&info)))
	runtime.KeepAlive(current)
	if id == 0 {
		return ""
	}
	defer procCoFree.Call(id)
	full := make([]uint16, 32768)
	var ok uintptr
	if procPathFromID.Find() == nil {
		ok, _, _ = procPathFromID.Call(id, uintptr(unsafe.Pointer(&full[0])), uintptr(len(full)), 0)
	} else {
		ok, _, _ = procLegacyPathFromID.Call(id, uintptr(unsafe.Pointer(&full[0])))
	}
	if ok == 0 {
		return ""
	}
	return syscall.UTF16ToString(full)
}

var folderInitialCallback = syscall.NewCallback(func(window uintptr, event uint32, unused, initial uintptr) uintptr {
	if event == 1 && initial != 0 {
		send(window, 0x467, 1, initial)
	}
	return 0
})

func syscallWindowProc() uintptr { return syscall.NewCallback(windowProc) }
