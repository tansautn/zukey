#Requires AutoHotkey v2.0
#Include "libs\JSON.ahk"
targetExe := "xiaowei.exe"
tempDir := A_ScriptDir . "\auto-backup-code"
ocrUrl := "https://f.zuko.pro/api/tools/ocr/backup-codes"
DirCreate(tempDir)
main() {
    global targetExe
    global tempDir
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
        WinActivate("ahk_exe " targetExe)
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
            screenshotFile := tempDir . "\" . deviceSerial . ".png"
            if FileExist(screenshotFile) {
                FileDelete(screenshotFile)
            }
;            Pause
            if !TakeADBScreenshot(deviceSerial, screenshotFile) {
                ; Try alternative method
                if !TakeADBScreenshotAlternative(deviceSerial, screenshotFile) {
                    throw Error("Failed to take screenshot for device: " . deviceSerial)
                }
            }
            ; 5. Convert image to base64
            base64Image := ImageToBase64(screenshotFile)
;            MsgBox "Base64 length: " . StrLen(base64Image)
;            MsgBox base64Image
            if (base64Image = "") {
                throw Error("Failed to convert image to base64 for device: " . deviceSerial)
            }
            
            ; 6. Call OCR API
            ToolTip "Processing OCR for device: " . deviceSerial, 100, 100
            ocrResult := PostBase64ToOCR(base64Image)
            jsonOcr := JSON.Load(ocrResult)
;            MsgBox(JSON.Dump(jsonOcr))
;            Pause
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

; --- Function: Take screenshot using ADB (Fixed Version) ---
TakeADBScreenshot(deviceSerial, savePath) {
    try {
        shell := ComObject("WScript.Shell")

        ; Method 1: Sử dụng PowerShell với proper escaping
        cmd := 'powershell -Command "& {adb -s `"' . deviceSerial . '`" exec-out screencap -p | Set-Content -Path `"' . savePath . '`" -Encoding Byte -NoNewline}"'

        OutputDebug("Executing command: " . cmd)

        exec := shell.Exec(cmd)
        exec.StdIn.Close()

        ; Wait for completion với timeout
        timeout := 10000  ; 10 seconds
        startTime := A_TickCount

        while (exec.Status = 0) {
            if (A_TickCount - startTime > timeout) {
                OutputDebug("Screenshot command timed out")
                return false
            }
            Sleep 100
        }

        ; Check exit code
        if (exec.ExitCode != 0) {
            OutputDebug("ADB command failed with exit code: " . exec.ExitCode)
            errorOutput := exec.StdErr.ReadAll()
            OutputDebug("Error output: " . errorOutput)
            return false
        }

        ; Verify file exists and has content
        if (!FileExist(savePath)) {
            OutputDebug("Screenshot file was not created: " . savePath)
            return false
        }

        ; Check file size (should be > 0)
        fileObj := FileOpen(savePath, "r")
        fileSize := fileObj.Length
        fileObj.Close()

        if (fileSize = 0) {
            OutputDebug("Screenshot file is empty: " . savePath)
            return false
        }

        OutputDebug("Screenshot saved successfully: " . savePath . " (Size: " . fileSize . " bytes)")
        return true

    } catch Error as e {
        OutputDebug("Exception in TakeADBScreenshot: " . e.message)
        return false
    }
}

; Alternative method using cmd if PowerShell doesn't work
TakeADBScreenshotAlternative(deviceSerial, savePath) {
    try {
        shell := ComObject("WScript.Shell")

        ; Create temporary path in system temp
        tempFile := EnvGet("TEMP") . "\adb_screenshot_" . A_TickCount . ".png"

        ; Use cmd with proper quoting
        cmd := 'cmd /c "adb -s ' . deviceSerial . ' exec-out screencap -p > "' . tempFile . '""'

        OutputDebug("Executing alternative command: " . cmd)

        exec := shell.Exec(cmd)
        exec.StdIn.Close()

        ; Wait for completion
        while (exec.Status = 0) {
            Sleep 100
        }

        ; Move temp file to final location
        if (FileExist(tempFile)) {
            FileCopy tempFile, savePath, 1
            FileDelete(tempFile)
            return FileExist(savePath)
        }

        return false

    } catch Error as e {
        OutputDebug("Exception in TakeADBScreenshotAlternative: " . e.message)
        return false
    }
}

; Updated main function call
; Replace the TakeADBScreenshot call in main() with:
/*
if !TakeADBScreenshot(deviceSerial, screenshotFile) {
    ; Try alternative method
    if !TakeADBScreenshotAlternative(deviceSerial, screenshotFile) {
        throw Error("Failed to take screenshot for device: " . deviceSerial)
    }
}
*/
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
        ; Parse JSON response
        jsonObj := JSON.Load(jsonResponse)

        ; Check if API returned success
        if (!jsonObj.Has("ok") || !jsonObj["ok"]) {
            ; API returned error
            errorMessage := jsonObj.Has("message") ? jsonObj["message"] : "Unknown API error"
            MsgBox("API Error: " . errorMessage, "OCR Error", 16) ; 16 = Error icon
            return ""
        }

        ; Extract ParsedText from successful response
        if (jsonObj.Has("data") && jsonObj["data"].Has("ParsedResults") && jsonObj["data"]["ParsedResults"].Length > 0) {
            parsedResult := jsonObj["data"]["ParsedResults"][1] ; First result
            if (parsedResult.Has("ParsedText")) {
                return parsedResult["ParsedText"]
            }
        }

        ; Fallback if structure is unexpected
        MsgBox("Unexpected API response structure", "OCR Warning", 48) ; 48 = Warning icon
        return jsonResponse

    } catch Error as e {
        ; JSON parsing failed
        MsgBox("Failed to parse API response: " . e.message, "Parse Error", 16)
        return ""
    }
}

; --- Function: Save results to JSON ---
SaveResultsToJSON(results) {
    try {
        jsonContent := "{"
        first := true

        for deviceSerial, parsedText in results {
            if (!first) {
                jsonContent .= ","
            }
            ; Only save ParsedText content
            jsonContent .= "`n  `"" . deviceSerial . "`": `"" . StrReplace(parsedText, '"', '\"') . "`""
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

        for deviceSerial, parsedText in results {
            if (clipboardText != "") {
                clipboardText .= "`n"
            }
            ; Only copy ParsedText content
            clipboardText .= parsedText
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
        global ocrUrl
        http := ComObject("WinHttp.WinHttpRequest.5.1")
        http.Open("POST", ocrUrl, true)
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
^+F1::main()
