#Requires AutoHotkey v2.0
#SingleInstance Force
Persistent

; ponytail: SWP_NOSENDCHANGING (0x400) skips WM_WINDOWPOSCHANGING so app can't
; clamp in that handler. If target also clamps in WM_SIZE (rare), size snaps
; back — then need DLL injection to hook WM_GETMINMAXINFO.
FLAGS := 0x0004 | 0x0010 | 0x0400  ; NOZORDER | NOACTIVATE | NOSENDCHANGING

state := { hwnd: 0, proc: "", armed: false }

g := Gui("+AlwaysOnTop +ToolWindow", "Force Resize")
g.SetFont("s10")
lbl := g.Add("Text", "w360 cBlue", "Target: (none)")
g.Add("Text", "w360 y+8",
    "1. 🎯 Sniper → click cửa sổ cần bỏ giới hạn`n"
    . "2. Giữ Win+Shift rồi drag chuột (bất cứ đâu trên màn)`n"
    . "   → bottom-right corner của target sẽ bám theo cursor")
btn := g.Add("Button", "w120 y+10", "🎯 Sniper")
btn.OnEvent("Click", (*) => StartSnipe())
g.OnEvent("Close", (*) => g.Hide())
g.Show()

A_TrayMenu.Delete()
A_TrayMenu.Add("Show", (*) => g.Show())
A_TrayMenu.Add("Sniper", (*) => (g.Show(), StartSnipe()))
A_TrayMenu.Add("Exit", (*) => ExitApp())
A_TrayMenu.Default := "Show"

StartSnipe() {
    g.Hide()
    ToolTip("🎯 Click on target window (Esc = cancel)")
    Hotkey("*LButton", Pick, "On")
    Hotkey("*Esc", CancelSnipe, "On")
}

Pick(*) {
    MouseGetPos(, , &hwnd)
    StopSnipe()
    if hwnd {
        state.hwnd := hwnd
        state.proc := ProcessGetName(WinGetPID("ahk_id " hwnd))
        lbl.Text := "Target: " state.proc "  (hwnd " hwnd ")"
        if !state.armed {
            Hotkey("#+LButton", FreeDrag, "On")
            state.armed := true
        }
    }
    g.Show()
}

CancelSnipe(*) {
    StopSnipe()
    g.Show()
}

StopSnipe() {
    ToolTip()
    try Hotkey("*LButton", "Off")
    try Hotkey("*Esc", "Off")
}

FreeDrag(*) {
    if !state.hwnd || !WinExist("ahk_id " state.hwnd)
        return
    WinGetPos(&x, &y, , , "ahk_id " state.hwnd)
    while GetKeyState("LButton", "P") {
        MouseGetPos(&mx, &my)
        w := Max(1, mx - x)
        h := Max(1, my - y)
        DllCall("SetWindowPos", "Ptr", state.hwnd, "Ptr", 0
            , "Int", 0, "Int", 0, "Int", w, "Int", h, "UInt", FLAGS)
        Sleep 10
    }
}
