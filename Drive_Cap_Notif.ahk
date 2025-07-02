#Requires AutoHotkey v2.0

Persistent
#SingleInstance Force
SetTimer CheckDiskSpace, 3600000 ; Run every hour (3600000 ms)

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
CheckDiskSpace() {
    driveList := DriveGetList()
    Loop Parse, driveList {
        drive := A_LoopField ":\"
        freeSpace := DriveGetSpaceFree(drive)
        capacity := DriveGetCapacity(drive)
        
        usedSpace := capacity - freeSpace
        usagePercentage := (usedSpace / capacity) * 100
        
        if (usagePercentage > 80) {
            formattedPercentage := Round(usagePercentage, 2)
            TrayTip "Disk Space Alert", "Drive " drive " is at " formattedPercentage "`% capacity!"
        }
    }
}
CheckDiskSpace()