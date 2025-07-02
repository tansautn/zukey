#Requires AutoHotkey v2.0




;Always on Top (Shift + Ctrl + Space)
^+SPACE::
{
	curentActiveWin := WinGetTitle("A")
	; MsgBox "The active window is " curentActiveWin
	WinSetAlwaysOnTop -1, curentActiveWin
	; x := InStr(curentActiveWin, "PINNED")
	; MsgBox "v = ''" x
	If InStr(curentActiveWin, "PINNED")
		WinSetTitle(StrReplace(curentActiveWin, " | PINNED", ""), curentActiveWin)
	Else
		WinSetTitle(curentActiveWin  . " | PINNED", curentActiveWin)
	; ^+SPACE:: MsgBox "The active window is '" WinGetTitle("A") "'."
	Return
}