#Requires AutoHotkey v2.0
#NoTrayIcon
; HotIfWinActive "ahk_exe phpstorm64.exe"
#HotIf WinActive("ahk_exe phpstorm64.exe") or WinActive("ahk_exe pycharm64.exe")
^Tab::
{
	SetKeyDelay(50, 50)
	Send "{Blind}{Ctrl DownR}{e}{Ctrl up}"
	Sleep(200)
	Send "{Blind}{Enter}"
	Return
}