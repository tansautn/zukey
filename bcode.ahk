#Requires AutoHotkey v2.0

targetExe := "xiaowei.exe"

main() {
    global 
    ; 1. Activate target window
    if !WinExist("ahk_exe " targetExe) {
        MsgBox "Window not found: " targetExe
    ExitApp
    }

    ; Looping devices here
    ocrResult := PostBase64ToOCR(base64Image)

    ; 5. Debug output
    MsgBox "OCR Result:`n" ocrResult
}

; --- Function: Capture a window and save as PNG ---
CaptureWindowToPNG(winTitle, savePath) {
    hwnd := WinExist(winTitle)
    local si := Buffer(16, 0)   ; <-- initialize buffer properly
    local pBitmap := 0          ; <-- initialize pBitmap
    if !hwnd
        return false

    ; Get window size
    WinGetPos &x, &y, &w, &h, hwnd

    ; Create compatible DC and bitmap
    hDC := DllCall("GetDC", "ptr", hwnd, "ptr")
    mDC := DllCall("gdi32\CreateCompatibleDC", "ptr", hDC, "ptr")
    hBM := DllCall("gdi32\CreateCompatibleBitmap", "ptr", hDC, "int", w, "int", h, "ptr")
    if !hBM {
        DllCall("ReleaseDC", "ptr", hwnd, "ptr", hDC)
        return false
    }
    obm := DllCall("gdi32\SelectObject", "ptr", mDC, "ptr", hBM, "ptr")

    ; BitBlt capture
    success := DllCall("gdi32\BitBlt", "ptr", mDC, "int", 0, "int", 0, "int", w, "int", h, "ptr", hDC, "int", 0, "int", 0, "uint", 0x00CC0020)

    ; Init GDI+
    static gdiplusToken := 0
    if (gdiplusToken = 0) {
        si := Buffer(16, 0)
        NumPut("UInt", 1, si, 0)
        DllCall("gdiplus\GdiplusStartup", "ptr*", &gdiplusToken, "ptr", si, "ptr", 0)
    }

    ; Save to PNG
    DllCall("gdiplus\GdipCreateBitmapFromHBITMAP", "ptr", hBM, "ptr", 0, "ptr*", &pBitmap)
    clsid := GetEncoderClsid("image/png")
    DllCall("gdiplus\GdipSaveImageToFile", "ptr", pBitmap, "wstr", savePath, "ptr", clsid, "ptr", 0)
    DllCall("gdiplus\GdipDisposeImage", "ptr", pBitmap)

    ; Cleanup
    DllCall("gdi32\SelectObject", "ptr", mDC, "ptr", obm)
    DllCall("gdi32\DeleteObject", "ptr", hBM)
    DllCall("gdi32\DeleteDC", "ptr", mDC)
    DllCall("ReleaseDC", "ptr", hwnd, "ptr", hDC)

    return success
}

; --- Function: Get image encoder CLSID ---
GetEncoderClsid(mimeType) {
    DllCall("gdiplus\GdipGetImageEncodersSize", "uint*", &count := 0, "uint*", &size := 0)
    local buffer := Buffer(size, 0)
    DllCall("gdiplus\GdipGetImageEncoders", "uint", count, "uint", size, "ptr", buffer)

    Loop count {
        item := buffer.Ptr + (A_Index - 1) * 84  ; GpImageCodecInfo size
        if (StrGet(NumGet(item + 68, "ptr")) = mimeType)
            return item
    }
    return 0
}

; --- Function: Convert binary to base64 ---
CryptBinaryToBase64(data) {
    size := BufGetSize(data)
    DllCall("crypt32\CryptBinaryToStringW", "ptr", data, "uint", size, "uint", 0x40000001, "ptr", 0, "uint*", &len := 0)
    out := Buffer(len * 2, 0)
    DllCall("crypt32\CryptBinaryToStringW", "ptr", data, "uint", size, "uint", 0x40000001, "ptr", out, "uint*", &len)
    return StrReplace(StrGet(out), "`r`n", "")
}

; --- Helper: Get buffer size ---
BufGetSize(buf) {
    if (Type(buf) = "Buffer")
        return buf.Size
    return StrLen(buf)
}

; --- Function: POST base64 to API ---
PostBase64ToOCR(base64Image) {
    http := ComObject("WinHttp.WinHttpRequest.5.1")
    http.Open("POST", "https://f.zuko.pro/api/tools/ocr/parse", true)
    http.SetRequestHeader("Content-Type", "application/json")
    body := "{" . '"base64Image": "' . base64Image . '"}'
    http.Send(body)
    http.WaitForResponse()
    return http.ResponseText
}
