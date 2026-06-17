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
    [Parameter(Mandatory)][string]$InputFile,
    [Parameter(Mandatory)][string]$OutputFile,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$scriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$promptPath = Join-Path $scriptDir 'prompt.md'

if (-not (Test-Path -LiteralPath $promptPath)) { throw "prompt.md not found at $promptPath" }
if (-not (Test-Path -LiteralPath $InputFile))  { throw "Input file not found: $InputFile" }

# --- Load inputs ---------------------------------------------------------------
$utf8NoBom     = New-Object System.Text.UTF8Encoding $false
$clipboardText = [System.IO.File]::ReadAllText($InputFile, $utf8NoBom)
if ([string]::IsNullOrWhiteSpace($clipboardText)) { throw "Input is empty." }

$md = [System.IO.File]::ReadAllText($promptPath, $utf8NoBom) -replace "`r`n", "`n"

# --- Extract Core block --------------------------------------------------------
$coreMatch = [regex]::Match($md, '(?ms)##\s+Core[^\n]*\n+```[a-z]*\n(.*?)\n```')
if (-not $coreMatch.Success) { throw "Could not find Core block in prompt.md" }
$core = $coreMatch.Groups[1].Value

# --- Extract every [FEATURE: NAME] block --------------------------------------
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

# --- Resolve requested features -----------------------------------------------
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

# --- Inject clipboard + features into Core ------------------------------------
$marker = "<clipboard>`n{{PASTE_CLIPBOARD_HERE}}`n</clipboard>"
if (-not $core.Contains($marker)) {
    throw "Core block in prompt.md does not contain the expected clipboard marker."
}
$clipboardSection = "<clipboard>`n" + $clipboardText.TrimEnd() + "`n</clipboard>"
$replacement = if ($featureText) { "$featureText`n`n$clipboardSection" } else { $clipboardSection }
$finalPrompt = $core.Replace($marker, $replacement)

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
