; ============================================================
;  TabScroll — RButton + Wheel = Switch Tab
;  Version: 1.3
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
;    - Startup Splash screen (Logo.png)
;    - Single Instance: Restarting will replace the old instance
;    - "Start with Windows" option in tray menu (Saved to .ini)
;    - OSD scroll count limited to max ±9
;    - Scroll sensitivity threshold (ScrollThreshold)
;    - App blacklist support (Blacklist)
;
; TabScroll.ini Options:
;    [Settings]
;    StartWithWindows = 0 or 1
;    ShowOSD          = 0 or 1
;    ScrollThreshold  = 1 (notches required to switch 1 tab, default: 1)
;    Blacklist        = comma-separated exe names (e.g. photoshop.exe,game.exe)
; ============================================================

#Requires AutoHotkey v2.0
#SingleInstance Force   ; If run again → automatically close old instance
#UseHook True

A_MenuMaskKey := "vkE8"

; ============================================================
;  CONFIG — File Paths
; ============================================================
global CONFIG_FILE  := A_ScriptDir . "\TabScroll.ini"
global SPLASH_IMAGE := A_ScriptDir . "\Logo.png"
global ICON_FILE    := A_ScriptDir . "\TabScroll.ico"
global STARTUP_KEY  := "TabScroll"
global STARTUP_REG  := "HKCU\Software\Microsoft\Windows\CurrentVersion\Run"

; ── Runtime config (loaded from .ini) ──
global g_scrollThreshold := 1
global g_blacklist       := []

; ============================================================
;  STATE
; ============================================================
global g_gestureActive  := false
global g_scrollCount    := 0
global g_scrollDir      := 0
global g_isTabApp       := false
global g_osdGui         := unset
global g_osdText        := unset
global g_osdEnabled     := true

; ============================================================
;  CONFIG LOADER
; ============================================================
LoadConfig() {
    global g_scrollThreshold, g_blacklist

    ; ScrollThreshold
    try {
        val := IniRead(CONFIG_FILE, "Settings", "ScrollThreshold", "1")
        g_scrollThreshold := Max(1, Integer(val))
    }

    ; Blacklist
    try {
        val := IniRead(CONFIG_FILE, "Settings", "Blacklist", "")
        if (val != "") {
            parts := StrSplit(val, ",")
            for item in parts {
                trimmed := Trim(item)
                if (trimmed != "")
                    g_blacklist.Push(StrLower(trimmed))
            }
        }
    }
}

; ============================================================
;  FEATURE 1 — SPLASH SCREEN
;  Shows Logo.png at screen center for ~1.5s on startup
; ============================================================
ShowSplash() {
    if !FileExist(SPLASH_IMAGE)
        return

    splash := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20")
    splash.BackColor := "010101"
    splash.MarginX := 0
    splash.MarginY := 0
    splash.AddPicture("w200 h200", SPLASH_IMAGE)

    splash.Show("w200 h200 Center NoActivate")
    WinSetTransColor("010101", splash)   
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
        target := '"' . A_AhkPath . '" "' . A_ScriptFullPath . '"'
        RegWrite(target, "REG_SZ", STARTUP_REG, STARTUP_KEY)
    } else {
        try RegDelete(STARTUP_REG, STARTUP_KEY)
    }
}

; Auto-fix registry path if folder was moved
SyncStartupRegistry() {
    if !LoadStartupPref()
        return
    try {
        saved := RegRead(STARTUP_REG, STARTUP_KEY)
        expected := '"' . A_ScriptDir . '\AutoHotkey64.exe" "' . A_ScriptFullPath . '"'
        if (saved != expected)
            RegWrite(expected, "REG_SZ", STARTUP_REG, STARTUP_KEY)
    }
}

ToggleStartup() {
    current := LoadStartupPref()
    newVal  := !current
    SaveStartupPref(newVal)
    try {
        ApplyStartupRegistry(newVal)
        UpdateTrayMenu()
        ShowToast(newVal ? "Start with Windows: Enabled" : "Start with Windows: Disabled")
    } catch {
        ShowToast("Error: Could not update startup setting.")
    }
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
    ShowToast(g_osdEnabled ? "OSD: Enabled" : "OSD: Disabled")
}

; ============================================================
;  TRAY MENU
; ============================================================

; ── Advanced Settings handlers ──
SetThreshold(val) {
    global g_scrollThreshold
    g_scrollThreshold := val
    IniWrite(val, CONFIG_FILE, "Settings", "ScrollThreshold")
    UpdateTrayMenu()
    ShowToast("Scroll Threshold: " val " notch" (val > 1 ? "es" : ""))
}

OpenBlacklist() {
    ; Ensure Blacklist key exists in .ini
    try {
        IniRead(CONFIG_FILE, "Settings", "Blacklist")
    } catch {
        IniWrite("", CONFIG_FILE, "Settings", "Blacklist")
    }
    Run('notepad.exe "' CONFIG_FILE '"')
}

BuildTrayMenu() {
    global g_scrollThreshold

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

    ; ── Advanced Settings submenu ──
    advMenu := Menu()

    ; Scroll Threshold submenu
    threshMenu := Menu()
    threshMenu.Add("1 notch" . (g_scrollThreshold = 1 ? "  ✓" : ""), (*) => SetThreshold(1))
    threshMenu.Add("2 notches" . (g_scrollThreshold = 2 ? "  ✓" : ""), (*) => SetThreshold(2))
    threshMenu.Add("3 notches" . (g_scrollThreshold = 3 ? "  ✓" : ""), (*) => SetThreshold(3))
    advMenu.Add("Scroll Threshold: " g_scrollThreshold, threshMenu)

    advMenu.Add()
    advMenu.Add("Edit Blacklist...", (*) => OpenBlacklist())

    A_TrayMenu.Add("⚙️ Advanced Settings", advMenu)

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
    global g_blacklist
    MouseGetPos(,, &hWnd)
    if !hWnd
        return false
    try {
        style := WinGetStyle(hWnd)
        if !(style & 0xC00000) ; No titlebar (Fullscreen/Borderless)
            return false

        if WinGetMinMax(hWnd) = -1 ; Minimized
            return false

        ; Check blacklist
        if (g_blacklist.Length > 0) {
            try {
                procName := StrLower(WinGetProcessName(hWnd))
                for exe in g_blacklist {
                    if (procName = exe)
                        return false
                }
            }
        }

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
    if !IsSet(g_osdGui)
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
    ; else: gesture started but not a tab app — just release cleanly

    g_gestureActive := false
    g_scrollCount   := 0
    g_scrollDir     := 0
    g_isTabApp      := false
}

HandleScroll(dir) {
    global g_gestureActive, g_scrollCount, g_scrollDir, g_isTabApp

    ; Pass through if right button not held
    if !GetKeyState("RButton", "P") {
        Send (dir > 0) ? "{WheelUp}" : "{WheelDown}"
        return
    }

    ; First scroll — decide whether to intercept
    if (!g_gestureActive) {
        if !IsInterceptable() {
            Send (dir > 0) ? "{WheelUp}" : "{WheelDown}"
            return
        }
        g_isTabApp      := true
        g_gestureActive := true
        s_notchAccum    := 0
        EnsureFocus()
    }

    ; Sensitivity threshold — accumulate notches
    global g_scrollThreshold
    static s_notchAccum := 0
    s_notchAccum += dir
    if (Abs(s_notchAccum) < g_scrollThreshold)
        return
    s_notchAccum := 0

    ; Switch tab
    g_scrollDir   := dir
    g_scrollCount += dir
    if (Abs(g_scrollCount) > 9)
        g_scrollCount := (g_scrollCount > 0) ? 9 : -9

    if !GetKeyState("Ctrl", "P")
        Send "{Ctrl Down}"

    Send (dir > 0) ? "{Tab}" : "+{Tab}"

    ShowOSD()
}

*WheelUp::   HandleScroll(1)
*WheelDown:: HandleScroll(-1)

; Release Ctrl if window loses focus mid-gesture (e.g. Alt+Tab)
~Alt::
~LWin::
{
    global g_gestureActive, g_isTabApp
    if (g_gestureActive && g_isTabApp && GetKeyState("Ctrl", "P"))
        Send "{Ctrl Up}"
    g_gestureActive := false
    g_scrollCount   := 0
    g_scrollDir     := 0
    g_isTabApp      := false
}

#SuspendExempt
^!p:: TogglePause()
^!q:: ExitApp()
#SuspendExempt False

TogglePause() {
    static paused := false
    paused := !paused
    Suspend(paused)
    A_IconTip := paused ? "TabScroll (Paused)" : "TabScroll"
    ShowToast(paused ? "⏸️  TabScroll Paused" : "▶️  TabScroll Resumed")
}

; ============================================================
;  INITIALIZATION
; ============================================================

if FileExist(ICON_FILE)
    TraySetIcon(ICON_FILE)
else
    ShowToast("Warning: TabScroll.ico not found.")

A_IconTip := "TabScroll"

BuildTrayMenu()
LoadConfig()
SyncStartupRegistry()
g_osdEnabled := LoadOSDPref()
ShowSplash()
if !FileExist(SPLASH_IMAGE)
    ShowToast("Warning: Logo.png not found.")
OnExit(OnAppExit)
OnAppExit(_*) {
    if GetKeyState("Ctrl", "P")
        Send "{Ctrl Up}"
    try g_osdGui.Destroy()
}
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
