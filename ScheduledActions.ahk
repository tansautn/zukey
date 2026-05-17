#Requires AutoHotkey v2.0
#SingleInstance Force

global ActionSequence := []
global PendingTask := ""
global IniFile := A_ScriptDir "\AutoActionSettings.ini" ; Khai báo đường dẫn file lưu trữ

; ==========================================
; 1. TẠO GIAO DIỆN (GUI)
; ==========================================
MainGui := Gui("+Resize +AlwaysOnTop", "Auto Action Scheduler v2")

; --- Khu vực định nghĩa hành động ---
MainGui.Add("GroupBox", "x10 y10 w380 h215", "1. Định nghĩa hành động")

MainGui.Add("Text", "x20 y35 w80", "Hành động:")
Actions := ["WinActive", "Click", "SendKey", "Sleep", "Log", "Notif", "WaitFor", "Exit"]
ddlAction := MainGui.Add("DropDownList", "x100 y30 w120 vActionType Choose1", Actions)
ddlAction.OnEvent("Change", UpdateHint)

MainGui.Add("Text", "x20 y65 w80", "Tham số 1:")
edtP1 := MainGui.Add("Edit", "x100 y60 w270 vP1")

MainGui.Add("Text", "x20 y95 w80", "Tham số 2:")
edtP2 := MainGui.Add("Edit", "x100 y90 w270 vP2")

MainGui.Add("Text", "x20 y125 w80", "Tham số 3:")
edtP3 := MainGui.Add("Edit", "x100 y120 w270 vP3")

txtHint := MainGui.Add("Text", "x20 y155 w360 cBlue h25", "Gợi ý: Chọn hành động để xem hướng dẫn.")

; --- Các nút quản lý chuỗi hành động ---
btnAdd := MainGui.Add("Button", "x20 y185 w90 h25 Default", "Thêm (Add)")
btnAdd.OnEvent("Click", AddAction)

btnDelSel := MainGui.Add("Button", "x115 y185 w80 h25", "Xóa dòng")
btnDelSel.OnEvent("Click", DeleteAction)

btnUp := MainGui.Add("Button", "x200 y185 w45 h25", "▲ Lên")
btnUp.OnEvent("Click", MoveUp)

btnDown := MainGui.Add("Button", "x250 y185 w45 h25", "▼ Xuống")
btnDown.OnEvent("Click", MoveDown)

btnClear := MainGui.Add("Button", "x300 y185 w80 h25", "Xóa tất cả")
btnClear.OnEvent("Click", ClearSequence)

; --- Khu vực Cấu hình & Lên lịch ---
MainGui.Add("GroupBox", "x10 y235 w380 h100", "2. Cấu hình & Lên lịch chạy")

MainGui.Add("Text", "x20 y265 w95", "Bắt đầu từ bước:")
edtIndex := MainGui.Add("Edit", "x115 y260 w50 Number")
MainGui.Add("UpDown", "Range1-999", 1)

MainGui.Add("Text", "x180 y265 w55", "Hẹn giờ:")
dtpTime := MainGui.Add("DateTime", "x235 y260 w100", "Time")

btnRunNow := MainGui.Add("Button", "x20 y295 w105 h30", "▶ Chạy ngay")
btnRunNow.OnEvent("Click", (*) => PrepareRun(false))

btnSchedule := MainGui.Add("Button", "x135 y295 w105 h30", "⏰ Lên lịch")
btnSchedule.OnEvent("Click", (*) => PrepareRun(true))

btnCancel := MainGui.Add("Button", "x250 y295 w105 h30", "✖ Hủy lịch")
btnCancel.OnEvent("Click", CancelSchedule)

lblStatus := MainGui.Add("Text", "x10 y345 w380 cRed", "Trạng thái: Đang chờ...")

; --- Danh sách hành động (-Multi để chỉ cho phép chọn 1 dòng) ---
lvActions := MainGui.Add("ListView", "x10 y365 w380 h160 Grid -Multi", ["Index", "Hành động", "P1", "P2", "P3"])
lvActions.ModifyCol(1, 45)
lvActions.ModifyCol(2, 75)
lvActions.ModifyCol(3, 85)
lvActions.ModifyCol(4, 85)
lvActions.ModifyCol(5, 85)

UpdateHint()

; ====== LOAD DỮ LIỆU TỪ INI KHI KHỞI ĐỘNG ======
LoadData()
RefreshListView() ; Cập nhật UI với dữ liệu vừa load
MainGui.Show("w400 h540")

; ==========================================
; 2. CÁC HÀM PERSISTENT (SAVE/LOAD INI)
; ==========================================

LoadData() {
    global ActionSequence := []
    
    ; Nếu file chưa tồn tại thì bỏ qua (chạy lần đầu)
    if !FileExist(IniFile)
        return
        
    ; Đọc tổng số action
    count := IniRead(IniFile, "Meta", "Count", 0)
    
    Loop count {
        section := "Action_" A_Index
        actType := IniRead(IniFile, section, "Type", "")
        p1 := IniRead(IniFile, section, "P1", "")
        p2 := IniRead(IniFile, section, "P2", "")
        p3 := IniRead(IniFile, section, "P3", "")
        
        ActionSequence.Push({ type: actType, p1: p1, p2: p2, p3: p3 })
    }
}

SaveData() {
    ; Xóa file cũ đi để tránh rác (ví dụ xóa từ 5 action xuống 3 action thì file sẽ update chuẩn)
    if FileExist(IniFile)
        FileDelete(IniFile)
        
    ; Ghi tổng số lượng actions
    IniWrite(ActionSequence.Length, IniFile, "Meta", "Count")
    
    ; Ghi từng action vào từng Section
    for index, act in ActionSequence {
        section := "Action_" index
        IniWrite(act.type, IniFile, section, "Type")
        IniWrite(act.p1, IniFile, section, "P1")
        IniWrite(act.p2, IniFile, section, "P2")
        IniWrite(act.p3, IniFile, section, "P3")
    }
}

; ==========================================
; 3. CÁC HÀM XỬ LÝ GIAO DIỆN & LISTVIEW
; ==========================================

UpdateHint(*) {
    act := ddlAction.Text
    hint := ""
    switch act {
        case "WinActive": hint := "P1: WinTitle (Trống = Active Win) | P2: WinText | P3: Exclude"
        case "Click": hint := "P1: X | P2: Y | P3: Options (vd: Right, Down, Up)"
        case "SendKey": hint := "P1: Text/Key | P2: WinTitle (Trống = Active Win) | P3: Control"
        case "Sleep": hint := "P1: Thời gian trễ (ms. 1000 = 1 giây)"
        case "Log": hint := "P1: Dòng text để ghi ra Debug Console"
        case "Notif": hint := "P1: Nội dung | P2: Tiêu đề (Title)"
        case "WaitFor": hint := "P1: 'Exist' hoặc 'Active' | P2: WinTitle (Trống = Active) | P3: Timeout"
        case "Exit": hint := "Thoát toàn bộ Script"
    }
    txtHint.Value := hint
}

; --- Làm mới giao diện ListView ---
RefreshListView() {
    lvActions.Delete()
    for index, act in ActionSequence {
        lvActions.Add("", index, act.type, act.p1, act.p2, act.p3)
    }
    ; GỌI LƯU NGAY KHI CÓ BẤT KỲ THAY ĐỔI NÀO (Tự động Persist)
    SaveData()
}

AddAction(*) {
    act := ddlAction.Text
    p1 := edtP1.Value, p2 := edtP2.Value, p3 := edtP3.Value
    ActionSequence.Push({ type: act, p1: p1, p2: p2, p3: p3 })
    RefreshListView()
    edtP1.Focus()
}

DeleteAction(*) {
    row := lvActions.GetNext(0)
    if (row > 0) {
        ActionSequence.RemoveAt(row)
        RefreshListView()

        ; Focus lại vào dòng gần đó để dễ thao tác tiếp
        if (ActionSequence.Length > 0) {
            newFocus := (row > ActionSequence.Length) ? ActionSequence.Length : row
            lvActions.Modify(newFocus, "Select Focus")
        }
    } else {
        MsgBox("Vui lòng chọn một dòng để xóa!", "Cảnh báo", "Icon!")
    }
}

MoveUp(*) {
    row := lvActions.GetNext(0)
    if (row > 1) {
        ; Đảo vị trí trong mảng
        temp := ActionSequence[row]
        ActionSequence[row] := ActionSequence[row - 1]
        ActionSequence[row - 1] := temp

        RefreshListView()
        lvActions.Modify(row - 1, "Select Focus") ; Giữ bôi đen dòng vừa di chuyển
    }
}

MoveDown(*) {
    row := lvActions.GetNext(0)
    if (row > 0 && row < ActionSequence.Length) {
        ; Đảo vị trí trong mảng
        temp := ActionSequence[row]
        ActionSequence[row] := ActionSequence[row + 1]
        ActionSequence[row + 1] := temp

        RefreshListView()
        lvActions.Modify(row + 1, "Select Focus") ; Giữ bôi đen dòng vừa di chuyển
    }
}

ClearSequence(*) {
    global ActionSequence := []
    RefreshListView()
    CancelSchedule()
}

; ==========================================
; 4. CÁC HÀM XỬ LÝ LOGIC CHẠY (ENGINE)
; ==========================================

CancelSchedule(*) {
    global PendingTask
    if (PendingTask) {
        SetTimer(PendingTask, 0)
        PendingTask := ""
        lblStatus.Value := "Trạng thái: Đã hủy lịch hẹn."
    }
}

PrepareRun(isScheduled) {
    global PendingTask

    if (ActionSequence.Length == 0) {
        MsgBox("Danh sách trống!", "Cảnh báo", "Icon!")
        return
    }

    startIdx := IsInteger(edtIndex.Value) ? Integer(edtIndex.Value) : 1

    if (startIdx < 1 || startIdx > ActionSequence.Length) {
        MsgBox("Entry index không hợp lệ! Vui lòng chọn từ 1 đến " ActionSequence.Length, "Lỗi", "IconX")
        return
    }

    if (!isScheduled) {
        CancelSchedule()
        ExecuteChain(startIdx)
    } else {
        CancelSchedule()

        targetTime := dtpTime.Value
        diffSecs := DateDiff(targetTime, A_Now, "Seconds")

        if (diffSecs <= 0) {
            targetTime := DateAdd(targetTime, 1, "Days")
            diffSecs := DateDiff(targetTime, A_Now, "Seconds")
        }

        dispTime := FormatTime(targetTime, "dd/MM/yyyy HH:mm:ss")
        lblStatus.Value := "Trạng thái: Đang hẹn giờ chạy lúc " dispTime

        PendingTask := () => ExecuteChain(startIdx)
        SetTimer(PendingTask, -(diffSecs * 1000))
    }
}

ExecuteChain(startIdx) {
    global PendingTask := ""
    lblStatus.Value := "Trạng thái: Đang chạy (từ bước " startIdx ")..."

    loop ActionSequence.Length - startIdx + 1 {
        currentIndex := startIdx + A_Index - 1
        act := ActionSequence[currentIndex]
        p1 := act.p1, p2 := act.p2, p3 := act.p3

        switch act.type {
            case "WinActive":
                targetWin := (p1 != "") ? p1 : "A"
                if WinExist(targetWin, p2, p3)
                    WinActivate(targetWin, p2, p3)
                else
                    OutputDebug("Window not found: " targetWin)

            case "Click":
                clickStr := p1 " " p2
                if (p3 != "")
                    clickStr .= " " p3
                Click(clickStr)

            case "SendKey":
                targetWin := (p2 != "") ? p2 : "A"
                try {
                    OutputDebug(p3)
                    OutputDebug(targetWin)
                    OutputDebug(p1)
                    ControlSend(p1, , targetWin)
                } catch as err {
                    OutputDebug("ControlSend Error: " err.Message)
                }

            case "Sleep":
                if IsInteger(p1)
                    Sleep(p1)

            case "Log":
                OutputDebug("LOG: " p1 "`n")

            case "Notif":
                title := (p2 != "") ? p2 : "Notification"
                TrayTip(p1, title, "Iconi")

            case "WaitFor":
                targetWin := (p2 != "") ? p2 : "A"
                timeout := IsInteger(p3) ? p3 : ""

                if (p1 = "Exist") {
                    if !WinWait(targetWin, , timeout)
                        OutputDebug("WaitFor Exist Timeout: " targetWin)
                } else if (p1 = "Active") {
                    if !WinWaitActive(targetWin, , timeout)
                        OutputDebug("WaitFor Active Timeout: " targetWin)
                }

            case "Exit":
                ExitApp()
        }
    }

    lblStatus.Value := "Trạng thái: Hoàn thành chuỗi!"
    TrayTip("Đã chạy xong tất cả hành động!", "Auto Action Scheduler", "Iconi")
}
