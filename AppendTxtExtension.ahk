#Requires AutoHotkey v2.0
#SingleInstance Force

; ==============================================================================
; PHẦN 1: AUTO-EXECUTE SECTION
; Code ở đây sẽ chạy ngay lập tức khi bạn click đúp vào script.
; Nhiệm vụ: Kiểm tra Startup, đăng ký nếu chưa có, sau đó KHÔNG ExitApp mà ngồi chờ Hotkey.
; ==============================================================================

ExecuteStartupCheck() ; Gọi hàm xử lý startup

; Sau khi hàm trên chạy xong, script sẽ tự động chuyển sang trạng thái "Idle"
; và lắng nghe Hotkey bên dưới. Không cần "Goto Main".

; ==============================================================================
; PHẦN 2: HOTKEY DEFINITIONS
; ==============================================================================

; Phím tắt: Ctrl (^) + Win (#) + Shift (+) + F2
^#+F2::
{
    ; 1. Lấy handle của cửa sổ hiện tại
    hwnd := WinExist("A")
    
    ; 2. Kết nối tới Object Windows Explorer qua COM
    activeTab := ""
    try {
        shellWindows := ComObject("Shell.Application").Windows
    } catch {
        return ; Không thể kết nối tới Shell
    }

    ; Tìm cửa sổ Explorer khớp với cửa sổ hiện tại (Active Window)
    found := false
    for w in shellWindows {
        try {
            ; ComObj có thể throw error nếu window đang bận hoặc khác thread
            if (w.hwnd == hwnd) {
                activeTab := w
                found := true
                break
            }
        }
    }

    if (!found) {
        return ; Không phải Explorer
    }

    ; Lấy view hiện tại của folder
    folderView := activeTab.Document
    
    ; Lấy danh sách các file đang được select
    selectedItems := folderView.SelectedItems
    
    if (selectedItems.Count == 0)
        return ; Không có file nào được chọn

    newFileNames := []
    
    ; 3. Duyệt qua từng file, copy và append .txt
    For item in selectedItems {
        srcPath := item.Path
        destPath := srcPath . ".txt"
        
        try {
            ; Copy file (flag 0 = không ghi đè nếu đã tồn tại)
            FileCopy srcPath, destPath
            
            ; Lấy tên file để select sau này
            SplitPath destPath, &outFileName
            newFileNames.Push(outFileName)
        } catch as err {
            ; Bỏ qua lỗi
        }
    }

    ; Sleep nhẹ để file system cập nhật
    Sleep 100

    ; 4. Set selected files thành các file mới
    try {
        folderNamespace := activeTab.Document.Folder 
        firstItem := true
        
        for name in newFileNames {
            try {
                newItem := folderNamespace.ParseName(name)
                if (firstItem) {
                    ; 1 (Select) | 4 (DeselectOthers) | 8 (EnsureVisible) | 16 (Focus)
                    folderView.SelectItem(newItem, 1 | 4 | 8 | 16)
                    firstItem := false
                } else {
                    folderView.SelectItem(newItem, 1)
                }
            }
        }
    }
}

; ==============================================================================
; PHẦN 3: FUNCTIONS HELPER (STARTUP LOGIC)
; ==============================================================================

ExecuteStartupCheck() {
    ; Lấy thông tin process hiện tại
    currentData := GetCurrentProcessInfo()
    entryName := currentData.name
    fullPath := currentData.path
    cmdLine := currentData.cmd

    ; Kiểm tra trong Registry
    if !CheckStartupEntry(entryName, fullPath) {
        
        ; Nếu chưa có, hỏi User
        if !A_IsAdmin {
            ; Nếu chưa là Admin, hỏi user có muốn restart as Admin để add không?
            result := MsgBox("Script chưa được thêm vào Startup.`nBạn có muốn cấp quyền Admin để thêm tự động không?", "Startup Check", 4+32)
            if (result = "No")
                return ; Người dùng không muốn thêm, chạy tiếp script bình thường
            
            ; Thử restart với quyền Admin
            if !RunAsAdmin() {
                MsgBox("Không thể chạy dưới quyền Admin. Vui lòng chuột phải -> Run as Administrator.")
                return 
            }
            ; Nếu RunAsAdmin thành công, script cũ sẽ đóng, script mới chạy lại từ đầu.
            ExitApp 
        }

        ; Nếu đã là Admin (hoặc vừa restart xong)
        result := MsgBox("Tên tiến trình: " entryName "`nĐường dẫn: " fullPath "`n`nThêm vào khởi động cùng Windows?", "Startup Registration", 4+32)
        
        if (result = "Yes") {
            try {
                AddStartupEntry(entryName, cmdLine)
                MsgBox("Đã thêm thành công vào Startup!", "Success")
            } catch as err {
                MsgBox("Lỗi khi ghi Registry: " err.Message)
            }
        }
    }
}

GetCurrentProcessInfo() {
    ScriptPID := ProcessExist()
    ; Lấy đường dẫn file thực thi
    fullPath := ProcessGetPath(ScriptPID)
    
    ; Lấy Command Line chuẩn xác (bao gồm cả arguments nếu có)
    ; Dùng StrGet để lấy string từ pointer trả về bởi GetCommandLineW
    cmdLinePtr := DllCall("GetCommandLineW", "Ptr")
    procCommandline := StrGet(cmdLinePtr, "UTF-16")
    
    SplitPath(fullPath, &name, &dir, &ext, &nameNoExt)
    
    ; Nếu chạy file .ahk chưa compile, Registry cần format: "AutoHotkey.exe" "Script.ahk"
    ; GetCommandLineW thường đã trả về đúng format này.
    
    return {name: nameNoExt, path: fullPath, cmd: procCommandline}
}

CheckStartupEntry(entryName, entryPath) {
    regKey := "HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Run"
    Loop Reg, regKey, "KV"
    {
        try {
            value := RegRead()
            ; Kiểm tra lỏng (chứa tên) hoặc chặt (đúng đường dẫn)
            if (A_LoopRegName = entryName || InStr(value, entryPath)) {
                return true
            }
        }
    }
    return false
}

AddStartupEntry(entryName, entryPath) {
    RegWrite entryPath, "REG_SZ", "HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Run", entryName
}

RunAsAdmin() {
    if !A_IsAdmin {
        try {
            if A_IsCompiled
                Run '*RunAs "' A_ScriptFullPath '" /restart'
            else
                Run '*RunAs "' A_AhkPath '" /restart "' A_ScriptFullPath '"'
            return true
        } catch {
            return false
        }
    }
    return true
}