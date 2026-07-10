#requires -Version 5.1
<#
.SYNOPSIS
    LangHelper backend: assembles the prompt from prompt.md and calls `gh models run`.

.DESCRIPTION
    Reads prompt.md from the script directory, extracts the Core block and any
    requested [FEATURE: ...] blocks, injects the clipboard text, then pipes the
    assembled prompt to `gh models run <model>` and writes the response.

.PARAMETER Features
    Comma-separated feature names to enable (e.g. "POLISH,BILINGUAL_EN_ZHTW").
    Empty string means Core-only (translate to English).

.PARAMETER Model
    Model id passed to `gh models run`. Default: openai/gpt-4.1-mini.

.PARAMETER PromptFile
    Optional path to an external prompt/spec file. If supplied and it exists,
    it is used instead of the bundled prompt.md. Two formats are supported:
      * Modular   - a file with a "## Core" block and [FEATURE: ...] blocks
                    (like prompt.md). Features are assembled as usual.
      * Raw/skill - any other markdown file (e.g. a SKILL.md / TeamsPrompt.md
                    spec). The whole file is used verbatim as the instruction;
                    YAML frontmatter is stripped, a sibling
                    references/internal-context.md is auto-appended when present,
                    and the clipboard text is added inside
                    <clipboard>...</clipboard> at the end. -Features is ignored.

.PARAMETER InputFile
    UTF-8 file containing the clipboard text to translate.

.PARAMETER OutputFile
    UTF-8 file to write the model response into.

.PARAMETER DryRun
    If set, writes the assembled prompt to OutputFile WITHOUT calling gh.
    Useful for verifying prompt assembly without spending API quota.
#>
[CmdletBinding()]
param(
    [string]$Features = "",
    [string]$Model = "openai/gpt-4.1-mini",
    [string]$PromptFile = "",
    [Parameter(Mandatory)][string]$InputFile,
    [Parameter(Mandatory)][string]$OutputFile,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$scriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path

# Use the external prompt file when provided and present; otherwise the bundled one.
if ($PromptFile -and (Test-Path -LiteralPath $PromptFile)) {
    $promptPath = (Resolve-Path -LiteralPath $PromptFile).Path
} else {
    $promptPath = Join-Path $scriptDir 'prompt.md'
}

if (-not (Test-Path -LiteralPath $promptPath)) { throw "Prompt file not found at $promptPath" }
if (-not (Test-Path -LiteralPath $InputFile))  { throw "Input file not found: $InputFile" }

# --- Load inputs ---------------------------------------------------------------
$utf8NoBom     = New-Object System.Text.UTF8Encoding $false
$clipboardText = [System.IO.File]::ReadAllText($InputFile, $utf8NoBom)
if ([string]::IsNullOrWhiteSpace($clipboardText)) { throw "Input is empty." }

$md = [System.IO.File]::ReadAllText($promptPath, $utf8NoBom) -replace "`r`n", "`n"

$marker = "<clipboard>`n{{PASTE_CLIPBOARD_HERE}}`n</clipboard>"
$clipboardSection = "<clipboard>`n" + $clipboardText.TrimEnd() + "`n</clipboard>"

# Decide which assembly mode to use: modular (prompt.md style) vs raw (skill spec).
$coreMatch = [regex]::Match($md, '(?ms)##\s+Core[^\n]*\n+```[a-z]*\n(.*?)\n```')
$isModular = $coreMatch.Success -and $coreMatch.Groups[1].Value.Contains($marker)

if ($isModular) {
    # --- Modular mode: Core block + selected [FEATURE: NAME] blocks ------------
    $core = $coreMatch.Groups[1].Value

    $featureBlocks = @{}
    $featureMatches = [regex]::Matches(
        $md,
        '(?ms)```[a-z]*\n(\[FEATURE:\s*([A-Z0-9_]+)[^\]]*\][^\n]*\n.*?)\n```'
    )
    foreach ($m in $featureMatches) {
        $name = $m.Groups[2].Value
        $body = $m.Groups[1].Value
        $featureBlocks[$name] = $body
    }

    $selected = @()
    if ($Features) {
        $selected = $Features.Split(',') |
            ForEach-Object { $_.Trim() } |
            Where-Object   { $_ }
    }

    $featureChunks = New-Object System.Collections.Generic.List[string]
    $missing       = New-Object System.Collections.Generic.List[string]
    foreach ($name in $selected) {
        if ($featureBlocks.ContainsKey($name)) {
            $featureChunks.Add($featureBlocks[$name])
        } else {
            $missing.Add($name)
        }
    }
    if ($missing.Count -gt 0) {
        Write-Warning ("Unknown feature(s) ignored: " + ($missing -join ', '))
    }
    $featureText = [string]::Join("`n`n", $featureChunks)

    $replacement = if ($featureText) { "$featureText`n`n$clipboardSection" } else { $clipboardSection }
    $finalPrompt = $core.Replace($marker, $replacement)

    # Some chat-tuned models (e.g. gpt-5-chat) ignore the feature blocks for short
    # input and answer with a single line. Append an explicit reminder listing the
    # exact "## ..." sections the enabled features require, after the clipboard,
    # where models weight instructions most heavily.
    if ($featureText) {
        $headings = [regex]::Matches($featureText, '##[ \t]+[^\r\n]+') |
            ForEach-Object { $_.Value.Trim() } |
            Select-Object -Unique
        if ($headings) {
            $headingList = $headings -join ', '
            $finalPrompt = $finalPrompt.TrimEnd() +
                "`n`nREMINDER: Even if the clipboard text above is short, you MUST still output every required section, in order: $headingList. Do not answer with a single line, and do not skip or merge any section."
        }
    }
}
else {
    # --- Raw/skill mode: use the whole file verbatim as the instruction -------
    # Strip a leading YAML frontmatter block (--- ... ---) if present.
    $body = [regex]::Replace($md, '(?s)\A\s*---\s*\n.*?\n---\s*\n', '')

    # Auto-append a sibling references/internal-context.md when it exists, so the
    # model gets the domain context the spec refers to.
    $refPath = Join-Path (Split-Path -Parent $promptPath) 'references\internal-context.md'
    if (Test-Path -LiteralPath $refPath) {
        $ref = [System.IO.File]::ReadAllText($refPath, $utf8NoBom) -replace "`r`n", "`n"
        $body = $body.TrimEnd() + "`n`n---`n`n# Reference: internal-context.md`n`n" + $ref.Trim()
    }

    $finalPrompt = $body.TrimEnd() + "`n`n" + $clipboardSection + "`n`n" +
        "The text inside <clipboard>...</clipboard> above is the input to process. Apply the skill/instructions above to THAT text now and output the result in the required format. Do not greet, do not ask for more input, and do not explain what you are about to do."
}

# --- Dry-run shortcut ----------------------------------------------------------
if ($DryRun) {
    [System.IO.File]::WriteAllText($OutputFile, $finalPrompt, $utf8NoBom)
    Write-Host "DryRun: assembled prompt written to $OutputFile"
    exit 0
}

# --- Call gh models run --------------------------------------------------------
if (-not (Get-Command 'gh' -ErrorAction SilentlyContinue)) {
    throw "'gh' CLI not found. Install GitHub CLI and run: gh extension install github/gh-models"
}

# Preflight so new machines fail with an actionable message instead of a native
# pipeline error when the gh-models extension is missing.
$tmpHelpErr = [System.IO.Path]::GetTempFileName()
try {
    & gh help models *> $null 2> $tmpHelpErr
    $helpExit = $LASTEXITCODE
    if ($helpExit -ne 0) {
        $helpErrText = ''
        if (Test-Path -LiteralPath $tmpHelpErr) {
            $helpErrText = [System.IO.File]::ReadAllText($tmpHelpErr, $utf8NoBom)
        }
        if ($helpErrText -match 'unknown command\s+"models"') {
            throw @"
'gh models' is not available in your current gh installation.

Fix:
1) gh auth login
2) gh extension install github/gh-models
3) (if already installed) gh extension upgrade github/gh-models
4) Retry LangHelper.
"@
        }

        throw "Unable to run 'gh help models' (exit $helpExit): $helpErrText"
    }
}
finally {
    if (Test-Path -LiteralPath $tmpHelpErr) {
        Remove-Item -LiteralPath $tmpHelpErr -Force -ErrorAction SilentlyContinue
    }
}

# Force UTF-8 on the PowerShell pipeline so CJK survives the trip to gh.
$prevInEnc  = [Console]::InputEncoding
$prevOutEnc = [Console]::OutputEncoding
$prevOFS    = $OutputEncoding
[Console]::InputEncoding  = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding           = [System.Text.Encoding]::UTF8

$tmpErr = [System.IO.Path]::GetTempFileName()
try {
    # PowerShell's native pipe gives gh a real stdin pipe (non-TTY), so it runs
    # one-shot instead of dropping into the >>> interactive REPL.
    $response = $finalPrompt | & gh models run $Model 2> $tmpErr
    $exit = $LASTEXITCODE

    if ($exit -ne 0) {
        $errText = ''
        if (Test-Path -LiteralPath $tmpErr) {
            $errText = [System.IO.File]::ReadAllText($tmpErr, $utf8NoBom)
        }
        throw "gh models run failed (exit $exit): $errText"
    }

    # $response may be a string[] when gh emits multiple lines; join them back.
    if ($response -is [System.Array]) {
        $response = [string]::Join("`n", $response)
    }
    [System.IO.File]::WriteAllText($OutputFile, [string]$response, $utf8NoBom)
}
finally {
    if (Test-Path -LiteralPath $tmpErr) {
        Remove-Item -LiteralPath $tmpErr -Force -ErrorAction SilentlyContinue
    }
    [Console]::InputEncoding  = $prevInEnc
    [Console]::OutputEncoding = $prevOutEnc
    $OutputEncoding           = $prevOFS
}
