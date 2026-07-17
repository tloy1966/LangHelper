# LangHelper

A DeepL-style **Ctrl+C, Ctrl+C** clipboard translator for Windows, powered by a
modular [prompt.md](prompt.md) and GitHub's `gh models` CLI. One window lets you
configure features (Polish, Bilingual EN/zh-TW, Glossary, etc.) in a dedicated
Configure window and watch the translation update live as you change settings.

## Install a release

1. Download `LangHelper-vX.Y.Z-windows-x64.zip` from the GitHub **Releases** page.
2. Optionally verify it against the accompanying `.zip.sha256` file.
3. Extract the entire archive to a writable folder. Keep `LangHelper.exe`, the
   PowerShell scripts, and [prompt.md](prompt.md) together.
4. Install GitHub CLI and SQLite, then authenticate and add GitHub Models:

   ```powershell
   winget install GitHub.cli SQLite.SQLite
   gh auth login
   gh extension install github/gh-models
   ```

5. Run `LangHelper.exe`. The compiled release does not require a separate
   AutoHotkey installation.

Windows may show a SmartScreen warning because releases are not code-signed.
Verify the SHA-256 checksum before choosing **Run anyway**.

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
| [langhelper-history.ps1](langhelper-history.ps1) | Stores and searches completed translations in a local SQLite database. |
| [langhelper.ahk](langhelper.ahk) | AutoHotkey v2: double-Ctrl+C detector, tray menu, combined translator window with a separate Configure-features window and live re-translate on feature/model change. |
| `langhelper.ini` | Auto-created. Persists settings (features, model, and the options in [Settings](#settings-langhelperini)). |
| `langhelper_history.sqlite` | Auto-created. Local searchable history database. |
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


## 從 0 開始設定 (Fresh setup)

Run these steps once on a new Windows machine / VM. Open **PowerShell** from the
project folder first:

```powershell
cd C:\path\to\LangHelper
```

### 1. Install required tools

LangHelper needs three command-line/runtime dependencies:

| Tool | Why LangHelper needs it | Install |
|---|---|---|
| AutoHotkey v2 | Runs [langhelper.ahk](langhelper.ahk), listens for `Ctrl+C, Ctrl+C`, and shows the GUI. | `winget install AutoHotkey.AutoHotkey` |
| GitHub CLI | Provides `gh auth` and `gh models run` for translation. | `winget install GitHub.cli` |
| SQLite CLI (`sqlite3.exe`) | Stores and searches local translation history in `langhelper_history.sqlite`. | `winget install SQLite.SQLite` |

Install all three:

```powershell
winget install AutoHotkey.AutoHotkey
winget install GitHub.cli
winget install SQLite.SQLite
```

Close and reopen PowerShell after installation so `AutoHotkey64.exe`, `gh`, and
`sqlite3` are available on `PATH`.

### 2. Verify SQLite is installed

History search depends on the SQLite command-line tool, not only the database
file. Confirm this command works:

```powershell
sqlite3 --version
```

If PowerShell says `sqlite3` is not recognized, reinstall it and reopen
PowerShell:

```powershell
winget install SQLite.SQLite
```

This is the same dependency checked by [langhelper-history.ps1](langhelper-history.ps1);
without it, history insert/search will fail with `sqlite3.exe not found`.

### 3. Sign in to GitHub Models

```powershell
gh auth login
gh extension install github/gh-models
```

Verify the AI side works on its own:

```powershell
"translate to english: 早安" | gh models run openai/gpt-4.1-mini
```

### 4. Launch LangHelper

Double-click [langhelper.ahk](langhelper.ahk), or run:

```powershell
AutoHotkey64.exe .\langhelper.ahk
```

A green "H" should appear in the Windows system tray. Select text anywhere,
press **Ctrl+C, Ctrl+C**, and the translator window should open.

## Auto-start on login

Right-click the LangHelper tray icon and select **Start with Windows**. A check
mark means LangHelper will launch automatically after the current user signs in,
including after a reboot. Select it again to disable automatic startup.

The toggle manages `LangHelper.lnk` in the current user's Windows Startup
folder. To inspect it directly, run `explorer.exe shell:startup`.

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
   - Every successful result is recorded in `langhelper_history.sqlite`.
4. Paste with **Ctrl+V**. Or click **Copy result** to recopy.
5. Tray → **Search history...** to find previous source/result text, copy a
   result, inspect the full item, or re-run the original source text.

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

> **Note — external prompt files disable features.** If `langhelper.ini` sets a
> `PromptFile=` that points to an existing file (e.g. a `SKILL.md` /
> `TeamsPrompt.md`), LangHelper runs in **raw/skill mode**: the whole file is
> used verbatim and the **Features selection is ignored** by the backend. In
> that mode the translator window greys out the **Configure features…** button
> and labels the summary as *"Ignored — external prompt file in use"*. Clear
> `PromptFile=` in the ini (and Reload) to return to the modular [prompt.md](prompt.md)
> where the feature checkboxes take effect.

## Settings (`langhelper.ini`)

`langhelper.ini` is auto-created under `[LangHelper]` and updated whenever you
change options in the translator window. Edit it by hand if you prefer, then
tray → **Reload script** to apply.

| Key | Values | Default | What it does |
|---|---|---|---|
| `Features` | comma-separated tags | `POLISH` | Enabled feature blocks (modular [prompt.md](prompt.md) mode only). |
| `Model` | `gh models` id | `openai/gpt-4.1-mini` | Model passed to `gh models run`. |
| `PromptFile` | file path or empty | *(empty)* | Points to an external prompt/spec (e.g. a `SKILL.md` / `TeamsPrompt.md`). When set and the file exists, LangHelper runs in raw/skill mode and **ignores `Features`**. Empty = bundled [prompt.md](prompt.md). |
| `AutoTranslate` | `0` / `1` | `0` | Toggles the previously always-on live translation. `1` = re-translate automatically while you type (debounced ~700 ms). `0` = only translate on trigger (Ctrl+C, Ctrl+C) or **Re-translate**. Mirrors the **Auto-translate while typing** checkbox. |
| `SingleWindow` | `0` / `1` | `1` | `1` = reuse one translator window (each trigger updates it in place). `0` = open a new window per trigger. Mirrors the **Single window (reuse)** checkbox. |



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
- **Start with Windows** — enable or disable launching LangHelper automatically
   when the current user signs in.
- **Open prompt.md** — opens the prompt in your default editor.
- **Show last result** — re-opens the previous translation in a viewer window.
- **Search history...** — opens a SQLite-backed searchable history of completed
   translations. Double-click a row to inspect it, copy the result, or re-run the
   original source text.
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
9. **Combined picker + result into one live window** —
   `ShowTranslatorWindow`: source panel, feature checkboxes,
   model dropdown, status line, result panel, Copy/Re-translate/Close.
   Any toggle or model change triggers a 700 ms debounced re-translate;
   result panel and clipboard update in place.
10. **Refreshed `ModelCatalog`** — `openai/gpt-4.1-mini` as default, with
    nano / 4.1 / 4o-mini / 5-mini / Mistral Small / Llama 3.3 70B as
    alternates.
11. **Auto-start on login** — Startup-folder shortcut via the PowerShell
    snippet above.
12. **Moved features into a Configure window** — the translator window now
    shows a read-only features summary plus a **⚙ Configure features…**
    button that opens a dedicated checkbox window; **Save** applies the
    selection, persists it, and re-translates.

## Publishing a release (maintainers)

Pull requests and pushes to `main` run the CI workflow, which validates
PowerShell syntax, prompt assembly, and synchronization between prompt feature
blocks and the AutoHotkey feature catalog.

To publish, create and push a semantic-version tag from a tested `main` commit:

```powershell
git switch main
git pull --ff-only
git tag -a v1.0.0 -m "LangHelper v1.0.0"
git push origin v1.0.0
```

The release workflow validates the tag, compiles the AutoHotkey v2 application,
packages the executable with its required companion files, generates a SHA-256
checksum, and creates GitHub release notes. Pre-release tags such as
`v1.1.0-beta.1` are automatically marked as GitHub pre-releases.
