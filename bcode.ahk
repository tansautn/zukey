#Requires AutoHotkey v2.0

; --------- CONFIGURATION ---------
TempDir       := A_ScriptDir "\temp\ahk-auto-backup-code"      ; where screenshots are stored
OCRApi        := "https://f.zuko.pro/api/tools/ocr/parse"        ; OCR endpoint

; --------- ENTRY POINT ---------
main()
return

main() {
    global TempDir, OCRApi
    try {
        DirCreate(TempDir)
        ToolTip "Loading..."

        serials := ListAdbDevices()
        if (serials.Length = 0)
            throw Error("No connected devices found via ADB")

        resultMap := Map()
        debugLog  := "Devices:" . StrJoin(serials, ", ") . "`n"

        for serial in serials {
            try {
                imgPath := TempDir "\" serial ".png"
                CaptureDeviceScreenshot(serial, imgPath)
                debugLog .= "Captured " serial " -> " imgPath "`n"

                base64 := ImageFileToBase64(imgPath)
                debugLog .= "Base64Size(" serial ")=" base64.Length "`n"

                ocr := PostBase64ToOCR(base64)
                debugLog .= "OCRResponse(" serial ")=" ocr "`n"

                ; join multi-line result to one line
                ocrClean := StrReplace(StrReplace(ocr, "`r"), "`n")
                resultMap[serial] := ocrClean
            } catch e {
                throw Error("Serial " serial " failed: " e.Message)
            }
        }

        ; save JSON to result.json
        json := MapToJson(resultMap)
        FileDelete("result.json")
        FileAppend(json, "result.json")

        ; copy values to clipboard (1 line / value)
        clip := ""
        for , v in resultMap
            clip .= v "`n"
        Clipboard := Trim(clip, "`n")

        ToolTip ""
        MsgBox "DONE"
    } catch e {
        ToolTip ""
        MsgBox "ERROR: " e.Message
        ; dump debug information to console
        OutputDebug("AHK-DEBUG:\n" debugLog)
    }
}

; --------- FUNCTIONS ---------

ListAdbDevices() {
    out := ""
    RunWait A_ComSpec " /c adb devices", , "Hide StdOut Var out"

    serials := []
    for line in StrSplit(out, "`n", "`r") {
        line := Trim(line)
        if (line = "" || InStr(line, "List of devices"))
            continue
        parts := StrSplit(line, "`t")
        serial := Trim(parts[1])
        status := parts.Length > 1 ? Trim(parts[2]) : ""
        if (serial != "" && status = "device")
            serials.Push(serial)
    }
    return serials
}

CaptureDeviceScreenshot(serial, savePath) {
    RunWait A_ComSpec " /c adb -s " serial " exec-out screencap -p > \"" savePath "\"", , "Hide"
    if !FileExist(savePath)
        throw Error("Screenshot not saved for " serial)
}

ImageFileToBase64(path) {
    file := FileOpen(path, "r")
    if !file
        throw Error("Cannot open image file " path)
    buf := Buffer(file.Length, 0)
    file.RawRead(buf, buf.Size)
    file.Close()
    return CryptBinaryToBase64(buf)
}

MapToJson(m) {
    json := "{"
    for k, v in m
        json .= '"' k '":"' StrReplace(v, '"', '\\"') '",' 
    return SubStr(json, 1, -1) "}"
}

; --- Function: Convert binary to base64 ---
CryptBinaryToBase64(data) {
    size := BufGetSize(data)
    DllCall("crypt32\\CryptBinaryToStringW", "ptr", data, "uint", size, "uint", 0x40000001, "ptr", 0, "uint*", &len := 0)
    out := Buffer(len * 2, 0)
    DllCall("crypt32\\CryptBinaryToStringW", "ptr", data, "uint", size, "uint", 0x40000001, "ptr", out, "uint*", &len)
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
    global OCRApi
    http := ComObject("WinHttp.WinHttpRequest.5.1")
    http.Open("POST", OCRApi, true)
    http.SetRequestHeader("Content-Type", "application/json")
    body := "{" '"base64Image":"' base64Image '"}'
    http.Send(body)
    http.WaitForResponse()
    return http.ResponseText
}
