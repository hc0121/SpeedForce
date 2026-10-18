; ============================================================
;  Speed Force  (AutoHotkey v2)
;  用途：在英文模式下誤打注音按鍵（例如 su3cl3 = 你好）時，
;        自動提示，並可一鍵切換成微軟注音重新輸入。
;  熱鍵：Ctrl+Alt+Z  修正剛打的字（或先選取錯字再按）
; ============================================================
#Requires AutoHotkey v2.0
#SingleInstance Force
Persistent
InstallKeybdHook
SendMode "Event"
SetKeyDelay 25, 10

; ===================== 設定（可自行修改） =====================
global FixHotkey   := "^!z"        ; 修正熱鍵：Ctrl+Alt+Z
global HotkeyName  := "Ctrl+Alt+Z"
global AutoDetect  := true         ; 打錯時自動提示
global AutoFix     := false        ; true = 偵測到就直接自動修正（不只提示）
global BeepOnAlert := true         ; 提示時嗶一聲
global AutoEnter   := true         ; 重打後自動按 Enter 確認選字（只在確認已切到中文模式時才按）
global IdleMs      := 700          ; 停筆多久（毫秒）後檢查
global ZhTW_HKL    := 0x04040404   ; 繁體中文（台灣）鍵盤配置

; ===================== 注音鍵盤對照 =====================
global ZKeys := "1qaz2wsxedcrfv5tgbyhnujm8ik,9ol.0p;/-6347 "
global ZSyms := "ㄅㄆㄇㄈㄉㄊㄋㄌㄍㄎㄏㄐㄑㄒㄓㄔㄕㄖㄗㄘㄙㄧㄨㄩㄚㄛㄜㄝㄞㄟㄠㄡㄢㄣㄤㄥㄦˊˇˋ˙ "
global ZMap := Map()
Loop StrLen(ZKeys)
    ZMap[SubStr(ZKeys, A_Index, 1)] := SubStr(ZSyms, A_Index, 1)

; 一個注音音節：[聲母]?[介音]?[韻母]?[聲調]   聲調: 6=ˊ 3=ˇ 4=ˋ 7=˙ 空白=一聲
global SylRe := "(?=[^3467 ])[1qaz2wsxedcrfv5tgbyhn]?[ujm]?[8ik,9ol.0p;/\-]?[3467 ]"

ToZhuyin(s) {
    out := ""
    Loop Parse StrLower(s)
        out .= ZMap.Has(A_LoopField) ? ZMap[A_LoopField] : A_LoopField
    return out
}

; 嚴格判斷：用來「自動偵測」，盡量避免把一般英文誤判
IsZhuyinStrict(s) {
    s := StrLower(s)
    if !RegExMatch(s, "^(?:" SylRe ")+\s*$")
        return false
    RegExReplace(s, SylRe, "", &syl)
    keys  := StrLen(RegExReplace(s, "\s"))
    tones := StrLen(RegExReplace(s, "[^3467]"))
    return (syl = 1 && tones >= 1 && keys >= 3)
        || (syl >= 2 && tones >= 1 && keys >= 4)
        || (syl >= 3 && keys >= 6)
}

; 寬鬆判斷：用來「手動修正」，只要全部都是注音鍵就接受
IsZhuyinLoose(s) {
    s := StrLower(Trim(s, " `t`r`n"))
    return s != "" && RegExMatch(s, "^[1qaz2wsxedcrfv5tgbyhnujm8ik,9ol.0p;/\-3467 ]+$")
}

; ===================== 視窗 / 輸入法 狀態 =====================
GetFocusHwnd(hwnd) {
    tid := DllCall("GetWindowThreadProcessId", "Ptr", hwnd, "Ptr", 0, "UInt")
    gti := Buffer(A_PtrSize = 8 ? 72 : 48, 0)
    NumPut("UInt", gti.Size, gti)
    if DllCall("GetGUIThreadInfo", "UInt", tid, "Ptr", gti) {
        f := NumGet(gti, 8 + A_PtrSize, "Ptr")
        if f
            return f
    }
    return hwnd
}

GetLayout(hwnd) {
    f := GetFocusHwnd(hwnd)
    tid := DllCall("GetWindowThreadProcessId", "Ptr", f, "Ptr", 0, "UInt")
    return DllCall("GetKeyboardLayout", "UInt", tid, "Ptr")
}

IsZhTWLayout(hwnd) => (GetLayout(hwnd) & 0xFFFF) = 0x0404

ImeWnd(hwnd) => DllCall("imm32\ImmGetDefaultIMEWnd", "Ptr", GetFocusHwnd(hwnd), "Ptr")

GetConvMode(hwnd) {
    w := ImeWnd(hwnd)
    if !w
        return 0
    try return SendMessage(0x283, 0x001, 0, w)      ; WM_IME_CONTROL, IMC_GETCONVERSIONMODE
    return 0
}

SetConvMode(hwnd, mode) {
    w := ImeWnd(hwnd)
    if !w
        return
    try SendMessage(0x283, 0x006, 1, w)             ; IMC_SETOPENSTATUS = 開啟
    try SendMessage(0x283, 0x002, mode, w)          ; IMC_SETCONVERSIONMODE
}

; 目前是否真的在「中文輸入」狀態（配置為 zh-TW 且輸入法在中文模式）
IsChinese(hwnd) => IsZhTWLayout(hwnd) && (GetConvMode(hwnd) & 1)

; 是否有組字中（有底線）  1=有 0=沒有 -1=無法判斷
IsComposing(hwnd) {
    f := GetFocusHwnd(hwnd)
    himc := DllCall("imm32\ImmGetContext", "Ptr", f, "Ptr")
    if !himc
        return -1
    len := DllCall("imm32\ImmGetCompositionStringW", "Ptr", himc, "UInt", 0x0008, "Ptr", 0, "UInt", 0, "Int")
    DllCall("imm32\ImmReleaseContext", "Ptr", f, "Ptr", himc)
    return len > 0 ? 1 : 0
}

; 切到 zh-TW 注音並確保中文模式；回傳是否已「確認」在中文模式
EnsureChinese(hwnd) {
    if !IsZhTWLayout(hwnd) {
        PostMessage 0x50, 0, ZhTW_HKL, , "ahk_id " hwnd      ; WM_INPUTLANGCHANGEREQUEST
        Loop 24 {
            Sleep 25
            if IsZhTWLayout(hwnd)
                break
        }
        if !IsZhTWLayout(hwnd)
            return false
        Sleep 120
    }
    if !(GetConvMode(hwnd) & 1) {
        SetConvMode(hwnd, 1)
        Sleep 80
        if !(GetConvMode(hwnd) & 1) {
            Send "{Shift}"          ; 微軟注音預設用 Shift 切換中/英
            Sleep 150
        }
    }
    return IsChinese(hwnd)
}

; ===================== 重打按鍵 =====================
Replay(seq) {
    Loop Parse StrLower(seq) {
        c := A_LoopField
        if c = " "
            Send "{Space}"
        else if RegExMatch(c, "^[a-z0-9,./;\-]$")
            Send "{" c "}"
        Sleep 20
    }
}

; ===================== 提示 =====================
Tip(text, ms := 3000) {
    if CaretGetPos(&x, &y)
        ToolTip text, x, y + 28
    else
        ToolTip text
    SetTimer () => ToolTip(), -ms
}

; ===================== 輸入監看 =====================
global ih := InputHook("V I")      ; V=不攔截  I=忽略本程式送出的按鍵
ih.KeyOpt("{Enter}{Tab}{Esc}{Left}{Right}{Up}{Down}{Home}{End}{PgUp}{PgDn}{Delete}", "N")
ih.OnChar := OnChar
ih.OnKeyDown := OnKeyDown
ih.Start()

ResetBuf() {
    SetTimer CheckTimer, 0
    ih.Stop()
    ih.Start()
}

OnChar(hook, ch) {
    if AutoDetect
        SetTimer CheckTimer, -IdleMs
}

OnKeyDown(hook, vk, sc) {
    if (vk = 0x0D || vk = 0x09)        ; Enter / Tab：字已送出，只提示不能自動修
        Check(false)
    ResetBuf()
}

CheckTimer() => Check(true)

Check(canFix := true) {
    buf := ih.Input
    if buf = "" || !AutoDetect
        return
    if !IsZhuyinStrict(buf)
        return
    hwnd := WinExist("A")
    if !hwnd || IsChinese(hwnd)         ; 本來就在中文模式，是正常打字
        return
    if (AutoFix && canFix) {
        DoFix()
        return
    }
    if BeepOnAlert
        SoundBeep 880, 120
    Tip("⚠ 忘了切注音？   " Trim(buf) "  →  " ToZhuyin(buf)
      . "`n按 " HotkeyName " 修正" (canFix ? "" : "（請先選取打錯的字）"), 4500)
}

~LButton::ResetBuf()
~RButton::ResetBuf()
~MButton::ResetBuf()

global LastWin := 0
SetTimer WatchWin, 250
WatchWin() {
    global LastWin
    w := WinExist("A")
    if (w != LastWin) {
        LastWin := w
        ResetBuf()
    }
}

; ===================== 修正 =====================
DoFix(*) {
    KeyWait "Ctrl"
    KeyWait "Alt"
    KeyWait "Shift"
    hwnd := WinExist("A")
    if !hwnd
        return
    seq := "", fromBuf := false
    buf := ih.Input
    if (buf != "" && IsZhuyinLoose(buf)) {
        seq := buf, fromBuf := true
    } else if !WinActive("ahk_class ConsoleWindowClass") && !WinActive("ahk_class CASCADIA_HOSTING_WINDOW_CLASS") {
        saved := ClipboardAll()
        A_Clipboard := ""
        Send "^c"
        if ClipWait(0.4) {
            t := Trim(A_Clipboard, " `t`r`n")
            if IsZhuyinLoose(t)
                seq := t
        }
        A_Clipboard := saved
    }
    if seq = "" {
        Tip("找不到可修正的內容：請先選取打錯的英文字，再按 " HotkeyName)
        return
    }
    ResetBuf()
    ok := EnsureChinese(hwnd)
    SetCapsLockState "Off"
    if fromBuf
        Send "{BS " StrLen(buf) "}"
    Replay(seq)
    Sleep 150
    if (ok && AutoEnter && IsComposing(hwnd) != 0) {
        Send "{Enter}"
        Tip("✓ 已切到注音並重打：" ToZhuyin(seq), 2000)
    } else {
        Tip("已切到注音並重打：" ToZhuyin(seq) "`n若文字仍有底線，請按 Enter 確認", 3500)
    }
}

Hotkey FixHotkey, DoFix

; ===================== 托盤選單 =====================
A_TrayMenu.Delete()
A_TrayMenu.Add("自動偵測打錯注音", ToggleDetect)
A_TrayMenu.Add("偵測到就直接自動修正", ToggleAutoFix)
A_TrayMenu.Add("提示音", ToggleBeep)
A_TrayMenu.Add("重打後自動按 Enter", ToggleEnter)
A_TrayMenu.Add()
A_TrayMenu.Add("開機自動啟動", ToggleStartup)
A_TrayMenu.Add()
A_TrayMenu.Add("離開", (*) => ExitApp())
A_TrayMenu.Default := "自動偵測打錯注音"
A_IconTip := "Speed Force  (" HotkeyName " 修正)"

ToggleDetect(*) {
    global AutoDetect
    AutoDetect := !AutoDetect
    UpdateMenu()
}
ToggleAutoFix(*) {
    global AutoFix
    AutoFix := !AutoFix
    UpdateMenu()
}
ToggleBeep(*) {
    global BeepOnAlert
    BeepOnAlert := !BeepOnAlert
    UpdateMenu()
}
ToggleEnter(*) {
    global AutoEnter
    AutoEnter := !AutoEnter
    UpdateMenu()
}

StartupLnk := A_Startup "\SpeedForce.lnk"
ToggleStartup(*) {
    if FileExist(StartupLnk)
        FileDelete StartupLnk
    else
        FileCreateShortcut A_ScriptFullPath, StartupLnk, A_ScriptDir
    UpdateMenu()
}

SetCheck(name, on) {
    if on
        A_TrayMenu.Check(name)
    else
        A_TrayMenu.Uncheck(name)
}

UpdateMenu() {
    SetCheck("自動偵測打錯注音", AutoDetect)
    SetCheck("偵測到就直接自動修正", AutoFix)
    SetCheck("提示音", BeepOnAlert)
    SetCheck("重打後自動按 Enter", AutoEnter)
    SetCheck("開機自動啟動", FileExist(StartupLnk))
}
UpdateMenu()
TrayTip "Speed Force 已啟動", "打錯注音時會提示，按 " HotkeyName " 一鍵修正", 1
