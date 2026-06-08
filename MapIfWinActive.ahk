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
            "^Enter", "{Enter}"
        )
    },
]

; ============================================================
;  REGISTRATION — touch nothing below
; ============================================================

for _, group in Mappings {
    for _, pattern in group.apps {
        for srcKey, target in group.keys {
            HotIfWinActive(pattern)
            Hotkey(srcKey, MakeHandler(target))
        }
    }
}

HotIfWinActive()

MakeHandler(target) => (hk) => (target is Func) ? target() : Send(target)
