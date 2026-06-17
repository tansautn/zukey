#Requires AutoHotkey v2.0
#NoTrayIcon
EnsureRestartFlag()
EnsureStartupEntry()

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
    jetbrainsExes := ["phpstorm64.exe", "pycharm64.exe", "rider64.exe"]
    for exe in jetbrainsExes {
        if WinActive("ahk_exe " exe) {
            return
        }
    }
    Send "{LWin down}{LAlt down}{Space}{LWin up}{LAlt up}"
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
;  MAPPING CONFIG  — edit only this section
; ============================================================

global Mappings := [
    {
        apps: ["ahk_exe phpstorm64.exe", "ahk_exe pycharm64.exe", "ahk_exe rider64.exe"],
        keys: Map(
            "^Tab",   JetBrainsTabSwitch,
            ;"+Enter", "{Enter}",
            ;"^Enter", "+{Enter}"
        )
    },
    {
        apps: ["ahk_exe WindowsTerminal.exe"],
        keys: Map(
            "+Enter", TerminalNewLine,
            "^Enter", "{Enter}",
            ; "Tab",    TerminalTabToRight
        )
    },
    ; {
        ; apps: ["ahk_exe powershell.exe"],
        ; keys: Map(
            ; "Tab",    TerminalTabToRight
        ; )
    ; },
    {
        apps: [],
        keys: Map(
            "~Shift", ShiftDoubleTap,
        )
    },
]

; ============================================================
;  REGISTRATION — touch nothing below
; ============================================================

for _, group in Mappings {
    if group.apps.Length = 0 {
        HotIfWinActive()
        for srcKey, target in group.keys {
            Hotkey(srcKey, MakeHandler(target))
        }
    } else {
        for _, pattern in group.apps {
            HotIfWinActive(pattern)
            for srcKey, target in group.keys {
                Hotkey(srcKey, MakeHandler(target))
            }
        }
    }
}

HotIfWinActive()

MakeHandler(target) => (hk) => (target is Func) ? target() : Send(target)
