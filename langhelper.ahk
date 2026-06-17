#Requires AutoHotkey v2.0
#SingleInstance Force
; ============================================================================== 
;  LangHelper — Ctrl+C, Ctrl+C clipboard translator
;  Pairs with prompt.md and langhelper.ps1 (which calls `gh models run`).
; ============================================================================== 

; --- Paths --------------------------------------------------------------------
ScriptDir  := A_ScriptDir
IniPath    := ScriptDir "\langhelper.ini"
PromptPath := ScriptDir "\prompt.md"
PsPath     := ScriptDir "\langhelper.ps1"
LogPath    := ScriptDir "\langhelper.log"
LastResultPath := A_Temp "\langhelper_last_result.txt"

Log(msg) {
    global LogPath
    line := FormatTime(, "yyyy-MM-dd HH:mm:ss") "  " msg "`r`n"
    try FileAppend(line, LogPath, "UTF-8")
}
Log("=== LangHelper start ===")

; --- Catalog of features (NAME, Label) — must match prompt.md ----------------
FeatureCatalog := [
    ["POLISH",            "Polish (professional rewrite)"],
    ["BILINGUAL_EN_ZHTW", "Bilingual (English + 繁體中文)"],
    ["GLOSSARY",          "Glossary / term explanation"],
    ["TONE_VARIANTS",     "Tone variants (formal/friendly/concise)"],
    ["REPLY",             "Reply drafts (chat/email)"],
    ["SUMMARY",           "TL;DR / summary"],
    ["TECHNICAL",         "Technical (preserve code/identifiers)"],
    ["BACK_TRANSLATE",    "Back-translation sanity check"],
    ["ROMANIZE",          "Romanization (Pinyin/Romaji/RR)"]
]

ModelCatalog := [
    "openai/gpt-4.1-mini",
    "openai/gpt-4.1-nano",
    "openai/gpt-4.1",
    "openai/gpt-4o-mini",
    "openai/gpt-5-mini",
    "mistral-ai/mistral-small-2503",
    "meta/llama-3.3-70b-instruct"
]

; --- Settings (loaded from INI with defaults) --------------------------------
Settings := Map(
    "Features", IniRead(IniPath, "LangHelper", "Features", "POLISH"),
    "Model",    IniRead(IniPath, "LangHelper", "Model",    "openai/gpt-4.1-mini")
)

SaveSettings() {
    global Settings, IniPath
    IniWrite Settings["Features"], IniPath, "LangHelper", "Features"
    IniWrite Settings["Model"],    IniPath, "LangHelper", "Model"
}

; --- Tray menu ---------------------------------------------------------------
BuildTrayMenu()

BuildTrayMenu() {
    global Settings, ModelCatalog, PromptPath, LogPath
    tray := A_TrayMenu
    tray.Delete()
    tray.Add("LangHelper", (*) => 0)
    tray.Disable("LangHelper")
    tray.Add()
    tray.Add("Open translator window…", (*) => OpenSettings())

    modelMenu := Menu()
    for m in ModelCatalog {
        modelMenu.Add(m, ChooseModel)
        if (m = Settings["Model"])
            modelMenu.Check(m)
    }
    tray.Add("Model", modelMenu)

    tray.Add()
    tray.Add("Open prompt.md",   (*) => Run('"' PromptPath '"'))
    tray.Add("Show last result", (*) => ShowLastResult())
    tray.Add("Open log file",    (*) => Run('"' LogPath '"'))
    tray.Add("Dry-run on clipboard (preview prompt)", (*) => DryRunOnClipboard())
    tray.Add()
    tray.Add("Reload script", (*) => Reload())
    tray.Add("Exit",          (*) => ExitApp())

    A_IconTip := "LangHelper — Ctrl+C, Ctrl+C to translate`nFeatures: " Settings["Features"] "`nModel: " Settings["Model"]
}

ShowLastResult() {
    global LastResultPath
    if (!FileExist(LastResultPath)) {
        MsgBox("No translation has been run yet.", "LangHelper", 64)
        return
    }
    txt := FileRead(LastResultPath, "UTF-8")
    ShowOutputViewer("Last translation result", txt)
}

ChooseModel(item, *) {
    global Settings
    Settings["Model"] := item
    SaveSettings()
    BuildTrayMenu()
    TrayTip("LangHelper", "Model set to " item, 0x1)
}

OpenSettings() {
    text := ""
    try text := A_Clipboard
    ShowTranslatorWindow(text, false)
}

; --- Single active translator window -----------------------------------------
ActiveTranslator := ""

; --- Double-Ctrl+C trigger ---------------------------------------------------
LastCopyTick := 0

~^c:: {
    global LastCopyTick
    now := A_TickCount
    if (now - LastCopyTick < 400) {
        LastCopyTick := 0
        SetTimer(() => TriggerTranslation(false), -100)
    } else {
        LastCopyTick := now
    }
}

DryRunOnClipboard() {
    SetTimer(() => TriggerTranslation(true), -10)
}

TriggerTranslation(dryRun) {
    global Settings
    Sleep 50
    text := ""
    try text := A_Clipboard
    Log("Trigger fired (dryRun=" dryRun ", clipboard length=" StrLen(text) ")")
    if (Trim(text) = "") {
        MsgBox("Clipboard is empty. Select text and press Ctrl+C, Ctrl+C.", "LangHelper", 48)
        return
    }

    if (dryRun) {
        ToolTip("LangHelper: building prompt…")
        result := CallBackend(text, Settings["Features"], Settings["Model"], true)
        ToolTip()
        if (result.error != "") {
            MsgBox("LangHelper error:`n`n" result.error, "LangHelper", 16)
            return
        }
        ShowOutputViewer("Assembled prompt (dry-run)", result.output)
        return
    }

    ShowTranslatorWindow(text, true)
}

; --- Backend call (AHK -> PowerShell -> gh models run) ----------------------
CallBackend(text, features, model, dryRun) {
    global PsPath
    tmpIn  := A_Temp "\langhelper_in.txt"
    tmpOut := A_Temp "\langhelper_out.txt"
    tmpErr := A_Temp "\langhelper_err.txt"
    for f in [tmpIn, tmpOut, tmpErr]
        try FileDelete f
    FileAppend(text, tmpIn, "UTF-8")

    psArgs := '-NoProfile -ExecutionPolicy Bypass -File "' PsPath '"'
        . ' -Features "' features '"'
        . ' -Model "'    model    '"'
        . ' -InputFile "'  tmpIn  '"'
        . ' -OutputFile "' tmpOut '"'
    if (dryRun)
        psArgs .= ' -DryRun'

    cmdLine := 'cmd.exe /c powershell.exe ' psArgs ' 1>> "' tmpErr '" 2>&1'
    Log("Running: " cmdLine)
    exitCode := -1
    try {
        exitCode := RunWait(cmdLine, , "Hide")
    } catch as e {
        return { error: "RunWait failed: " e.Message, output: "", exit: -1 }
    }

    out := FileExist(tmpOut) ? FileRead(tmpOut, "UTF-8") : ""
    err := FileExist(tmpErr) ? FileRead(tmpErr, "UTF-8") : ""

    out := RTrim(out, " `t`r`n")
    err := Trim(err, " `t`r`n")

    if (exitCode != 0 && out = "")
        return { error: (err != "" ? err : "PowerShell exited with code " exitCode), output: "", exit: exitCode }
    if (out = "" && err != "")
        return { error: err, output: "", exit: exitCode }
    return { error: "", output: out, exit: exitCode }
}

; --- Combined translator window (source + features + result, live) ----------
FormatFeatures(featStr) {
    global FeatureCatalog
    if (Trim(featStr) = "")
        return "(default — Polish)"
    parts := []
    for item in FeatureCatalog {
        for f in StrSplit(featStr, ",")
            if (Trim(f) = item[1]) {
                parts.Push(item[2])
                break
            }
    }
    out := ""
    for i, p in parts
        out .= (i = 1 ? "" : ", ") p
    return out = "" ? featStr : out
}

ShowTranslatorWindow(sourceText, autoRun) {
    global FeatureCatalog, ModelCatalog, Settings, LastResultPath, ActiveTranslator

    ; Reuse the existing window if one is already open.
    if (IsObject(ActiveTranslator)) {
        try {
            ActiveTranslator.update.Call(sourceText, autoRun)
            return
        } catch {
            ActiveTranslator := ""
        }
    }

    selectedFeatures := Settings["Features"]
    chooseIdx := 1
    Loop ModelCatalog.Length
        if (ModelCatalog[A_Index] = Settings["Model"]) {
            chooseIdx := A_Index
            break
        }

    g := Gui("+Resize", "LangHelper")
    g.BackColor := "F4F5F7"
    g.SetFont("s10", "Segoe UI")
    g.MarginX := 16, g.MarginY := 14

    ; --- Header --------------------------------------------------------------
    g.SetFont("s15 Bold", "Segoe UI")
    g.Add("Text", "xm c1F2937 BackgroundTrans", "LangHelper")
    g.SetFont("s9 Norm", "Segoe UI")
    g.Add("Text", "xm y+2 c6B7280 BackgroundTrans", "Live clipboard translator · edits re-translate automatically")

    ; --- Input ---------------------------------------------------------------
    g.SetFont("s10 Bold", "Segoe UI")
    g.Add("Text", "xm y+14 c374151 BackgroundTrans", "Input")
    g.SetFont("s9 Norm", "Segoe UI")
    charCount := g.Add("Text", "xm yp w820 r1 c9CA3AF Right BackgroundTrans", StrLen(sourceText) " chars")
    g.SetFont("s10 Norm", "Segoe UI")
    inputEdit := g.Add("Edit", "xm y+4 w820 h110 +Wrap", sourceText)

    ; --- Original clipboard snapshot (de-emphasized) -------------------------
    g.SetFont("s9 Norm", "Segoe UI")
    g.Add("Text", "xm y+10 c9CA3AF BackgroundTrans", "Original clipboard snapshot")
    snapshotEdit := g.Add("Edit", "xm y+3 w820 h52 ReadOnly +Wrap c6B7280", sourceText)

    ; --- Features ------------------------------------------------------------
    g.SetFont("s10 Bold", "Segoe UI")
    g.Add("Text", "xm y+12 c374151 BackgroundTrans", "Features")
    g.SetFont("s10 Norm", "Segoe UI")
    featuresLabel := g.Add("Text", "x+10 yp w620 c4B5563 BackgroundTrans", FormatFeatures(selectedFeatures))
    cfgBtn := g.Add("Button", "xm y+6 w220", "⚙  Configure features…")

    ; --- Model ---------------------------------------------------------------
    g.SetFont("s10 Bold", "Segoe UI")
    g.Add("Text", "xm y+14 Section c374151 BackgroundTrans", "Model")
    g.SetFont("s10 Norm", "Segoe UI")
    ddModel := g.Add("DropDownList", "x+10 yp-3 w360 Choose" chooseIdx, ModelCatalog)

    ; --- Status --------------------------------------------------------------
    statusText := g.Add("Text", "xm y+16 w820 c059669 BackgroundTrans", "● Ready")

    ; --- Result --------------------------------------------------------------
    g.SetFont("s10 Bold", "Segoe UI")
    g.Add("Text", "xm y+8 c374151 BackgroundTrans", "Result")
    g.SetFont("s9 Norm", "Segoe UI")
    g.Add("Text", "x+10 yp+2 c9CA3AF BackgroundTrans", "· auto-copied to clipboard")
    g.SetFont("s10 Norm", "Segoe UI")
    resultEdit := g.Add("Edit", "xm y+4 w820 h280 ReadOnly +Wrap")

    ; --- Actions -------------------------------------------------------------
    copyBtn  := g.Add("Button", "xm y+12 w170 Default", "📋  Copy result")
    rerunBtn := g.Add("Button", "x+10 w150", "↻  Re-translate")
    closeBtn := g.Add("Button", "x+10 w120", "Close")

    state := { running: false, restartRequested: false, seq: 0 }

    GetSelected() {
        return selectedFeatures
    }

    SetStatus(msg, color) {
        statusText.SetFont("c" color)
        statusText.Value := msg
    }

    UpdateCharCount(*) {
        charCount.Value := StrLen(inputEdit.Value) " chars"
    }

    SetBusy(busy) {
        inputEdit.Enabled := !busy
        rerunBtn.Enabled := !busy
        copyBtn.Enabled  := !busy
        ddModel.Enabled  := !busy
        cfgBtn.Enabled   := !busy
    }

    DoTranslate(seq) {
        if (seq != state.seq)
            return
        if (state.running) {
            state.restartRequested := true
            return
        }

        textToTranslate := Trim(inputEdit.Value)
        if (textToTranslate = "") {
            SetStatus("● Input is empty", "9CA3AF")
            resultEdit.Value := ""
            return
        }

        feat := GetSelected()
        modl := ModelCatalog[ddModel.Value]
        Settings["Features"] := feat
        Settings["Model"]    := modl
        SaveSettings()
        BuildTrayMenu()

        state.running := true
        state.restartRequested := false
        SetBusy(true)
        SetStatus("◐ Translating with " modl " (" (feat = "" ? "default" : feat) ")…", "D97706")
        resultEdit.Value := ""
        SetTimer(() => RunOnce(textToTranslate, feat, modl, seq), -10)
    }

    RunOnce(textToTranslate, feat, modl, seq) {
        Log("Window translate  features=[" feat "]  model=" modl "  inputLen=" StrLen(textToTranslate))
        result := CallBackend(textToTranslate, feat, modl, false)
        Log("Window backend returned  exit=" result.exit "  outLen=" StrLen(result.output))
        state.running := false
        SetBusy(false)

        if (state.restartRequested || seq != state.seq) {
            SetTimer(() => DoTranslate(state.seq), -10)
            return
        }

        if (result.error != "") {
            SetStatus("✕ Error — see Open log file in tray", "DC2626")
            resultEdit.Value := result.error
            return
        }
        if (result.output = "") {
            SetStatus("● Empty response", "9CA3AF")
            return
        }
        resultEdit.Value := result.output
        A_Clipboard := result.output
        try FileDelete LastResultPath
        FileAppend(result.output, LastResultPath, "UTF-8")
        SetStatus("✓ Done — result copied to clipboard", "059669")
    }

    DebouncedTranslate(*) {
        state.seq += 1
        mySeq := state.seq
        SetTimer(() => DoTranslate(mySeq), -700)
    }

    ForceTranslate(*) {
        state.seq += 1
        DoTranslate(state.seq)
    }

    OpenFeatureConfig(*) {
        cfg := Gui("+Owner" g.Hwnd " +ToolWindow", "Configure Features")
        cfg.BackColor := "F4F5F7"
        cfg.SetFont("s10", "Segoe UI")
        cfg.MarginX := 16, cfg.MarginY := 14
        cfg.SetFont("s12 Bold", "Segoe UI")
        cfg.Add("Text", "xm c1F2937 BackgroundTrans", "Configure features")
        cfg.SetFont("s9 Norm", "Segoe UI")
        cfg.Add("Text", "xm y+2 c6B7280 BackgroundTrans", "Re-translates automatically when you save")
        cfg.SetFont("s10 Norm", "Segoe UI")
        cfg.Add("Text", "xm y+10 c374151 BackgroundTrans", "Select features to apply:")

        enabledNow := Map()
        for f in StrSplit(selectedFeatures, ",")
            if (Trim(f) != "")
                enabledNow[Trim(f)] := true

        cfgBoxes := Map()
        for i, item in FeatureCatalog {
            name := item[1], label := item[2]
            opts := (Mod(i, 2) = 1) ? "xm y+10 w360 v" name : "x+12 yp w360 v" name
            if (enabledNow.Has(name))
                opts .= " Checked"
            cfgBoxes[name] := cfg.Add("CheckBox", opts, label)
        }

        SaveCfg(*) {
            names := []
            for item in FeatureCatalog {
                n := item[1]
                if (cfgBoxes[n].Value)
                    names.Push(n)
            }
            joined := ""
            for i, n in names
                joined .= (i = 1 ? "" : ",") n
            selectedFeatures := joined
            featuresLabel.Text := FormatFeatures(selectedFeatures)
            Settings["Features"] := selectedFeatures
            SaveSettings()
            BuildTrayMenu()
            cfg.Destroy()
            ForceTranslate()
        }

        saveBtn   := cfg.Add("Button", "xm y+16 w120 Default", "Save")
        cancelBtn := cfg.Add("Button", "x+10 w120", "Cancel")
        saveBtn.OnEvent("Click", SaveCfg)
        cancelBtn.OnEvent("Click", (*) => cfg.Destroy())
        cfg.OnEvent("Escape", (*) => cfg.Destroy())
        cfg.OnEvent("Close",  (*) => cfg.Destroy())
        cfg.Show()
    }

    inputEdit.OnEvent("Change", DebouncedTranslate)
    inputEdit.OnEvent("Change", UpdateCharCount)
    cfgBtn.OnEvent("Click", OpenFeatureConfig)
    ddModel.OnEvent("Change", DebouncedTranslate)

    rerunBtn.OnEvent("Click", ForceTranslate)
    copyBtn.OnEvent("Click", (*) => (
        A_Clipboard := resultEdit.Value,
        SetStatus("✓ Result copied to clipboard", "059669")
    ))
    UpdateWindow(newText, doAutoRun) {
        inputEdit.Value := newText
        snapshotEdit.Value := newText
        UpdateCharCount()
        SetStatus("● Ready", "059669")
        resultEdit.Value := ""
        g.Show()
        WinActivate("ahk_id " g.Hwnd)
        if (doAutoRun && Trim(newText) != "") {
            state.seq += 1
            DoTranslate(state.seq)
        }
    }

    DestroyWindow(*) {
        global ActiveTranslator
        ActiveTranslator := ""
        g.Destroy()
    }

    closeBtn.OnEvent("Click", DestroyWindow)
    g.OnEvent("Escape", DestroyWindow)
    g.OnEvent("Close",  DestroyWindow)

    ActiveTranslator := { gui: g, update: UpdateWindow }

    g.Show("AutoSize Center")

    if (autoRun && Trim(inputEdit.Value) != "") {
        state.seq += 1
        DoTranslate(state.seq)
    }
}

; --- Simple read-only viewer (dry-run / last result) ------------------------
ShowOutputViewer(title, text) {
    g := Gui("+Resize +AlwaysOnTop", title)
    g.SetFont("s10", "Consolas")
    g.MarginX := 10, g.MarginY := 10
    g.Add("Edit", "xm ym w760 h480 ReadOnly +Wrap", text)
    copyBtn  := g.Add("Button", "xm y+10 w160", "Copy to clipboard")
    closeBtn := g.Add("Button", "x+10  w120 Default", "Close")
    copyBtn.OnEvent("Click", (*) => (A_Clipboard := text, ToolTip("Copied ✓"), SetTimer(() => ToolTip(), -1200)))
    closeBtn.OnEvent("Click", (*) => g.Destroy())
    g.OnEvent("Escape", (*) => g.Destroy())
    g.OnEvent("Close",  (*) => g.Destroy())
    g.Show()
}

TrayTip("LangHelper", "Ready. Press Ctrl+C, Ctrl+C on any selection.", 0x1)
