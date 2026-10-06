#Requires AutoHotkey v2.0
#SingleInstance Force
Persistent

; Sniper không click được 1 số cửa sổ (chạy quyền admin) vì UIPI chặn input hook
; của 1 process non-elevated lên window elevated → tự nâng quyền admin ngay khi start.
EnsureAdmin()

; ponytail: SWP_NOSENDCHANGING (0x400) skips WM_WINDOWPOSCHANGING so app can't
; clamp in that handler. If target also clamps in WM_SIZE (rare), size snaps
; back — then need DLL injection to hook WM_GETMINMAXINFO.
FLAGS := 0x0004 | 0x0010 | 0x0400  ; NOZORDER | NOACTIVATE | NOSENDCHANGING

global ConfigFile := A_ScriptDir "\ForceResize.ini"

state := { hwnd: 0, proc: "", armed: false }
global plHwnds := []        ; map row index -> hwnd trong Process List picker
global plGui := ""

g := Gui("+AlwaysOnTop +ToolWindow", "Force Resize")
g.SetFont("s10")
lbl := g.Add("Text", "w380 cBlue", "Target: (none)")
g.Add("Text", "w380 y+8",
    "1. 🎯 Sniper (click) hoặc 📋 Process List (chọn) để set target`n"
    . "2. Giữ Win+Shift rồi drag chuột → bottom-right bám theo cursor`n"
    . "3. 💾 Remember: lưu pos+size hiện tại của target (key theo process name)`n"
    . "4. ✅ Apply: set lại pos+size cho tất cả process đã lưu")

btnSnipe := g.Add("Button", "w120 y+10 section", "🎯 Sniper")
btnSnipe.OnEvent("Click", (*) => StartSnipe())
btnList := g.Add("Button", "w130 ys", "📋 Process List")
btnList.OnEvent("Click", (*) => ShowProcessList())

btnSave := g.Add("Button", "w120 xs section", "💾 Remember")
btnSave.OnEvent("Click", (*) => SaveProfile())
btnApply := g.Add("Button", "w100 ys", "✅ Apply")
btnApply.OnEvent("Click", (*) => ApplyAll())
btnDel := g.Add("Button", "w100 ys", "🗑 Delete")
btnDel.OnEvent("Click", (*) => DeleteProfile())

g.Add("Text", "xs w380 y+12", "Đã lưu (process → position + size):")
lvProf := g.Add("ListView", "xs w380 h170 Grid -Multi", ["Process", "X", "Y", "W", "H"])
lvProf.ModifyCol(1, 150)
lvProf.OnEvent("DoubleClick", (*) => ApplySelected())

g.OnEvent("Close", (*) => g.Hide())
RefreshProfiles()
g.Show()

A_TrayMenu.Delete()
A_TrayMenu.Add("Show", (*) => g.Show())
A_TrayMenu.Add("Sniper", (*) => (g.Show(), StartSnipe()))
A_TrayMenu.Add("Apply saved", (*) => ApplyAll())
A_TrayMenu.Add("Exit", (*) => ExitApp())
A_TrayMenu.Default := "Show"

; --- Nâng quyền admin (chạy 1 lần, nếu UAC bị từ chối thì chạy tiếp non-elevated) ---
EnsureAdmin() {
    if A_IsAdmin
        return
    full := DllCall("GetCommandLine", "str")
    if RegExMatch(full, " /restart(?!\S)")   ; đã thử rồi, tránh loop
        return
    try {
        if A_IsCompiled
            Run '*RunAs "' A_ScriptFullPath '" /restart'
        else
            Run '*RunAs "' A_AhkPath '" /restart "' A_ScriptFullPath '"'
        ExitApp
    }
    ; UAC bị từ chối → tiếp tục non-elevated (vẫn resize được window thường)
}

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
        SetTarget(RootWindow(hwnd))
    }
    g.Show()
}

; Resolve về top-level/root window thật. MouseGetPos có thể trả hwnd của window
; owned/popup; GA_ROOT (2) lấy root, đảm bảo SetWindowPos tác động đúng cửa sổ.
RootWindow(hwnd) {
    root := DllCall("GetAncestor", "Ptr", hwnd, "UInt", 2, "Ptr")
    return root ? root : hwnd
}

SetTarget(hwnd) {
    state.hwnd := hwnd
    state.proc := ProcessGetName(WinGetPID("ahk_id " hwnd))
    lbl.Text := "Target: " state.proc "  (hwnd " hwnd ")"
    if !state.armed {
        Hotkey("#+LButton", FreeDrag, "On")
        state.armed := true
    }
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

; ---------------------------------------------------------------------------
;  PROCESS LIST PICKER
; ---------------------------------------------------------------------------
ShowProcessList() {
    global plGui, plHwnds
    if (plGui is Gui)
        try plGui.Destroy()
    plHwnds := []

    plGui := Gui("+AlwaysOnTop +ToolWindow +Owner" g.Hwnd, "Chọn cửa sổ / process")
    plGui.SetFont("s10")
    plGui.Add("Text", "w520", "Double-click (hoặc chọn + Chọn) để set target:")
    lv := plGui.Add("ListView", "w520 h320 Grid -Multi vLV", ["Process", "Title", "hwnd"])

    for hwnd in WinGetList() {
        title := ""
        try title := WinGetTitle("ahk_id " hwnd)
        if (title == "")
            continue
        style := 0
        try style := WinGetStyle("ahk_id " hwnd)
        if !(style & 0x10000000)        ; WS_VISIBLE
            continue
        proc := ""
        try proc := ProcessGetName(WinGetPID("ahk_id " hwnd))
        if (proc == "")
            continue
        plHwnds.Push(hwnd)
        lv.Add("", proc, title, hwnd)
    }
    lv.ModifyCol(1, 150)
    lv.ModifyCol(2, 300)
    lv.ModifyCol(3, 0)      ; ẩn cột hwnd
    lv.OnEvent("DoubleClick", PickFromList)

    btnPick := plGui.Add("Button", "w100 Default", "Chọn")
    btnPick.OnEvent("Click", (*) => PickFromList(lv, lv.GetNext()))
    btnRe := plGui.Add("Button", "w100 x+8", "Refresh")
    btnRe.OnEvent("Click", (*) => ShowProcessList())
    btnClose := plGui.Add("Button", "w100 x+8", "Đóng")
    btnClose.OnEvent("Click", (*) => plGui.Destroy())
    plGui.Show()

    PickFromList(ctrl, row, *) {
        if !row
            return
        hwnd := plHwnds[row]
        if (hwnd && WinExist("ahk_id " hwnd)) {
            SetTarget(hwnd)
            try plGui.Destroy()
            g.Show()
        }
    }
}

; ---------------------------------------------------------------------------
;  LƯU / ÁP DỤNG CONFIG (key theo process name)
; ---------------------------------------------------------------------------
SaveProfile() {
    if !state.hwnd || !WinExist("ahk_id " state.hwnd) {
        MsgBox("Chưa có target hợp lệ. Dùng 🎯 Sniper hoặc 📋 Process List trước.",
            "Force Resize", "Icon!")
        return
    }
    WinGetPos(&x, &y, &w, &h, "ahk_id " state.hwnd)
    IniWrite(x, ConfigFile, state.proc, "X")
    IniWrite(y, ConfigFile, state.proc, "Y")
    IniWrite(w, ConfigFile, state.proc, "W")
    IniWrite(h, ConfigFile, state.proc, "H")
    RefreshProfiles()
    ToolTip("💾 Đã lưu: " state.proc " → " x "," y " " w "x" h)
    SetTimer(() => ToolTip(), -1500)
}

; Áp dụng config đã lưu cho MỌI process matching đang chạy (1 nút Apply).
ApplyAll() {
    count := 0
    for proc in SavedProcesses()
        count += ApplyProfileToProcess(proc)
    ToolTip("✅ Applied cho " count " cửa sổ")
    SetTimer(() => ToolTip(), -1500)
}

; Áp dụng chỉ profile đang chọn trong ListView.
ApplySelected() {
    row := lvProf.GetNext()
    if !row
        return
    proc := lvProf.GetText(row, 1)
    n := ApplyProfileToProcess(proc)
    ToolTip("✅ " proc " → " n " cửa sổ")
    SetTimer(() => ToolTip(), -1500)
}

ApplyProfileToProcess(proc) {
    x := IniRead(ConfigFile, proc, "X", "")
    y := IniRead(ConfigFile, proc, "Y", "")
    w := IniRead(ConfigFile, proc, "W", "")
    h := IniRead(ConfigFile, proc, "H", "")
    if (x == "" || y == "" || w == "" || h == "")
        return 0
    applied := 0
    for hwnd in WinGetList() {
        title := ""
        try title := WinGetTitle("ahk_id " hwnd)
        if (title == "")
            continue
        pname := ""
        try pname := ProcessGetName(WinGetPID("ahk_id " hwnd))
        if (pname != proc)
            continue
        ; Khôi phục nếu đang maximize/minimize để move+size có hiệu lực
        try {
            if (WinGetMinMax("ahk_id " hwnd) != 0)
                WinRestore("ahk_id " hwnd)
        }
        DllCall("SetWindowPos", "Ptr", hwnd, "Ptr", 0
            , "Int", x, "Int", y, "Int", w, "Int", h, "UInt", FLAGS)
        applied++
    }
    return applied
}

DeleteProfile() {
    row := lvProf.GetNext()
    if !row {
        MsgBox("Chọn 1 dòng để xoá.", "Force Resize", "Icon!")
        return
    }
    proc := lvProf.GetText(row, 1)
    try IniDelete(ConfigFile, proc)
    RefreshProfiles()
}

SavedProcesses() {
    list := []
    sections := ""
    try sections := IniRead(ConfigFile)
    for line in StrSplit(sections, "`n", "`r") {
        name := Trim(line)
        if (name != "")
            list.Push(name)
    }
    return list
}

RefreshProfiles() {
    lvProf.Delete()
    for proc in SavedProcesses() {
        x := IniRead(ConfigFile, proc, "X", "")
        y := IniRead(ConfigFile, proc, "Y", "")
        w := IniRead(ConfigFile, proc, "W", "")
        h := IniRead(ConfigFile, proc, "H", "")
        lvProf.Add("", proc, x, y, w, h)
    }
}
