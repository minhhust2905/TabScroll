; ============================================================
;  TabScroll — RButton + Wheel = Switch Tab
;  Phiên bản: 1.2
;  Yêu cầu: AutoHotkey v2.0+
; ============================================================
;
;  Cách dùng:
;    - Giữ chuột phải + lăn lên   → tab tiếp theo  (Ctrl+Tab)
;    - Giữ chuột phải + lăn xuống → tab trước đó   (Ctrl+Shift+Tab)
;    - Giữ chuột phải + không lăn → click phải bình thường
;    - Ngoài các app được hỗ trợ  → scroll bình thường
;
;  Tính năng v1.1:
;    - Splash screen khi khởi động (Thumbnail.png)
;    - Không bị duplicate: chạy lại sẽ tắt instance cũ, khởi động lại
;    - Tùy chọn "Khởi động cùng Windows" trong tray menu (lưu vào .ini)
;
;  Fix v1.2:
;    - Startup registry dùng đúng AutoHotkey64.exe trong resources/
;    - OSD scroll count giới hạn tối đa ±9
;
; ============================================================

#Requires AutoHotkey v2.0
#SingleInstance Force   ; Nếu chạy lại → tự động tắt instance cũ, chạy mới
#UseHook True

A_MenuMaskKey := "vkE8"

; ============================================================
;  CONFIG — đường dẫn file
; ============================================================
global CONFIG_FILE  := A_ScriptDir . "\TabScroll.ini"
global SPLASH_IMAGE := A_ScriptDir . "\Thumbnail.png"
global ICON_FILE    := A_ScriptDir . "\TabScroll.ico"
global STARTUP_KEY  := "TabScroll"
global STARTUP_REG  := "HKCU\Software\Microsoft\Windows\CurrentVersion\Run"

; ============================================================
;  Whitelist đã được thay thế bằng IsInterceptable()
;  Tự động hoạt động với mọi app — không cần maintain
; ============================================================

; ============================================================
;  STATE
; ============================================================
global g_gestureActive  := false
global g_scrollCount    := 0
global g_scrollDir      := 0
global g_isTabApp       := false
global g_osdGui         := false
global g_osdText        := false
global g_osdEnabled     := true

; ============================================================
;  FEATURE 1 — SPLASH SCREEN
;  Hiện Thumbnail.png ở giữa màn hình ~1.5 giây khi khởi động
; ============================================================
ShowSplash() {
    if !FileExist(SPLASH_IMAGE)
        return

    splash := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20")
    splash.BackColor := "1A1A1A"
    splash.MarginX := 0
    splash.MarginY := 0

    pic := splash.AddPicture("w240 h-1", SPLASH_IMAGE)   ; giữ tỉ lệ, rộng 240px

    ; Tính kích thước thực của ảnh sau khi scale
    picW := 240
    picH := pic.Value  ; AHK trả về chiều cao thực sau scale (nếu h=-1)

    ; Lấy kích thước màn hình chính
    MonitorGetWorkArea(MonitorGetPrimary(), &mL, &mT, &mR, &mB)
    screenW := mR - mL
    screenH := mB - mT

    padX := 32
    padY := 24
    winW := picW + padX * 2
    winH := 300

    posX := mL + (screenW - winW) // 2
    posY := mT + (screenH - winH) // 2

    splash.Show("x" posX " y" posY " w" winW " h" winH " NoActivate")

    ; Bo góc
    try DllCall("SetWindowRgn",
        "Ptr", splash.Hwnd,
        "Ptr", DllCall("CreateRoundRectRgn",
            "Int", 0, "Int", 0, "Int", winW, "Int", winH,
            "Int", 16, "Int", 16),
        "Int", true)

    WinSetTransparent(230, splash)

    ; Tự đóng sau 1500ms
    SetTimer(() => splash.Destroy(), -1500)
}

; ============================================================
;  FEATURE 3 — STARTUP WITH WINDOWS
;  Đọc / ghi registry, lưu preference ra .ini
; ============================================================
LoadStartupPref() {
    try {
        val := IniRead(CONFIG_FILE, "Settings", "StartWithWindows", "0")
        return (val = "1")
    }
    return false
}

SaveStartupPref(enabled) {
    IniWrite(enabled ? "1" : "0", CONFIG_FILE, "Settings", "StartWithWindows")
}

ApplyStartupRegistry(enabled) {
    if enabled {
        target := '"' . A_ScriptDir . '\AutoHotkey64.exe" "' . A_ScriptFullPath . '"'
        RegWrite(target, "REG_SZ", STARTUP_REG, STARTUP_KEY)
    } else {
        try RegDelete(STARTUP_REG, STARTUP_KEY)
    }
}

ToggleStartup() {
    current := LoadStartupPref()
    newVal  := !current
    SaveStartupPref(newVal)
    ApplyStartupRegistry(newVal)
    UpdateTrayMenu()
}

; ============================================================
;  OSD PREFERENCE
; ============================================================
LoadOSDPref() {
    try {
        val := IniRead(CONFIG_FILE, "Settings", "ShowOSD", "1")
        return (val = "1")
    }
    return true
}

SaveOSDPref(enabled) {
    IniWrite(enabled ? "1" : "0", CONFIG_FILE, "Settings", "ShowOSD")
}

ToggleOSD() {
    global g_osdEnabled
    g_osdEnabled := !g_osdEnabled
    SaveOSDPref(g_osdEnabled)
    if (!g_osdEnabled)
        HideOSD()
    UpdateTrayMenu()
}

; ============================================================
;  TRAY MENU
; ============================================================
BuildTrayMenu() {
    A_TrayMenu.Delete()

    A_TrayMenu.Add("TabScroll v1.2", (*) => "")
    A_TrayMenu.Disable("TabScroll v1.2")
    A_TrayMenu.Add()

    A_TrayMenu.Add("⏸️ Pause   Ctrl+Alt+P", (*) => TogglePause())
    A_TrayMenu.Add()

    startupLabel := LoadStartupPref()
        ? "✅ Khởi động cùng Windows"
        : "☐  Khởi động cùng Windows"
    A_TrayMenu.Add(startupLabel, (*) => ToggleStartup())

    osdLabel := LoadOSDPref()
        ? "✅ Hiện OSD khi đổi tab"
        : "☐  Hiện OSD khi đổi tab"
    A_TrayMenu.Add(osdLabel, (*) => ToggleOSD())

    A_TrayMenu.Add()
    A_TrayMenu.Add("❌ Quit   Ctrl+Alt+Q", (*) => ExitApp())

    A_TrayMenu.Default := "⏸️ Pause   Ctrl+Alt+P"
}

UpdateTrayMenu() {
    BuildTrayMenu()
}

; ============================================================
;  HELPER: kiểm tra window dưới con trỏ có thể intercept không
;  Thay thế whitelist — tự động hoạt động với mọi app có tab
; ============================================================
IsInterceptable() {
    MouseGetPos(,, &hWnd)
    if !hWnd
        return false
    try {
        ; Không có titlebar (WS_CAPTION) → fullscreen hoặc borderless game
        style := WinGetStyle(hWnd)
        if !(style & 0xC00000)
            return false

        ; Minimized
        if WinGetMinMax(hWnd) = -1
            return false

        return true
    } catch {
        return false
    }
}

; ============================================================
;  HELPER: đảm bảo window dưới con trỏ có focus
; ============================================================
EnsureFocus() {
    MouseGetPos(,, &hWnd)
    try {
        if (WinExist(hWnd) && WinGetMinMax(hWnd) != -1)
            WinActivate(hWnd)
    }
}

; ============================================================
;  OSD — khởi tạo 1 lần, update text mỗi notch
; ============================================================
InitOSD() {
    global g_osdGui, g_osdText

    static w := 160
    static h := 46

    g_osdGui := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20")
    g_osdGui.BackColor := "1A1A1A"
    g_osdGui.MarginX   := 0
    g_osdGui.MarginY   := 0
    g_osdGui.SetFont("s13 bold", "Segoe UI")

    textY    := (h - 20) // 2
    g_osdText := g_osdGui.AddText("x0 y" textY " w" w " Center", "")

    MonitorGetWorkArea(MonitorGetPrimary(), &mL, &mT, &mR, &mB)
    posX := mR - w - 24
    posY := mT + 48

    g_osdGui.Show("x" posX " y" posY " w" w " h" h " NoActivate Hide")

    ; Bo góc pill — chỉ chạy 1 lần duy nhất
    try DllCall("SetWindowRgn",
        "Ptr", g_osdGui.Hwnd,
        "Ptr", DllCall("CreateRoundRectRgn",
            "Int", 0, "Int", 0, "Int", w, "Int", h,
            "Int", h, "Int", h),
        "Int", true)

    WinSetTransparent(225, g_osdGui)
}

ShowOSD() {
    global g_osdGui, g_osdText, g_scrollCount, g_scrollDir, g_osdEnabled
    if !g_osdEnabled
        return

    arrow := (g_scrollDir > 0) ? "→" : "←"
    count := Abs(g_scrollCount)
    label := (count = 1) ? "tab" : "tabs"
    color := (g_scrollDir > 0) ? "F0C040" : "C8C8C8"

    ; Chỉ update text + màu — không tạo/hủy gì cả
    g_osdText.SetFont("c" color)
    g_osdText.Value := arrow . "  " . count . " " . label

    g_osdGui.Show("NoActivate")
    SetTimer(HideOSD, -1000)
}

HideOSD() {
    global g_osdGui
    g_osdGui.Hide()
}

; ============================================================
;  RButton — intercept để phân biệt gesture vs click phải thật
; ============================================================
*RButton::
{
    global g_gestureActive, g_scrollCount, g_scrollDir, g_isTabApp
    ; Safety: release Ctrl nếu còn kẹt từ gesture trước
    if GetKeyState("Ctrl", "P")
        Send "{Ctrl Up}"
    g_gestureActive := false
    g_scrollCount   := 0
    g_scrollDir     := 0
    g_isTabApp      := false
}

RButton Up::
{
    global g_gestureActive, g_isTabApp

    if (g_gestureActive && g_isTabApp) {
        ; Nhả Ctrl sau notch cuối cùng
        Send "{Ctrl Up}"
    } else if (!g_gestureActive) {
        Click "Right"
    }

    g_gestureActive := false
    g_scrollCount   := 0
    g_scrollDir     := 0
    g_isTabApp      := false
}

; ============================================================
;  SCROLL HANDLER
; ============================================================
HandleScroll(dir) {
    global g_gestureActive, g_scrollCount, g_scrollDir, g_isTabApp

    if !GetKeyState("RButton", "P") {
        Send (dir > 0) ? "{WheelUp}" : "{WheelDown}"
        return
    }

    if (!g_gestureActive) {
        ; Chỉ check 1 lần duy nhất khi gesture bắt đầu
        if !IsInterceptable() {
            Send (dir > 0) ? "{WheelUp}" : "{WheelDown}"
            return
        }
        g_isTabApp      := true
        g_gestureActive := true
        EnsureFocus()
    }

    if !g_isTabApp {
        Send (dir > 0) ? "{WheelUp}" : "{WheelDown}"
        return
    }

    g_scrollDir   := dir
    g_scrollCount += dir
    if (Abs(g_scrollCount) > 9)
        g_scrollCount := (g_scrollCount > 0) ? 9 : -9

    ; Giữ Ctrl xuyên suốt gesture — chỉ gửi Tab/Shift+Tab mỗi notch
    if !GetKeyState("Ctrl", "P")
        Send "{Ctrl Down}"

    if (dir > 0)
        Send "{Tab}"
    else
        Send "+{Tab}"

    ShowOSD()
}

*WheelUp::   HandleScroll(1)
*WheelDown:: HandleScroll(-1)

; ============================================================
;  HOTKEYS
; ============================================================
#SuspendExempt
^!p:: TogglePause()
^!q:: ExitApp()
#SuspendExempt False

TogglePause() {
    static paused := false
    paused := !paused
    Suspend(paused)
    A_IconTip := paused ? "TabScroll (Paused)" : "TabScroll"
}

; ============================================================
;  KHỞI ĐỘNG
; ============================================================

; Icon tray
if FileExist(ICON_FILE)
    TraySetIcon(ICON_FILE)
else
    TraySetIcon(A_ScriptFullPath)

A_IconTip := "TabScroll"

; Build tray menu
BuildTrayMenu()

; Đồng bộ registry với preference đã lưu (phòng case registry bị xóa ngoài)
ApplyStartupRegistry(LoadStartupPref())

; Load OSD preference
g_osdEnabled := LoadOSDPref()

; Hiện splash
ShowSplash()

; Safety: release Ctrl nếu app tắt giữa gesture
OnExit((_*) => (GetKeyState("Ctrl", "P") ? Send("{Ctrl Up}") : ""))

; Khởi tạo OSD window 1 lần
InitOSD()

; ============================================================
;  TOAST NOTIFICATION — TabScroll brand style
; ============================================================

ShowToast(msg := "TabScroll is running in the system tray.", duration := 3000) {
    static W := 410
    static H := 58

    toast := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20")
    toast.BackColor := "181818"
    toast.MarginX := 0
    toast.MarginY := 0

    ; --- Gold accent bar (left edge) ---
    accent := toast.AddProgress("x0 y0 w3 h" H " Backgroundc9a84c Range0-100", 100)

    ; --- Logo mark "[T]" in gold ---
    logo := toast.AddText("x14 y0 w30 h" H " Center 0x200 BackgroundTrans", "[T]")
    logo.SetFont("s9 w700 cc9a84c", "Courier New")

    ; --- App name ---
    appName := toast.AddText("x48 y10 w" (W - 62) " h18 BackgroundTrans", "TABSCROLL")
    appName.SetFont("s8 w700 cc9a84c", "Courier New")

    ; --- Message ---
    body := toast.AddText("x48 y27 w" (W - 62) " h20 BackgroundTrans", msg)
    body.SetFont("s9 cffffff", "Courier New")

    ; --- Thin gold bottom border (dùng Progress ngang) ---
    bottom := toast.AddProgress("x0 y" (H - 1) " w" W " h1 Backgroundc9a84c Range0-100", 100)

    ; --- Position: bottom-right above taskbar ---
    MonitorGetWorkArea(MonitorGetPrimary(), &mL, &mT, &mR, &mB)
    toast.Show("x" (mR - W - 20) " y" (mB - H - 16) " w" W " h" H " NoActivate")

    ; --- Bo góc Windows 11+ ---
    try DllCall("dwmapi\DwmSetWindowAttribute",
        "Ptr", WinExist("ahk_id " toast.Hwnd),
        "UInt", 33, "Int*", 2, "UInt", 4)

    ; --- Fade in ---
    Loop 10 {
        WinSetTransparent(A_Index * 23, toast)
        Sleep(16)
    }

    ; --- Fade out & destroy ---
    SetTimer(_FadeOut.Bind(toast), -duration)

    _FadeOut(t) {
        Loop 10 {
            WinSetTransparent(230 - A_Index * 23, t)
            Sleep(16)
        }
        t.Destroy()
    }
}

ShowToast()