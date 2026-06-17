# LangHelper

A DeepL-style **Ctrl+C, Ctrl+C** clipboard translator for Windows, powered by a
modular [prompt.md](prompt.md) and GitHub's `gh models` CLI. One window lets you
configure features (Polish, Bilingual EN/zh-TW, Glossary, etc.) in a dedicated
Configure window and watch the translation update live as you change settings.

```
Ctrl+C, Ctrl+C
   │
   ▼
langhelper.ahk  ──reads clipboard──►  opens translator window
       │
       └── on feature/model change ──►  langhelper.ps1
                                          │  loads prompt.md
                                          │  injects [FEATURE: …] blocks
                                          │  injects <clipboard>…</clipboard>
                                          ▼
                                   gh models run <model>   (stdin pipe)
                                          │
                                          ▼
                                   stdout ──► result panel + clipboard
```

## Files

| File | Role |
|---|---|
| [prompt.md](prompt.md) | LLM prompt spec — Core block + every `[FEATURE: NAME]` block. Edit freely; the PS script re-reads it on every call. |
| [langhelper.ps1](langhelper.ps1) | Assembles the prompt and calls `gh models run` via a native PowerShell pipe (UTF-8 in/out, stderr captured). |
| [langhelper.ahk](langhelper.ahk) | AutoHotkey v2: double-Ctrl+C detector, tray menu, combined translator window with a separate Configure-features window and live re-translate on feature/model change. |
| `langhelper.ini` | Auto-created. Persists last-used features + model. |
| `langhelper.log` | Auto-created. Timestamped log of every trigger and backend call. |

## AutoHotkey 介紹

[AutoHotkey](https://www.autohotkey.com/)（簡稱 AHK）是一套 **Windows 專用的免費開源
自動化腳本語言**，最常被用來：

- **自訂熱鍵 / 快捷鍵**：把任意按鍵組合（例如 `Ctrl+C, Ctrl+C`）綁定到自己的動作。
- **文字代換與巨集**：自動展開縮寫、批次輸入、模擬鍵盤與滑鼠操作。
- **建立小型 GUI 工具**：用幾行腳本就能做出視窗、按鈕、下拉選單、系統匣（tray）圖示。
- **串接外部程式**：呼叫 PowerShell、CLI、其他執行檔，把結果接回腳本。

LangHelper 就是一個典型例子——用 AHK 監聽「連按兩次 `Ctrl+C`」，讀取剪貼簿，開出
翻譯視窗，再把文字交給 PowerShell 與 `gh models` 處理。

**版本注意**：本專案使用 **AutoHotkey v2**（語法與 v1 不相容）。v1 的直譯器無法解析
這個腳本，安裝時請務必選 v2.x：

```powershell
winget install AutoHotkey.AutoHotkey        # v2.x
```

幾個常見名詞：

| 名詞 | 說明 |
|---|---|
| `.ahk` | AutoHotkey 腳本檔，雙擊即可由 AHK 直譯器執行。 |
| Hotkey | 熱鍵，例如本專案的 `~^c::`（`^` = Ctrl、`~` = 不攔截原本的複製行為）。 |
| Tray icon | 系統匣圖示，右鍵可開啟選單（切換模型、開啟 log、重新載入腳本等）。 |
| `Gui()` | 建立視窗的物件，LangHelper 的翻譯視窗與設定視窗都由它產生。 |


## One-time setup

```powershell
winget install AutoHotkey.AutoHotkey        # v2.x
winget install GitHub.cli
gh auth login
gh extension install github/gh-models
```

Verify the AI side works on its own:

```powershell
"translate to english: 早安" | gh models run openai/gpt-4.1-mini
```

## Auto-start on login (recommended)

Drop a shortcut into the Startup folder so LangHelper comes up after every VM
reboot / user login:

```powershell
$wsh = New-Object -ComObject WScript.Shell
$lnk = $wsh.CreateShortcut("$([Environment]::GetFolderPath('Startup'))\LangHelper.lnk")
$lnk.TargetPath       = (Get-Command AutoHotkey64.exe).Source
$lnk.Arguments        = '"C:\path\to\LangHelper\langhelper.ahk"'
$lnk.WorkingDirectory = 'C:\path\to\LangHelper'
$lnk.IconLocation     = (Get-Command AutoHotkey64.exe).Source + ',0'
$lnk.Description      = 'LangHelper - Ctrl+C,Ctrl+C clipboard translator'
$lnk.Save()
```

To inspect / remove later: `explorer.exe shell:startup` and delete
`LangHelper.lnk`.

## Daily use

1. Launch [langhelper.ahk](langhelper.ahk) (auto-starts if you ran the snippet
   above). A green "H" appears in the system tray.
2. Select any text anywhere in Windows → press **Ctrl+C, Ctrl+C** (within
   ~400 ms).
3. The **translator window** opens:
   - **Source** panel shows the clipboard text (read-only).
   - **Features** summary shows the currently enabled features; click
     **⚙ Configure features…** to open the Configure window, tick/untick
     features, then **Save** to apply and re-translate.
   - **Model** dropdown — switch models on the fly.
   - **Result** panel updates live (~700 ms debounce after any change)
     and the result is auto-copied to the clipboard.
4. Paste with **Ctrl+V**. Or click **Copy result** to recopy.

## Features (defined in [prompt.md](prompt.md))

| Tag | What it does |
|---|---|
| `POLISH` | Adds `## Polished (English)` with a professional rewrite. |
| `BILINGUAL_EN_ZHTW` | Forces both `## English` and `## 繁體中文 (zh-TW)` sections. Combines with POLISH to also produce polished versions of each. |
| `GLOSSARY` | 3–8 key terms with usage notes. |
| `TONE_VARIANTS` | Formal / Friendly / Concise rewrites. |
| `REPLY` | Two reply drafts (short + detailed). |
| `SUMMARY` | TL;DR (+ key points if source is long). |
| `TECHNICAL` | Preserves code, identifiers, paths, error messages. |
| `BACK_TRANSLATE` | Back-translation sanity check + drift notes. |
| `ROMANIZE` | Pinyin / Romaji / Revised Romanization for CJK. |

## Recommended models

Translation/polish is short-input, low-reasoning — small modern models give the
best speed-per-quality. Avoid `o1*` / `o3*` / `o4*` / `deepseek-r1*` /
`*reasoning` models; they add silent "thinking" tokens for no gain.

| Pick | Model | When |
|---|---|---|
| 🥇 Default | `openai/gpt-4.1-mini` | Everyday driver — fast (1–2 s) + excellent CJK ↔ EN. |
| 🥈 Fastest | `openai/gpt-4.1-nano` | Sub-second on short text. Skip for nuanced/long input. |
| 🥉 Quality | `openai/gpt-4.1` | When mini result feels off (rare jargon, formal Chinese). |
| Alt | `mistral-ai/mistral-small-2503`, `meta/llama-3.3-70b-instruct` | Non-OpenAI alternates. |

Change anytime via tray → **Model ▸** or the dropdown in the translator window.

## Tray menu

- **Open translator window…** — opens the combined window using the current clipboard.
- **Model ▸** — quick model switcher (checked = current).
- **Open prompt.md** — opens the prompt in your default editor.
- **Show last result** — re-opens the previous translation in a viewer window.
- **Open log file** — opens `langhelper.log`.
- **Dry-run on clipboard (preview prompt)** — assembles the full prompt and
  shows it in a window *without* calling the model. Great when iterating on
  [prompt.md](prompt.md).
- **Reload script** — restart AHK without re-launching from Explorer.
- **Exit**.

## Smoke test (no API spend)

```powershell
"這個 bug 我看一下，應該是 race condition 造成的。" |
    Out-File -Encoding UTF8 -NoNewline "$env:TEMP\lh_in.txt"

powershell -NoProfile -ExecutionPolicy Bypass `
    -File .\langhelper.ps1 `
    -Features "POLISH,BILINGUAL_EN_ZHTW" `
    -InputFile  "$env:TEMP\lh_in.txt" `
    -OutputFile "$env:TEMP\lh_out.txt" `
    -DryRun

Get-Content "$env:TEMP\lh_out.txt" -Raw
```

You should see the Core block, both FEATURE blocks, and the clipboard text
wrapped in `<clipboard>…</clipboard>`.

Drop `-DryRun` to make the real API call.

## How features are wired

[langhelper.ahk](langhelper.ahk) has a `FeatureCatalog` mapping
`[FEATURE: NAME]` tags from [prompt.md](prompt.md) to checkbox labels. To add
a feature:

1. Add a new fenced block to [prompt.md](prompt.md) starting with
   `[FEATURE: MY_FEATURE]`.
2. Add `["MY_FEATURE", "My label"]` to `FeatureCatalog` in
   [langhelper.ahk](langhelper.ahk).
3. Tray → **Reload script**.

No changes to [langhelper.ps1](langhelper.ps1) needed — it discovers feature
blocks by scanning the markdown.

## Troubleshooting

| Symptom | Fix |
|---|---|
| `Error: Unexpected "{"` when launching | Make sure AHK **v2** is installed (`winget install AutoHotkey.AutoHotkey`). The v1 interpreter can't parse this script. |
| Model replies with a greeting like *"Hello! I'm here to help…"* instead of a translation | `gh models run` fell into interactive `>>>` mode. The script avoids this by piping via PowerShell's native `\|`. If you see it, confirm you're on the latest [langhelper.ps1](langhelper.ps1). |
| Bilingual selected but only English appears | Make sure [prompt.md](prompt.md) is the current version — the `BILINGUAL_EN_ZHTW` block explicitly demands both sections and overrides the Core "return only translated text" rule. |
| Ctrl+C, Ctrl+C does nothing, but tray → **Dry-run** works | Another app is eating the second Ctrl+C. Edit [langhelper.ahk](langhelper.ahk): change `~^c::` to e.g. `~^!c::` (Ctrl+Alt+C) and reload. |
| `gh: command not found` | `winget install GitHub.cli` and `gh auth login`. |
| `unknown command "models"` | `gh extension install github/gh-models`. |
| Empty / garbled CJK output | Confirm [prompt.md](prompt.md) is saved as UTF-8 (no BOM). |
| "Could not find Core block" | Don't rename the `## Core` heading or remove its fenced code block in [prompt.md](prompt.md). |
| Need to see what happened | Tray → **Open log file**. Every trigger, command line, exit code, and output length is logged. |

## Build history (what we did)

1. **Wrote modular [prompt.md](prompt.md)** — Core (translate to English) +
   `[FEATURE: …]` blocks for Polish, Bilingual EN/zh-TW, and 7 more optional
   features.
2. **Picked the stack** — AutoHotkey v2 (hotkey + GUI) + PowerShell
   (prompt assembly) + `gh models` CLI (AI, uses existing GitHub auth, no
   API keys to manage).
3. **Built [langhelper.ps1](langhelper.ps1)** — parses [prompt.md](prompt.md)
   via regex, injects clipboard text, pipes to `gh models run`. Has
   `-DryRun` for prompt inspection.
4. **Built [langhelper.ahk](langhelper.ahk)** — `~^c::` double-press
   detector, tray menu, feature picker GUI.
5. **Fixed AHK v2 parse error** — nested single-line `Name(*) { stmt }`
   doesn't parse; split into multi-line form.
6. **Fixed the "Hello!" greeting bug** — `gh models run` was entering
   interactive `>>>` mode because `cmd < file` and
   `Start-Process -RedirectStandardInput` don't give it a real pipe.
   Switched to PowerShell's native `$prompt | & gh models run $Model`,
   which works.
7. **Added visibility** — MsgBox errors, `langhelper.log`, tray
   *Show last result* / *Open log file* / *Reload script*.
8. **Strengthened `BILINGUAL_EN_ZHTW`** — explicitly overrides Core's
   "return only translated text" rule and demands both `## English` and
   `## 繁體中文 (zh-TW)` sections, so zh-TW is no longer skipped when the
   source is already English.
9. **Moved features into a Configure window** — the translator window now
   shows a read-only features summary plus a **⚙ Configure features…**
   button that opens a dedicated checkbox window; **Save** applies the
   selection, persists it, and re-translates.
9. **Combined picker + result into one live window** —
   `ShowTranslatorWindow`: source panel, 2-column feature checkboxes,
   model dropdown, status line, result panel, Copy/Re-translate/Close.
   Any toggle or model change triggers a 700 ms debounced re-translate;
   result panel and clipboard update in place.
10. **Refreshed `ModelCatalog`** — `openai/gpt-4.1-mini` as default, with
    nano / 4.1 / 4o-mini / 5-mini / Mistral Small / Llama 3.3 70B as
    alternates.
11. **Auto-start on login** — Startup-folder shortcut via the PowerShell
    snippet above.
