#Requires AutoHotkey v2.0
#NoTrayIcon
EnsureRestartFlag()

EnsureRestartFlag() {
    ; Lấy toàn bộ Command Line dưới dạng chuỗi
    fullCmd := StrGet(DllCall("GetCommandLineW", "Ptr"), "UTF-16")

    ; Kiểm tra xem chuỗi command line có chứa "/restart" không (case-insensitive)
    if !InStr(fullCmd, "/restart") {
        ; Nếu chưa có, ta sẽ chạy lại chính nó với flag /restart
        
        if A_IsCompiled {
            ; Trường hợp đã compile thành .exe
            Run('"' A_ScriptFullPath '" /restart')
        } else {
            ; Trường hợp chạy file .ahk gốc
            ; Cấu trúc: "PathToAutoHotkey.exe" /restart "PathToScript.ahk"
            Run('"' A_AhkPath '" /restart "' A_ScriptFullPath '"')
        }
        
        ; Sau khi gọi Run xong thì kill instance hiện tại ngay lập tức
        ExitApp()
    }
}

;Maximum performance by using Group add (1 call to WinActivate)
GroupAdd "JetBrainsIDE", "ahk_exe phpstorm64.exe"
GroupAdd "JetBrainsIDE", "ahk_exe pycharm64.exe"
GroupAdd "JetBrainsIDE", "ahk_exe rider64.exe"
#HotIf WinActive("AHK_group JetBrainsIDE")
^Tab::
{
	SetKeyDelay(50, 50)
	Send "{Blind}{Ctrl DownR}{e}{Ctrl up}"
	Sleep(200)
	Send "{Blind}{Enter}"
	Return
}