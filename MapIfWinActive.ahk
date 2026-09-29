#Requires AutoHotkey v2.0
EnsureRestartFlag()
EnsureStartupEntry()

jetbrainsExes := ["phpstorm64.exe", "pycharm64.exe", "rider64.exe", "rustrover64.exe"]

IsJetBrainsActive() {
    global jetbrainsExes
    for exe in jetbrainsExes
        if WinActive("ahk_exe " exe)
            return true
    return false
}

; Tray menu — chèn "Manage Shortcuts" lên đầu, GIỮ NGUYÊN menu chuẩn của AHK.
; Mục "Open" chuẩn mở cửa sổ chính = debug built-in (View → Lines/Variables/Hotkeys/Key History).
A_TrayMenu.Insert("1&", "Manage Shortcuts", (*) => ShowManagerGui())
A_TrayMenu.Insert("2&")   ; separator ngăn với các mục chuẩn
A_TrayMenu.Default := "Manage Shortcuts"
try TraySetIcon("shell32.dll", 44)

EnsureRestartFlag() {
    fullCmd := StrGet(DllCall("GetCommandLineW", "Ptr"), "UTF-16")
    if !InStr(fullCmd, "/restart") {
        if A_IsCompiled
            Run('"' A_ScriptFullPath '" /restart')
        else
            Run('"' A_AhkPath '" /restart "' A_ScriptFullPath '"')
        ExitApp()
    }
}

EnsureStartupEntry() {
    entryName := "MapIfWinActive"
    if A_IsCompiled
        entryCmd := '"' A_ScriptFullPath '" /restart'
    else
        entryCmd := '"' A_AhkPath '" /restart "' A_ScriptFullPath '"'

    Loop Reg, "HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Run", "KVR" {
        if (A_LoopRegName = entryName) {
            return
        }
    }

    if MsgBox("Add MapIfWinActive to Windows startup?",, "YesNo") = "Yes" {
        RegWrite(entryCmd, "REG_SZ", "HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Run", entryName)
    }
}

; ============================================================
;  ACTION FUNCTIONS
; ============================================================

JetBrainsTabSwitch(*) {
    SetKeyDelay(50, 50)
    Send "{Blind}{Ctrl DownR}{e}{Ctrl up}"
    Sleep(200)
    Send "{Blind}{Enter}"
}

TerminalNewLine(*) {
    saved := A_Clipboard
    A_Clipboard := "`n"
    ClipWait(1)
    Send "^v"
    Sleep 50
    A_Clipboard := saved
}

TerminalTabToRight(*) {
    tt := WinGetTitle("A")
    if !InStr(tt, "✳")
        Send "{Right}"
}

SearchEverywhereCmd(*) {
    if IsJetBrainsActive()
        return
    KeyWait("Shift") ; Chờ người dùng nhả hẳn phím Shift
    SendEvent("#+q") ; Dùng SendEvent thay vì Send để kích hoạt Windows Global Hook tốt hơn
}

ShiftDoubleTap(key:="{LShift}") {
    if (A_PriorHotkey != "~Shift" or A_TimeSincePriorHotkey > 400) {
        KeyWait("Shift")
        return
    }
    SearchEverywhereCmd()
    ; static lastTime := 0, lastKey := ""
    ; now := A_TickCount
    ; if (lastKey = key && now - lastTime < 300) {
        ; lastTime := 0
        ; SearchEverywhereCmd()
    ; } else {
        ; lastTime := now
        ; lastKey := key
    ; }
}

; ============================================================
;  CASE CYCLER — UPPER → lower → Title → Pascal → Original
; ============================================================

global CaseCycleOriginals := Map()

TitleCase(s) {
    result := ""
    boundary := true
    Loop Parse, s {
        ch := A_LoopField
        if (ch ~= "\W")
            result .= ch, boundary := true
        else if boundary
            result .= StrUpper(ch), boundary := false
        else
            result .= StrLower(ch)
    }
    return result
}

PascalCase(s) {
    result := ""
    capNext := true
    Loop Parse, s {
        ch := A_LoopField
        if (ch ~= "\W") {
            capNext := true
            continue
        }
        if capNext
            result .= StrUpper(ch), capNext := false
        else
            result .= StrLower(ch)
    }
    return result
}

CycleCaseSelected(*) {
    KeyWait("Ctrl")
    KeyWait("Shift")
    saved := ClipboardAll()
    A_Clipboard := ""
    Send "+{Del}"
    if !ClipWait(0.5) {
        A_Clipboard := saved
        return
    }
    current := A_Clipboard
    if (current = "") {
        A_Clipboard := saved
        return
    }
    ; Key strips non-word chars → Pascal ("BecomeAnExpert") maps to same
    ; slot as Original ("Become an expert").
    key := StrLower(RegExReplace(current, "\W", ""))
    if !CaseCycleOriginals.Has(key)
        CaseCycleOriginals[key] := current
    original := CaseCycleOriginals[key]

    ; Cycle order; dedupe preserving first occurrence
    raw := [StrUpper(original), StrLower(original), TitleCase(original), PascalCase(original), original]
    forms := []
    seen := Map()
    for f in raw {
        if !seen.Has(f) {
            forms.Push(f)
            seen[f] := true
        }
    }

    idx := 0
    for i, f in forms {
        if (current == f) {
            idx := i
            break
        }
    }
    nextText := forms[Mod(idx, forms.Length) + 1]

    A_Clipboard := nextText
    Send "+{Ins}"
    Sleep 80
    Send "+{Left " StrLen(nextText) "}"
    A_Clipboard := saved
}

; ============================================================
;  CUSTOM SHORTCUTS  (GUI-managed, lưu vào shortcuts.ini)
; ============================================================

global CustomIni := A_ScriptDir "\shortcuts.ini"
global RegisteredCustomKeys := []   ; các [hotkey, winCriteria] đang bật, để tắt khi refresh
global MgrRowIds := []               ; map row index → section id trong GUI

; id deterministic từ command → cùng lệnh dùng lại cùng section (upsert)
CommandId(cmd) {
    s := ""
    for word in StrSplit(Trim(cmd), " ", " `t")
        if (word != "")
            s .= (s = "" ? "" : " ") word
    s := StrLower(s)
    h := 2166136261
    Loop Parse, s {
        h := (h ^ Ord(A_LoopField)) & 0xFFFFFFFF
        h := (h * 16777619) & 0xFFFFFFFF
    }
    return "SC_" Format("{:08x}", h)
}

; Tách chuỗi phân tách ';' thành mảng pattern đã Trim, bỏ phần tử rỗng
SplitPatterns(s) {
    out := []
    for part in StrSplit(s, ";") {
        p := Trim(part)
        if (p != "")
            out.Push(p)
    }
    return out
}

; Loại ký tự không hợp lệ trong tên file .lnk
SanitizeName(name) => RegExReplace(name, '[\\/:*?"<>|]', "_")

CustomLnkPath(name) => A_Desktop "\" SanitizeName(name) ".lnk"

CreateDesktopIcon(name, cmd, workDir, iconPath := "") {
    try {
        if (iconPath != "")
            FileCreateShortcut(A_ComSpec, CustomLnkPath(name), workDir, '/c ' cmd, name, iconPath)
        else
            FileCreateShortcut(A_ComSpec, CustomLnkPath(name), workDir, '/c ' cmd, name)
    } catch as e {
        MsgBox("Không tạo được shortcut icon: " e.Message)
    }
}

DeleteDesktopIcon(name) {
    p := CustomLnkPath(name)
    if FileExist(p)
        try FileDelete(p)
}

; Chạy lệnh shell, bỏ qua nếu một app trong exclude đang active (giống SearchEverywhereCmd)
RunShellGuarded(cmd, workDir, excludeArr) {
    for pat in excludeArr
        if WinActive(pat)
            return
    try
        Run(cmd, workDir)
    catch as e
        MsgBox("Run failed: " e.Message "`n`nCommand: " cmd)
}

MakeShellHandler(cmd, workDir, excludeArr) => (*) => RunShellGuarded(cmd, workDir, excludeArr)

; Đặt context hotkey: rỗng = global, ngược lại theo cửa sổ active
SetHotContext(crit) {
    if (crit = "")
        HotIfWinActive()
    else
        HotIfWinActive(crit)
}

; Đọc toàn bộ section từ INI, đăng ký lại hotkey theo scope WinActive + exclude
ApplyCustomHotkeys() {
    global RegisteredCustomKeys
    ; 1) Tắt hotkey đã đăng ký trước đó
    for pair in RegisteredCustomKeys {
        SetHotContext(pair[2])
        try Hotkey(pair[1], "Off")
    }
    RegisteredCustomKeys := []

    ; 2) Đăng ký lại từ INI
    sections := ""
    try sections := IniRead(CustomIni)
    if (sections = "") {
        HotIfWinActive()
        return
    }
    for id in StrSplit(sections, "`n", "`r") {
        if (id = "")
            continue
        hk  := Trim(IniRead(CustomIni, id, "Hotkey", ""))
        cmd := IniRead(CustomIni, id, "Command", "")
        if (hk = "" || cmd = "")
            continue
        if (IniRead(CustomIni, id, "Enabled", "1") != "1")
            continue
        workDir  := IniRead(CustomIni, id, "WorkingDir", "")
        excludeArr := SplitPatterns(IniRead(CustomIni, id, "Exclude", ""))
        scopes := SplitPatterns(IniRead(CustomIni, id, "WinActive", ""))
        if (scopes.Length = 0)
            scopes := [""]   ; global
        handler := MakeShellHandler(cmd, workDir, excludeArr)
        for crit in scopes {
            SetHotContext(crit)
            try {
                Hotkey(hk, handler)
                RegisteredCustomKeys.Push([hk, crit])
            } catch as e {
                MsgBox("Không đăng ký được hotkey '" hk "': " e.Message)
            }
        }
    }
    HotIfWinActive()   ; reset context về global
}

LoadCustomShortcuts() => ApplyCustomHotkeys()

; ---- GUI ----------------------------------------------------

ShowManagerGui(*) {
    static mgr := ""
    if IsObject(mgr) {
        try {
            mgr.Show()
            MgrRefresh(mgr)
            return
        }
    }
    mgr := Gui("+Resize", "Manage Shortcuts")
    mgr.SetFont("s10", "Segoe UI")

    mgr.Add("Text", "xm", "Custom shortcuts:")
    lv := mgr.Add("ListView", "xm w720 h240 vLV", ["On", "Name", "Hotkey", "Command", "WinActive", "Icon"])
    lv.ModifyCol(1, 40)
    lv.ModifyCol(2, 130)
    lv.ModifyCol(3, 90)
    lv.ModifyCol(4, 240)
    lv.ModifyCol(5, 140)
    lv.ModifyCol(6, 40)
    lv.OnEvent("DoubleClick", (ctrl, row) => (row ? EditSelected(mgr) : ""))

    mgr.Add("Button", "xm w100", "Add").OnEvent("Click", (*) => (ShowEditDialog(mgr), 0))
    mgr.Add("Button", "x+8 w100", "Edit").OnEvent("Click", (*) => EditSelected(mgr))
    mgr.Add("Button", "x+8 w100", "Delete").OnEvent("Click", (*) => DeleteSelected(mgr))
    mgr.Add("Button", "x+8 w100", "Toggle On/Off").OnEvent("Click", (*) => ToggleSelectedCustom(mgr))
    mgr.Add("Button", "x+8 w100", "Close").OnEvent("Click", (*) => mgr.Hide())

    mgr.Add("Text", "xm y+12", "Built-in hotkeys (tick = bật, hotkey cố định):")
    blv := mgr.Add("ListView", "xm w720 h160 Checked -Multi vBLV", ["Hotkey", "Mô tả"])
    blv.ModifyCol(1, 100)
    blv.ModifyCol(2, 600)
    for b in BuiltinList
        blv.Add(IsBuiltinEnabled(b.id) ? "Check" : "", b.hotkey, b.label)
    blv.OnEvent("ItemCheck", BuiltinCheckToggle)

    mgr.OnEvent("Close", (*) => mgr.Hide())
    MgrRefresh(mgr)
    mgr.Show()
}

BuiltinCheckToggle(ctrl, row, checked) {
    global BuiltinList
    if (row < 1 || row > BuiltinList.Length)
        return
    b := BuiltinList[row]
    IniWrite(checked ? "1" : "0", CustomIni, "_Builtins", b.id)
    ApplyBuiltins()
}

BuiltinsRefresh(mgr) {
    blv := mgr["BLV"]
    for i, b in BuiltinList
        blv.Modify(i, IsBuiltinEnabled(b.id) ? "Check" : "-Check")
}

ToggleSelectedCustom(mgr) {
    id := SelectedId(mgr)
    if (id = "") {
        MsgBox("Chọn một dòng để bật/tắt.")
        return
    }
    cur := IniRead(CustomIni, id, "Enabled", "1")
    IniWrite(cur = "1" ? "0" : "1", CustomIni, id, "Enabled")
    ApplyCustomHotkeys()
    MgrRefresh(mgr)
}

MgrRefresh(mgr) {
    global MgrRowIds
    lv := mgr["LV"]
    lv.Delete()
    MgrRowIds := []
    sections := ""
    try sections := IniRead(CustomIni)
    if (sections != "") {
        for id in StrSplit(sections, "`n", "`r") {
            if (id = "" || id = "_Builtins")
                continue
            name := IniRead(CustomIni, id, "Name", id)
            hk   := IniRead(CustomIni, id, "Hotkey", "")
            cmd  := IniRead(CustomIni, id, "Command", "")
            win  := IniRead(CustomIni, id, "WinActive", "")
            ico  := IniRead(CustomIni, id, "CreateIcon", "0") = "1" ? "✓" : ""
            on   := IniRead(CustomIni, id, "Enabled", "1") = "1" ? "✓" : ""
            lv.Add(, on, name, hk, cmd, win, ico)
            MgrRowIds.Push(id)
        }
    }
    try BuiltinsRefresh(mgr)
}

SelectedId(mgr) {
    global MgrRowIds
    row := mgr["LV"].GetNext()
    if (!row || row > MgrRowIds.Length)
        return ""
    return MgrRowIds[row]
}

EditSelected(mgr) {
    id := SelectedId(mgr)
    if (id = "") {
        MsgBox("Chọn một dòng để sửa.")
        return
    }
    ShowEditDialog(mgr, id)
}

DeleteSelected(mgr) {
    id := SelectedId(mgr)
    if (id = "") {
        MsgBox("Chọn một dòng để xoá.")
        return
    }
    name := IniRead(CustomIni, id, "Name", "")
    if MsgBox("Xoá shortcut '" name "'?",, "YesNo") != "Yes"
        return
    if (IniRead(CustomIni, id, "CreateIcon", "0") = "1" && name != "")
        DeleteDesktopIcon(name)
    try IniDelete(CustomIni, id)
    ApplyCustomHotkeys()
    MgrRefresh(mgr)
}

ShowEditDialog(mgr, id := "") {
    dlg := Gui("+Owner" mgr.Hwnd " -MinimizeBox", id = "" ? "Add Shortcut" : "Edit Shortcut")
    dlg.SetFont("s10", "Segoe UI")

    dlg.Add("Text", "xm w120", "Name:")
    eName := dlg.Add("Edit", "x+4 w360 vName", IniRead(CustomIni, id, "Name", ""))

    dlg.Add("Text", "xm w120", "Hotkey:")
    eHk := dlg.Add("Edit", "x+4 w180 vHotkeyText", IniRead(CustomIni, id, "Hotkey", ""))
    dlg.Add("Text", "x+8", "bắt phím →")
    eHkCap := dlg.Add("Hotkey", "x+4 w150")
    eHkCap.OnEvent("Change", (*) => (eHkCap.Value != "" ? eHk.Value := eHkCap.Value : ""))
    dlg.Add("Text", "xm w480 cGray", "Cú pháp: ^ Ctrl, ! Alt, + Shift, # Win. VD ^!n hoặc ^!Del. Phím đặc biệt (Del, Ins, F13…) gõ tay vào ô Hotkey.")

    dlg.Add("Text", "xm w120", "Command:")
    eCmd := dlg.Add("Edit", "x+4 w280 vCommand", IniRead(CustomIni, id, "Command", ""))
    dlg.Add("Button", "x+4 w76", "Browse…").OnEvent("Click", (*) => BrowseInto(dlg, eCmd, false))

    dlg.Add("Text", "xm w120", "Working Dir:")
    eDir := dlg.Add("Edit", "x+4 w280 vWorkingDir", IniRead(CustomIni, id, "WorkingDir", ""))
    dlg.Add("Button", "x+4 w76", "Browse…").OnEvent("Click", (*) => BrowseInto(dlg, eDir, true))

    dlg.Add("Text", "xm w120", "WinActive:")
    eWin := dlg.Add("Edit", "x+4 w360 vWinActive", IniRead(CustomIni, id, "WinActive", ""))
    dlg.Add("Text", "xm w480 cGray", "Chỉ chạy hotkey trong các cửa sổ này (vd: ahk_exe code.exe), phân tách bằng ';'. Rỗng = mọi cửa sổ.")

    dlg.Add("Text", "xm w120", "Exclude:")
    eExc := dlg.Add("Edit", "x+4 w360 vExclude", IniRead(CustomIni, id, "Exclude", ""))
    dlg.Add("Text", "xm w480 cGray", "Bỏ qua khi các app này đang active, phân tách bằng ';'.")

    cEnabled := dlg.Add("CheckBox", "xm vEnabled", "Bật hotkey này")
    cEnabled.Value := (id = "") ? 1 : (IniRead(CustomIni, id, "Enabled", "1") = "1" ? 1 : 0)

    cIcon := dlg.Add("CheckBox", "xm vCreateIcon", "Tạo icon trên Desktop")
    cIcon.Value := IniRead(CustomIni, id, "CreateIcon", "0") = "1" ? 1 : 0

    dlg.Add("Text", "xm w120", "Icon path:")
    eIco := dlg.Add("Edit", "x+4 w280 vIconPath", IniRead(CustomIni, id, "IconPath", ""))
    dlg.Add("Button", "x+4 w76", "Browse…").OnEvent("Click", (*) => BrowseInto(dlg, eIco, false))

    dlg.Add("Button", "xm w100 Default", "OK").OnEvent("Click", (*) => SaveEdit(dlg, mgr, id))
    dlg.Add("Button", "x+8 w100", "Cancel").OnEvent("Click", (*) => dlg.Destroy())
    dlg.OnEvent("Close", (*) => dlg.Destroy())
    dlg.Show()
}

BrowseInto(dlg, ctrl, folder) {
    if folder {
        sel := DirSelect(, 3, "Chọn thư mục")
        if (sel != "")
            ctrl.Value := sel
    } else {
        sel := FileSelect(1, , "Chọn file")
        if (sel != "")
            ctrl.Value := sel
    }
    dlg.Show()
}

SaveEdit(dlg, mgr, oldId) {
    data := dlg.Submit(false)
    name := Trim(data.Name)
    cmd  := Trim(data.Command)
    hkText := Trim(data.HotkeyText)
    if (name = "") {
        MsgBox("Name không được rỗng.")
        return
    }
    if (hkText = "" && !data.CreateIcon) {
        MsgBox("Cần ít nhất một Hotkey hoặc bật tạo icon Desktop.")
        return
    }
    if (cmd = "") {
        MsgBox("Command không được rỗng.")
        return
    }

    newId := CommandId(cmd)
    ; nếu đổi command khi Edit → chuyển section, dọn section/.lnk cũ
    if (oldId != "" && oldId != newId) {
        oldName := IniRead(CustomIni, oldId, "Name", "")
        if (IniRead(CustomIni, oldId, "CreateIcon", "0") = "1" && oldName != "")
            DeleteDesktopIcon(oldName)
        try IniDelete(CustomIni, oldId)
    }
    ; nếu đổi tên nhưng cùng section, dọn .lnk tên cũ
    prevName := IniRead(CustomIni, newId, "Name", "")
    if (prevName != "" && prevName != name)
        DeleteDesktopIcon(prevName)

    IniWrite(name,               CustomIni, newId, "Name")
    IniWrite(hkText,             CustomIni, newId, "Hotkey")
    IniWrite(cmd,                CustomIni, newId, "Command")
    IniWrite(Trim(data.WorkingDir), CustomIni, newId, "WorkingDir")
    IniWrite(Trim(data.WinActive),  CustomIni, newId, "WinActive")
    IniWrite(Trim(data.Exclude),    CustomIni, newId, "Exclude")
    IniWrite(data.CreateIcon ? "1" : "0", CustomIni, newId, "CreateIcon")
    IniWrite(Trim(data.IconPath),   CustomIni, newId, "IconPath")
    IniWrite(data.Enabled ? "1" : "0", CustomIni, newId, "Enabled")

    if (data.CreateIcon)
        CreateDesktopIcon(name, cmd, Trim(data.WorkingDir), Trim(data.IconPath))
    else
        DeleteDesktopIcon(name)

    dlg.Destroy()
    ApplyCustomHotkeys()
    MgrRefresh(mgr)
}

; ============================================================
;  BUILT-IN HOTKEYS — id, hotkey, action, scope
;  Toggle bật/tắt qua Manager GUI, lưu vào [_Builtins] trong shortcuts.ini
; ============================================================

global BuiltinList := [
    { id: "JetBrainsTabSwitch", label: "JetBrains: Ctrl+Tab swap tab",
      hotkey: "^Tab",
      apps: ["ahk_exe phpstorm64.exe", "ahk_exe pycharm64.exe", "ahk_exe rider64.exe", "ahk_exe rustrover64.exe"],
      action: JetBrainsTabSwitch, ctx: "" },
    { id: "TerminalShiftEnter", label: "Terminal: Shift+Enter -> newline",
      hotkey: "+Enter", apps: ["ahk_exe WindowsTerminal.exe"],
      action: TerminalNewLine, ctx: "" },
    { id: "TerminalCtrlEnter", label: "Terminal: Ctrl+Enter -> Enter",
      hotkey: "^Enter", apps: ["ahk_exe WindowsTerminal.exe"],
      action: "{Enter}", ctx: "" },
    { id: "ShiftDoubleTap", label: "Double-Shift -> Search Everywhere",
      hotkey: "~Shift", apps: [],
      action: ShiftDoubleTap, ctx: "" },
    { id: "ManagerGui", label: "Win+Alt+M -> Manage Shortcuts",
      hotkey: "#!m", apps: [],
      action: ShowManagerGui, ctx: "" },
    { id: "CycleCase", label: "Ctrl+Shift+U -> Cycle case (skip JetBrains)",
      hotkey: "^+u", apps: [],
      action: CycleCaseSelected, ctx: "notJB" },
]

global RegisteredBuiltins := []   ; [ [hotkey, ctxTag], ... ]

NotInJetBrains(*) => !IsJetBrainsActive()

ApplyBuiltinContext(tag) {
    if (tag = "notJB")
        HotIf(NotInJetBrains)
    else if (tag = "")
        HotIfWinActive()
    else
        HotIfWinActive(tag)
}

IsBuiltinEnabled(id) => IniRead(CustomIni, "_Builtins", id, "1") = "1"

ApplyBuiltins() {
    global RegisteredBuiltins, BuiltinList
    for pair in RegisteredBuiltins {
        ApplyBuiltinContext(pair[2])
        try Hotkey(pair[1], "Off")
    }
    RegisteredBuiltins := []

    for b in BuiltinList {
        if !IsBuiltinEnabled(b.id)
            continue
        handler := MakeHandler(b.action)
        if (b.ctx = "notJB") {
            ApplyBuiltinContext("notJB")
            try {
                Hotkey(b.hotkey, handler, "On")
                RegisteredBuiltins.Push([b.hotkey, "notJB"])
            } catch as e {
                MsgBox("Builtin '" b.id "': " e.Message)
            }
        } else if (b.apps.Length = 0) {
            ApplyBuiltinContext("")
            try {
                Hotkey(b.hotkey, handler, "On")
                RegisteredBuiltins.Push([b.hotkey, ""])
            } catch as e {
                MsgBox("Builtin '" b.id "': " e.Message)
            }
        } else {
            for pat in b.apps {
                ApplyBuiltinContext(pat)
                try {
                    Hotkey(b.hotkey, handler, "On")
                    RegisteredBuiltins.Push([b.hotkey, pat])
                } catch as e {
                    MsgBox("Builtin '" b.id "' @ " pat ": " e.Message)
                }
            }
        }
    }
    HotIfWinActive()
}

MakeHandler(target) => (hk) => (target is Func) ? target() : Send(target)

ApplyBuiltins()
LoadCustomShortcuts()
