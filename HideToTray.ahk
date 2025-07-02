#Requires AutoHotkey v2.0
#SingleInstance Force
#WinActivateForce
Persistent
COMPILED_FILENAME := "HideToTray.exe"
; Lấy tên tiến trình hiện tại và đường dẫn đầy đủ
currentProcess := GetCurrentProcess()
procFileName := currentProcess.name
fullPath := currentProcess.path
; procCommandline := DllCall("GetCommandLineA"
     ; , "Unit", DllCall("GetModuleHandle", "str", "kernel32.dll")
     ; , "str", "GetCommandLineA")
procCommandline := currentProcess.cmd


; Kiểm tra xem tiến trình đã có trong mục khởi động chưa
entryName := procFileName
isRunFromAhkFile := InStr(procCommandline, ".ahk") and !A_IsCompiled
; Check for complied file name already registered
if (isRunFromAhkFile and RegExMatch(entryName, "i)AutoHotkey.*\.exe$")){
    entryName := COMPILED_FILENAME
}
if !CheckStartupEntry(entryName, fullPath) {
    if !A_IsAdmin {
		accept := MsgBox("Chưa có startup entry cho " procFileName "`nKhởi động lại với quyền admin để thêm ?",,"YesNo")
		if accept = "No" {
			Goto Main
		}
        ; Khởi động lại với quyền admin
        if accept and !RunAsAdmin(){
			MsgBox('Ko chạy đc với quyền assmin')
		}
		ExitApp
    }
	; Hiển thị hộp thoại thông báo và yêu cầu xác nhận
	if (MsgBox("Tên tiến trình: " procFileName "`nĐường dẫn đầy đủ: " fullPath "`nBạn có muốn thêm tiến trình này vào mục khởi động không?",, "YesNo") = "No") {
		Goto Main
	}
    AddStartupEntry(entryName, procCommandline)
    MsgBox "Tiến trình đã được thêm vào mục khởi động.`nFull command: " procCommandline
	Goto Main
}

GetCurrentProcess() {
    ; Lấy tên tiến trình hiện tại
    ; procFileName := ""
    ; fullPath := ""
	ScriptPID := ProcessExist()
	procFileName := ProcessGetName(ScriptPID)
    fullPath := ProcessGetPath(ScriptPID)
	procCommandline := DllCall("GetCommandLineW"
     , "UInt", ScriptPID
     , "str")
    ; DllCall("Psapi.dll\GetModuleFileName", "Ptr", 0, "Str", fullPath, "UInt", 1024)
    SplitPath(fullPath, &name := "", &dir := "", &ext := "", &nameNoExt := "")
    return {name: nameNoExt, path: fullPath, cmd: procCommandline}
}

CheckStartupEntry(entryName, entryPath) {
    ; entries := RegRead("HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Run")
	Loop Reg, "HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Run", "KVR"
    {
		value := RegRead()
        if(InStr(value, entryName) or entryPath = value){
			return true
		}
    }
    ; for key, value in entries {
        ; if key = entryName and value = entryPath
            ; return true
    ; }
    return false
}

AddStartupEntry(entryName, entryPath) {
    RegWrite entryPath ,"REG_SZ", "HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Run", entryName
}

RunAsAdmin() {
    if !A_IsAdmin {
        try {
            Run("*RunAs " A_ScriptFullPath)
            return true
        } catch {
            ; MsgBox "Không thể khởi động lại với quyền admin."
            return false
        }
    }
    return true
}
Main:
; Global array to store hidden windows
global hiddenWindows := Map()

; Win+H to hide active window to tray
#h::HideWindowToTray()

HideWindowToTray() {
    activeWin := WinGetID("A")
    if !activeWin
        return
    
    title := WinGetTitle(activeWin)
    class := WinGetClass(activeWin)
    
    ; Skip if no window is active
    if (title = "" or class = "")
        return
    
    ; Create a unique identifier
    id := "win_" . activeWin
    
    ; Store window info
    hiddenWindows[id] := {
        title: title,
        hwnd: activeWin
    }
    
    ; Add tray menu item
    A_TrayMenu.Add(title, RestoreWindowFromTray)
    TraySetIcon(, , 1)
    
    ; Hide the window
    WinHide(activeWin)
}

RestoreWindowFromTray(ItemName, ItemPos, MenuName) {
    ; Find the window by title
    for id, winInfo in hiddenWindows {
        if (winInfo.title = ItemName) {
            ; Show and activate the window
            WinShow("ahk_id " winInfo.hwnd)
            
            WinActivate("ahk_id " winInfo.hwnd)
            
            ; Remove from hidden windows
            hiddenWindows.Delete(id)
            
            ; Remove tray menu item
            A_TrayMenu.Delete(ItemName)
            break
        }
        
    }
}
; -----------------------
; Auto-Hide child processes of specific parents (e.g., cursor.exe)
; -----------------------

global knownPIDs := Map()
global watchParents := []

SetTimer(CheckNewProcesses, 1000)
return

CheckNewProcesses(*) {
    wmi := ComObjGet("winmgmts:")
    for process in wmi.ExecQuery("Select * from Win32_Process") {
        pid := process.ProcessId
        exe := process.Name
        ppid := process.ParentProcessId

        ; Skip if already known
        if knownPIDs.Has(pid)
            continue

        ; Mark as known
        knownPIDs[pid] := true

        ; If this is a parent to watch (cursor.exe)
        if (exe = "cursor.exe") {
            watchParents.Push(pid)
            continue
        }

        ; If this is a child to hide
        if (exe = "cmd.exe" || exe = "uvx.exe") {
            ; Check parent against watchParents
            for parentID in watchParents {
                if (ppid = parentID) {
                    winList := WinGetList("ahk_pid " pid)
                    for hwnd in winList {
                        if hwnd {
                            title := "Auto-hid " exe " (PID " pid ") launched by cursor.exe (PID " ppid ")"
                            id := "hwnd_" hwnd

                            ; Save to hiddenWindows
                            hiddenWindows[id] := {
                                title: title,
                                hwnd: hwnd
                            }

                            ; Add to tray
                            A_TrayMenu.Add(title, RestoreWindowFromTray)
                            TraySetIcon(, , 1)

                            ; Hide the window
                            WinHide("ahk_id " hwnd)

                            ToolTip(title)
                            SetTimer(RemoveToolTip, -1000)
                        }
                    }
                    break
                }
            }
        }
    }
}

RemoveToolTip(*) {
    ToolTip()
}