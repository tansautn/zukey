#Requires AutoHotkey v2.0
#SingleInstance Force

; --- KHỞI TẠO GUI ---
myGui := Gui("+AlwaysOnTop +ToolWindow", "Auto Typer (AHK v2)")
myGui.SetFont("s10", "Segoe UI")

myGui.Add("Text",, "Nhập text (Plaintext):")
; Tạo Edit box và lưu tham chiếu vào biến inputObj
inputObj := myGui.Add("Edit", "w300 h200 Multi vMyInput")

; Nút Send và Stop
btnSend := myGui.Add("Button", "w140 Section", "Send (Start)")
btnStop := myGui.Add("Button", "ys w140", "Stop")

; Gán sự kiện (Event) cho nút bấm
btnSend.OnEvent("Click", StartProcess)
btnStop.OnEvent("Click", StopProcess)

; Biến toàn cục để kiểm soát dừng
global isStopping := false

myGui.Show()

; --- HOTKEY: Ctrl + Alt + M ---
^!m::StartProcess()

; --- HÀM XỬ LÝ CHÍNH ---
StartProcess(*)
{
    global isStopping := false
    textToSend := inputObj.Value ; Lấy text từ ô input
    
    if (textToSend = "")
        return

    ; Logic chuyển cửa sổ:
    ; Nếu cửa sổ hiện tại là GUI (do bấm nút), gửi Alt+Esc để về cửa sổ trước
    if WinActive("ahk_id " myGui.Hwnd)
    {
        Send("!{Esc}") 
        Sleep(300) ; Chờ cửa sổ kia active
    }
    
    ; Lấy Handle của cửa sổ đích (cửa sổ đang active)
    try {
        targetWin := WinExist("A")
    } catch {
        return ; Không tìm thấy cửa sổ nào
    }

    ; Loop qua từng ký tự trong chuỗi text
    Loop Parse, textToSend
    {
        if (isStopping)
        {
            ToolTip("Đã dừng (Stopped)!")
            SetTimer () => ToolTip(), -2000 ; Tắt tooltip sau 2s
            break
        }

        char := A_LoopField
        
        ; Xử lý xuống dòng: `n thành {Enter}
        if (char = "`n")
            ControlSend("{Enter}",, targetWin)
        ; Bỏ qua `r để tránh double enter
        else if (char != "`r")
            ControlSend("{Raw}" char,, targetWin)
            
        Sleep(10) ; Delay nhỏ để tránh bị 'nuốt' phím
    }
}

; --- HÀM DỪNG ---
StopProcess(*)
{
    global isStopping := true
    ; Focus lại GUI để người dùng biết đã bấm ăn
    try WinActivate("ahk_id " myGui.Hwnd)
}