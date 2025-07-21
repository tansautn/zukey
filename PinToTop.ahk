#Requires AutoHotkey v2.0
global AFFECTED := [
    {method: "StartWith", value: "Developer Tools"}
]
global __handledWins := Map()

tooglePinned()
{
	curentActiveWin := WinGetTitle("A")
	; MsgBox "The active window is " curentActiveWin
	WinSetAlwaysOnTop -1, curentActiveWin
	; x := InStr(curentActiveWin, "PINNED")
	; MsgBox "v = ''" x
	If InStr(curentActiveWin, "PINNED") {
	    title := StrReplace(curentActiveWin, " | PINNED", "")
	    title := StrReplace(title, " | AUTOPINNED", "")
		WinSetTitle(title, curentActiveWin)
	}
	Else
		WinSetTitle(curentActiveWin  . " | PINNED", curentActiveWin)
	; ^+SPACE:: MsgBox "The active window is '" WinGetTitle("A") "'."
	Return
}

AutoPinLoop() {
    global AFFECTED, __handledWins

    winList := WinGetList()
    for hwnd in winList {
        try title := WinGetTitle(hwnd)
        if (title == "" || __handledWins.Has(hwnd))
            continue
        if (InStr(title, "PINNED") || InStr(title, "AUTOPINNED"))
            continue
        for rule in AFFECTED {
            method := rule.method
            value := rule.value

            matched := (
                (method = "InStr" && InStr(title, value)) ||
                (method = "StartWith" && SubStr(title, 1, StrLen(value)) == value) ||
                (method = "EndWith" && SubStr(title, -StrLen(value) + 1) == value)
            )

            if matched {
                NewTitle := title " | AUTOPINNED"
                WinSetTitle(NewTitle, hwnd)
                WinSetAlwaysOnTop(1, hwnd)
                break
            }
        }
        __handledWins[hwnd] := true
    }
}

;Always on Top (Shift + Ctrl + Space)
^+SPACE::tooglePinned()
SetTimer(AutoPinLoop, 250) ; Run every 250 ms
