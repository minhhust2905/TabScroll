; ============================================================
;  TabScroll — RButton + Wheel = Switch Tab
;  Version: 1.2
;  Requirement: AutoHotkey v2.0+
; ============================================================
;
; Usage:
;    - Hold Right Click + Scroll Up   → Next tab (Ctrl+Tab)
;    - Hold Right Click + Scroll Down → Previous tab (Ctrl+Shift+Tab)
;    - Hold Right Click + No Scroll   → Normal right click
;    - Outside supported apps         → Normal scroll
;
; Features:
;    - Startup Splash screen (Thumbnail.png)
;    - Single Instance: Restarting will replace the old instance
;    - "Start with Windows" option in tray menu (Saved to .ini)
;    - OSD scroll count limited to max ±9
; ============================================================

#Requires AutoHotkey v2.0
#SingleInstance Force   ; If run again → automatically close old instance
#UseHook True

A_MenuMaskKey := "vkE8"

; ============================================================
;  CONFIG — File Paths
; ============================================================
global CONFIG_FILE  := A_ScriptDir . "\TabScroll.ini"
global SPLASH_IMAGE := A_ScriptDir . "\Thumbnail.png"
global ICON_FILE    := A_ScriptDir . "\TabScroll.ico"
global STARTUP_KEY  := "TabScroll"
global STARTUP_REG  := "HKCU\Software\Microsoft\Windows\CurrentVersion\Run"

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
;  Shows Thumbnail.png at screen center for ~1.5s on startup
; ============================================================
ShowSplash() {
    if !FileExist(SPLASH_IMAGE)
        return

    splash := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20")
    splash.BackColor := "1A1A1A"
    splash.MarginX := 0
    splash.MarginY := 0

    pic := splash.AddPicture("w240 h-1", SPLASH_IMAGE)   ; Keep aspect ratio, width 240px

    picW := 240
    picH := pic.Value  ; AHK returns actual height after scale

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

    ; Round corners
    try DllCall("SetWindowRgn",
        "Ptr", splash.Hwnd,
        "Ptr", DllCall("CreateRoundRectRgn",
            "Int", 0, "Int", 0, "Int", winW, "Int", winH,
            "Int", 16, "Int", 16),
        "Int", true)

    WinSetTransparent(230, splash)

    ; Auto-close after 1500ms
    SetTimer(() => splash.Destroy(), -1500)
}

; ============================================================
;  FEATURE 2 — STARTUP WITH WINDOWS
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
;  FEATURE 3 — OSD PREFERENCE
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

    A_TrayMenu.Add("TabScroll", (*) => "")
    A_TrayMenu.Disable("TabScroll")
    A_TrayMenu.Add()

    A_TrayMenu.Add("⏸️ Pause   Ctrl+Alt+P", (*) => TogglePause())
    A_TrayMenu.Add()

    startupLabel := LoadStartupPref()
        ? "✅ Start with Windows"
        : "☐  Start with Windows"
    A_TrayMenu.Add(startupLabel, (*) => ToggleStartup())

    osdLabel := LoadOSDPref()
        ? "✅ Show OSD on tab switch"
        : "☐  Show OSD on tab switch"
    A_TrayMenu.Add(osdLabel, (*) => ToggleOSD())

    A_TrayMenu.Add()
    A_TrayMenu.Add("❌ Quit   Ctrl+Alt+Q", (*) => ExitApp())

    A_TrayMenu.Default := "⏸️ Pause   Ctrl+Alt+P"
}

UpdateTrayMenu() {
    BuildTrayMenu()
}

; ============================================================
;  HELPERS
; ============================================================
IsInterceptable() {
    MouseGetPos(,, &hWnd)
    if !hWnd
        return false
    try {
        style := WinGetStyle(hWnd)
        if !(style & 0xC00000) ; No titlebar (Fullscreen/Borderless)
            return false

        if WinGetMinMax(hWnd) = -1 ; Minimized
            return false

        return true
    } catch {
        return false
    }
}

EnsureFocus() {
    MouseGetPos(,, &hWnd)
    try {
        if (WinExist(hWnd) && WinGetMinMax(hWnd) != -1)
            WinActivate(hWnd)
    }
}

; ============================================================
;  OSD — Initialize once, update text per notch
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
;  HOTKEYS & GESTURE HANDLERS
; ============================================================
*RButton::
{
    global g_gestureActive, g_scrollCount, g_scrollDir, g_isTabApp
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
        Send "{Ctrl Up}"
    } else if (!g_gestureActive) {
        Click "Right"
    }

    g_gestureActive := false
    g_scrollCount   := 0
    g_scrollDir     := 0
    g_isTabApp      := false
}

HandleScroll(dir) {
    global g_gestureActive, g_scrollCount, g_scrollDir, g_isTabApp

    if !GetKeyState("RButton", "P") {
        Send (dir > 0) ? "{WheelUp}" : "{WheelDown}"
        return
    }

    if (!g_gestureActive) {
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
;  INITIALIZATION
; ============================================================

if FileExist(ICON_FILE)
    TraySetIcon(ICON_FILE)
else
    TraySetIcon(A_ScriptFullPath)

A_IconTip := "TabScroll"

BuildTrayMenu()
ApplyStartupRegistry(LoadStartupPref())
g_osdEnabled := LoadOSDPref()
ShowSplash()
OnExit((_*) => (GetKeyState("Ctrl", "P") ? Send("{Ctrl Up}") : ""))
InitOSD()

; ============================================================
;  TOAST NOTIFICATION
; ============================================================
ShowToast(msg := "TabScroll is running in the system tray.", duration := 3000) {
    static W := 410
    static H := 58

    toast := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20")
    toast.BackColor := "181818"
    toast.MarginX := 0
    toast.MarginY := 0

    accent := toast.AddProgress("x0 y0 w3 h" H " Backgroundc9a84c Range0-100", 100)
    logo := toast.AddText("x14 y0 w30 h" H " Center 0x200 BackgroundTrans", "[T]")
    logo.SetFont("s9 w700 cc9a84c", "Courier New")

    appName := toast.AddText("x48 y10 w" (W - 62) " h18 BackgroundTrans", "TABSCROLL")
    appName.SetFont("s8 w700 cc9a84c", "Courier New")

    body := toast.AddText("x48 y27 w" (W - 62) " h20 BackgroundTrans", msg)
    body.SetFont("s9 cffffff", "Courier New")

    bottom := toast.AddProgress("x0 y" (H - 1) " w" W " h1 Backgroundc9a84c Range0-100", 100)

    MonitorGetWorkArea(MonitorGetPrimary(), &mL, &mT, &mR, &mB)
    toast.Show("x" (mR - W - 20) " y" (mB - H - 16) " w" W " h" H " NoActivate")

    try DllCall("dwmapi\DwmSetWindowAttribute",
        "Ptr", WinExist("ahk_id " toast.Hwnd),
        "UInt", 33, "Int*", 2, "UInt", 4)

    Loop 10 {
        WinSetTransparent(A_Index * 23, toast)
        Sleep(16)
    }

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