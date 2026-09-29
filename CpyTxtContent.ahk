#Requires AutoHotkey v2.0
#SingleInstance Force

; ==============================================================================
; PHẦN 1: GLOBAL VARIABLES & AUTO-EXECUTE SECTION
; ==============================================================================
global FileContents := Map() ; Map lưu trữ nội dung file (Index by basename)
global MultiFileGui := ""    ; Biến lưu trữ đối tượng GUI
global LVCtrl := ""          ; Biến lưu trữ đối tượng ListView

; Bắt Message từ Windows Kernel. 
; 0x0021 là WM_MOUSEACTIVATE. Đảm bảo GUI của chúng ta không bao giờ cướp Focus của cửa sổ khác.
OnMessage(0x0021, WM_MOUSEACTIVATE)

ExecuteStartupCheck()

; ==============================================================================
; PHẦN 2: HOTKEY DEFINITIONS (^#+F3)
; ==============================================================================
^#+F3::
{
    hwnd := WinExist("A")
    
    ; Kết nối tới Object Windows Explorer qua COM
    activeTab := ""
    try {
        shellWindows := ComObject("Shell.Application").Windows
    } catch {
        return
    }

    found := false
    for w in shellWindows {
        try {
            if (w.hwnd == hwnd) {
                activeTab := w
                found := true
                break
            }
        }
    }

    if (!found) 
    {
        return
    }

    selectedItems := activeTab.Document.SelectedItems
    if (selectedItems.Count == 0) {
        TrayTip "Cảnh báo", "Bạn chưa chọn file nào!", 2
        return
    }

    ; 1. Reset lại trạng thái (Clear bộ nhớ và tắt GUI cũ nếu có)
    ResetAndCloseGui()

    ; 2. Đọc file và nạp vào Memory (Map)
    processedCount := 0
    For item in selectedItems {
        filePath := item.Path
        
        ; Bỏ qua Thư mục
        if InStr(FileExist(filePath), "D")
            continue
            
        try {
            fileText := FileRead(filePath, "UTF-8")
            SplitPath filePath, &fileName
            
            ; Giữ nguyên format như bạn yêu cầu
            formattedContent := "---- `r`n# " fileName "`r`n`r`n" fileText "`r`n`r`n"
            
            ; Lưu vào Map indexed by basename
            FileContents[fileName] := formattedContent
            processedCount++
        } catch Error as ex {
            OutputDebug(ex)
        }
    }

    ; 3. Nếu có file hợp lệ, hiển thị Table
    if (processedCount > 0) {
        ShowFloatingTable()
        TrayTip "Sẵn sàng", "Đã nạp " processedCount " file(s) vào bộ nhớ. Hãy sang cửa sổ khác để Paste!", 2
    } else {
        TrayTip "Lỗi", "Không có file nào đọc được.", 3
    }
}

; ==============================================================================
; PHẦN 3: GUI & LOGIC XỬ LÝ CLICK SANG CỬA SỔ KHÁC
; ==============================================================================

ShowFloatingTable() {
    global MultiFileGui, LVCtrl, FileContents

    ; Tạo GUI: 
    ; +AlwaysOnTop: Luôn nổi
    ; -Caption: Bỏ thanh tiêu đề cho gọn
    ; +ToolWindow: Không hiện dưới Taskbar
    ; +E0x08000000: WS_EX_NOACTIVATE - Không cướp focus khi khởi tạo
    MultiFileGui := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x08000000 +Border")
    MultiFileGui.BackColor := "White"
    MultiFileGui.SetFont("s10", "Segoe UI")

    ; Header text
    MultiFileGui.Add("Text", "x10 y10 w200 cBlack +BackgroundTrans", "Bảng điều khiển Paste:")

    ; Nút X (Đóng & Clear Mem)
    closeBtn := MultiFileGui.Add("Text", "x230 y8 w20 h20 cRed Center +Border BackgroundWhite", "X")
    closeBtn.SetFont("w700") ; In đậm
    closeBtn.OnEvent("Click", (*) => ResetAndCloseGui())

    ; Table (ListView)
    LVCtrl := MultiFileGui.Add("ListView", "x10 y35 w240 h200 -Hdr -Multi +Grid", ["Tên File"])
    
    ; Đổ dữ liệu từ Map vào ListView
    for fileName, content in FileContents {
        LVCtrl.Add("", fileName)
    }

    ; Bắt sự kiện Click vào 1 row
    LVCtrl.OnEvent("Click", OnRowClick)

    ; Lấy tọa độ Working Area của màn hình CHÍNH (Default Monitor = 1)
    MonitorGetWorkArea(1, &Left, &Top, &Right, &Bottom)

    GuiWidth := 260
    GuiHeight := 245
    
    ; Tính toán góc phải bên dưới màn hình (cách mép 15px)
    PosX := Right - GuiWidth - 15
    PosY := Bottom - GuiHeight - 15

    ; Show với cờ NoActivate để cửa sổ hiện tại (Explorer) không bị mất Focus
    MultiFileGui.Show("NoActivate x" PosX " y" PosY " w" GuiWidth " h" GuiHeight)
}

OnRowClick(LV, RowNumber) {
    global FileContents
    if (RowNumber == 0)
        return
    
    fileName := LV.GetText(RowNumber, 1)
    
    if FileContents.Has(fileName) {
        ; 1. Put content vào Clipboard
        A_Clipboard := FileContents[fileName]
        
        ; Đợi Clipboard sẵn sàng (Max 1s)
        if !ClipWait(1) {
            TrayTip "Lỗi", "Không thể copy vào Clipboard", 2
            return
        }
        
        ; 2. Gửi phím Ctrl+V vào cửa sổ đang Active
        ; (Vì GUI của chúng ta dùng NoActivate, cửa sổ Active hiện tại chính là IDE/Editor của bạn)
        SendInput("^v")
        
        ; Bỏ select dòng vừa click để click lại dễ hơn
        LV.Modify(RowNumber, "-Select")
    }
}

ResetAndCloseGui() {
    global MultiFileGui, FileContents
    if (MultiFileGui) {
        MultiFileGui.Destroy()
        MultiFileGui := ""
    }
    FileContents.Clear() ; Xoá sạch content trong Memory
}

; Hàm chặn Windows kích hoạt (Active) GUI khi click chuột vào nó
WM_MOUSEACTIVATE(wParam, lParam, msg, hwnd) {
    global MultiFileGui
    ; Nếu cửa sổ được click là GUI của chúng ta
    if (MultiFileGui and wParam == MultiFileGui.Hwnd) {
        return 3 ; Trả về MA_NOACTIVATE (3) -> Cho phép Click xuyên qua nhưng KHÔNG cướp Focus
    }
}

; ==============================================================================
; PHẦN 4: STARTUP HELPERS (Giữ nguyên gốc của bạn)
; ==============================================================================

ExecuteStartupCheck() {
    currentData := GetCurrentProcessInfo()
    entryName := currentData.name
    fullPath := currentData.path
    cmdLine := currentData.cmd

    if !CheckStartupEntry(entryName, fullPath) {
        if !A_IsAdmin {
            result := MsgBox("Script chưa được thêm vào Startup.`nBạn có muốn cấp quyền Admin để thêm tự động không?", "Startup Check", 4+32)
            if (result = "No")
                return 
            
            if !RunAsAdmin() {
                MsgBox("Không thể chạy dưới quyền Admin. Vui lòng chuột phải -> Run as Administrator.")
                return 
            }
            ExitApp 
        }

        result := MsgBox("Tên tiến trình: " entryName "`nĐường dẫn: " fullPath "`n`nThêm vào khởi động cùng Windows?", "Startup Registration", 4+32)
        
        if (result = "Yes") {
            try {
                AddStartupEntry(entryName, cmdLine)
                TrayTip "Thành công", "Đã thêm script vào Startup!", 1
            } catch as err {
                MsgBox("Lỗi khi ghi Registry: " err.Message)
            }
        }
    }
}

GetCurrentProcessInfo() {
    ScriptPID := ProcessExist()
    fullPath := ProcessGetPath(ScriptPID)
    cmdLinePtr := DllCall("GetCommandLineW", "Ptr")
    procCommandline := StrGet(cmdLinePtr, "UTF-16")
    SplitPath fullPath, &name, &dir, &ext, &nameNoExt
    return {name: nameNoExt, path: fullPath, cmd: procCommandline}
}

CheckStartupEntry(entryName, entryPath) {
    regKey := "HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Run"
    Loop Reg, regKey, "KV"
    {
        try {
            value := RegRead()
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