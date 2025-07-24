#Requires AutoHotkey v2.0

targetExe := "xiaowei.exe"

main() {
    global 
    local devices := []
    local results := Map()
    local errorMsg := ""
    local base64Image := ""
    local screenshotFile := ""
    local httpResponse := ""
    local httpCode := 0
    
    try {
        ; Hiện tooltip loading
        ToolTip "Loading... Getting ADB devices", 100, 100
        
        ; 1. Activate target window (optional check)
        if !WinExist("ahk_exe " targetExe) {
            MsgBox "Window not found: " targetExe ". Continuing with ADB operations..."
        }
        
        ; 2. List ADB devices
        ToolTip "Getting ADB device list...", 100, 100
        devices := GetADBDevices()
        
        if (devices.Length = 0) {
            throw Error("No ADB devices found")
        }
        
        ; 3. Loop through each device
        for index, deviceSerial in devices {
            ToolTip "Processing device " . index . "/" . devices.Length . ": " . deviceSerial, 100, 100
            
            ; 4. Take screenshot using ADB
            screenshotFile := "temp/ahk-auto-backup-code/" . deviceSerial . ".png"
            if !TakeADBScreenshot(deviceSerial, screenshotFile) {
                throw Error("Failed to take screenshot for device: " . deviceSerial)
            }
            
            ; 5. Convert image to base64
            base64Image := ImageToBase64(screenshotFile)
            if (base64Image = "") {
                throw Error("Failed to convert image to base64 for device: " . deviceSerial)
            }
            
            ; 6. Call OCR API
            ToolTip "Processing OCR for device: " . deviceSerial, 100, 100
            ocrResult := PostBase64ToOCR(base64Image)
            if (ocrResult = "") {
                throw Error("Failed to get OCR result for device: " . deviceSerial)
            }
            
            ; Parse OCR response to get text content
            ocrText := ParseOCRResponse(ocrResult)
            
            ; 7. Store result
            results[deviceSerial] := ocrText
        }
        
        ; 8. Save results to JSON
        SaveResultsToJSON(results)
        
        ; 9. Copy results to clipboard
        CopyResultsToClipboard(results)
        
        ; Hide tooltip
        ToolTip
        
        ; 10. Show completion message
        MsgBox "DONE! Results copied to clipboard and saved to result.json"
        
    } catch Error as e {
        ; Hide tooltip
        ToolTip
        
        ; Show error message
        MsgBox "Error: " . e.message
        
        ; Debug output to console
        OutputDebug("=== ERROR DEBUG INFO ===")
        OutputDebug("Error message: " . e.message)
        OutputDebug("Devices found: " . (devices.Length > 0 ? Join(devices, ", ") : "None"))
        OutputDebug("Last screenshot file: " . screenshotFile)
        OutputDebug("Base64 length: " . StrLen(base64Image))
        OutputDebug("HTTP response: " . httpResponse)
        OutputDebug("HTTP code: " . httpCode)
        OutputDebug("=== END DEBUG INFO ===")
    }
}

; --- Function: Get ADB devices ---
GetADBDevices() {
    devices := []
    
    ; Run adb devices command
    shell := ComObject("WScript.Shell")
    exec := shell.Exec("adb devices")
    
    ; Wait for completion and get output
    exec.StdIn.Close()
    output := exec.StdOut.ReadAll()
    
    ; Parse output to extract device serials
    lines := StrSplit(output, "`n")
    for line in lines {
        line := Trim(line)
        if (line != "" && !InStr(line, "List of devices") && InStr(line, "device")) {
            parts := StrSplit(line, "`t")
            if (parts.Length >= 2) {
                deviceSerial := Trim(parts[1])
                if (deviceSerial != "") {
                    devices.Push(deviceSerial)
                }
            }
        }
    }
    
    return devices
}

; --- Function: Take screenshot using ADB ---
TakeADBScreenshot(deviceSerial, savePath) {
    try {
        ; Use adb to take screenshot
        shell := ComObject("WScript.Shell")
        
        ; Take screenshot on device
        cmd1 := "adb -s " . deviceSerial . " shell screencap -p /sdcard/screenshot.png"
        exec1 := shell.Exec(cmd1)
        exec1.StdIn.Close()
        
        ; Wait for completion
        while (exec1.Status = 0) {
            Sleep 100
        }
        
        ; Pull screenshot to local
        cmd2 := "adb -s " . deviceSerial . " pull /sdcard/screenshot.png " . savePath
        exec2 := shell.Exec(cmd2)
        exec2.StdIn.Close()
        
        ; Wait for completion
        while (exec2.Status = 0) {
            Sleep 100
        }
        
        ; Clean up device screenshot
        cmd3 := "adb -s " . deviceSerial . " shell rm /sdcard/screenshot.png"
        exec3 := shell.Exec(cmd3)
        exec3.StdIn.Close()
        
        ; Check if file exists
        return FileExist(savePath)
        
    } catch {
        return false
    }
}

; --- Function: Convert image to base64 ---
ImageToBase64(imagePath) {
    try {
        ; Read file as binary
        file := FileOpen(imagePath, "r")
        file.RawRead(data := Buffer(file.Length), file.Length)
        file.Close()
        
        ; Convert to base64
        return CryptBinaryToBase64(data)
    } catch {
        return ""
    }
}

; --- Function: Parse OCR response ---
ParseOCRResponse(jsonResponse) {
    try {
        ; Simple JSON parsing for the text field
        ; This is a basic implementation - you might want to use a proper JSON parser
        if (InStr(jsonResponse, '"text"')) {
            ; Extract text value from JSON
            start := InStr(jsonResponse, '"text"') + 7
            start := InStr(jsonResponse, '"', false, start) + 1
            end := InStr(jsonResponse, '"', false, start) - 1
            
            if (start > 0 && end > start) {
                text := SubStr(jsonResponse, start, end - start + 1)
                ; Join multiple lines if any
                return StrReplace(StrReplace(text, "`r`n", " "), "`n", " ")
            }
        }
        return jsonResponse ; Return full response if parsing fails
    } catch {
        return jsonResponse
    }
}

; --- Function: Save results to JSON ---
SaveResultsToJSON(results) {
    try {
        jsonContent := "{"
        first := true
        
        for deviceSerial, ocrText in results {
            if (!first) {
                jsonContent .= ","
            }
            jsonContent .= "`n  `"" . deviceSerial . "`": `"" . StrReplace(ocrText, '"', '\"') . "`""
            first := false
        }
        
        jsonContent .= "`n}"
        
        ; Save to file
        file := FileOpen("result.json", "w")
        file.Write(jsonContent)
        file.Close()
    } catch {
        ; Ignore file save errors
    }
}

; --- Function: Copy results to clipboard ---
CopyResultsToClipboard(results) {
    try {
        clipboardText := ""
        
        for deviceSerial, ocrText in results {
            if (clipboardText != "") {
                clipboardText .= "`n"
            }
            clipboardText .= ocrText
        }
        
        A_Clipboard := clipboardText
    } catch {
        ; Ignore clipboard errors
    }
}

; --- Function: Join array elements ---
Join(arr, separator) {
    result := ""
    for index, value in arr {
        if (index > 1) {
            result .= separator
        }
        result .= value
    }
    return result
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
    try {
        http := ComObject("WinHttp.WinHttpRequest.5.1")
        http.Open("POST", "https://f.zuko.pro/api/tools/ocr/parse", true)
        http.SetRequestHeader("Content-Type", "application/json")
        body := "{" . '"base64Image": "' . base64Image . '"}'
        http.Send(body)
        http.WaitForResponse()
        
        ; Store response for debugging
        global httpResponse := http.ResponseText
        global httpCode := http.Status
        
        return http.ResponseText
    } catch Error as e {
        global httpResponse := "Error: " . e.message
        global httpCode := 0
        return ""
    }
}

; --- Hotkey to run the script ---
F1::main()
