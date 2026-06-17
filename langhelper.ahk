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
    global FeatureCatalog, ModelCatalog, Settings, LastResultPath

    g := Gui("+Resize", "LangHelper")
    g.SetFont("s10", "Segoe UI")
    g.MarginX := 12, g.MarginY := 12

    g.Add("Text", "xm", "Live input (type Chinese or English here):")
    inputEdit := g.Add("Edit", "xm y+4 w820 h100 +Wrap", sourceText)

    g.Add("Text", "xm y+10", "Clipboard snapshot:")
    g.Add("Edit", "xm y+4 w820 h70 ReadOnly +Wrap", sourceText)

    ; --- Feature configuration (opens separate window) -----------------------
    selectedFeatures := Settings["Features"]

    g.Add("Text", "xm y+12", "Features:")
    featuresLabel := g.Add("Text", "x+8 yp w640", FormatFeatures(selectedFeatures))
    cfgBtn := g.Add("Button", "xm y+6 w200", "⚙ Configure features…")

    g.Add("Text", "xm y+14 Section", "Model:")
    chooseIdx := 1
    Loop ModelCatalog.Length
        if (ModelCatalog[A_Index] = Settings["Model"]) {
            chooseIdx := A_Index
            break
        }
    ddModel := g.Add("DropDownList", "x+8 yp-3 w340 Choose" chooseIdx, ModelCatalog)

    statusText := g.Add("Text", "xm y+14 w820", "Ready.")
    g.Add("Text", "xm y+6", "Result (auto-copied to clipboard when done):")
    resultEdit := g.Add("Edit", "xm y+4 w820 h280 ReadOnly +Wrap")

    copyBtn  := g.Add("Button", "xm y+10 w160", "Copy result")
    rerunBtn := g.Add("Button", "x+10 w120",    "Re-translate")
    closeBtn := g.Add("Button", "x+10 w120 Default", "Close")

    state := { running: false, restartRequested: false, seq: 0 }

    GetSelected() {
        return selectedFeatures
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
            statusText.Value := "Input is empty."
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
        statusText.Value := "Translating with " modl " (" (feat = "" ? "default" : feat) ")…"
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
            statusText.Value := "Error — see Open log file in tray."
            resultEdit.Value := result.error
            return
        }
        if (result.output = "") {
            statusText.Value := "Empty response."
            return
        }
        resultEdit.Value := result.output
        A_Clipboard := result.output
        try FileDelete LastResultPath
        FileAppend(result.output, LastResultPath, "UTF-8")
        statusText.Value := "Done. Result copied to clipboard."
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
        cfg.SetFont("s10", "Segoe UI")
        cfg.MarginX := 12, cfg.MarginY := 12
        cfg.Add("Text", "xm", "Select features to apply (re-translates on save):")

        enabledNow := Map()
        for f in StrSplit(selectedFeatures, ",")
            if (Trim(f) != "")
                enabledNow[Trim(f)] := true

        cfgBoxes := Map()
        for i, item in FeatureCatalog {
            name := item[1], label := item[2]
            opts := (Mod(i, 2) = 1) ? "xm y+8 w360 v" name : "x+12 yp w360 v" name
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
    cfgBtn.OnEvent("Click", OpenFeatureConfig)
    ddModel.OnEvent("Change", DebouncedTranslate)

    rerunBtn.OnEvent("Click", ForceTranslate)
    copyBtn.OnEvent("Click", (*) => (
        A_Clipboard := resultEdit.Value,
        statusText.Value := "Result copied to clipboard ✓"
    ))
    closeBtn.OnEvent("Click", (*) => g.Destroy())
    g.OnEvent("Escape", (*) => g.Destroy())
    g.OnEvent("Close",  (*) => g.Destroy())

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
