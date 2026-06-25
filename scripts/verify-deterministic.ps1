<#
.SYNOPSIS
    Proves that a headless operation is deterministic by running it twice and
    byte-comparing the produced output file (the scripted equivalent of `fc /b`).

.DESCRIPTION
    Determinism is a testable property, not a promise. This script runs a
    producing .scr through run-headless.ps1 twice, into two separate output
    paths, then compares the two outputs byte-for-byte via SHA-256.

    If the output legitimately embeds volatile fields (timestamps, run ids,
    absolute temp paths), supply -NormalizeRegex to mask them before comparison
    so the test stays strict about everything else rather than being weakened or
    skipped entirely.

    The producing .scr is responsible for writing to the path the harness will
    compare. Use the OutToken substitution so each of the two runs writes to a
    distinct file: put the literal token  __OUT__  wherever the output path
    appears in your .scr, and this script swaps in run-specific paths.

.PARAMETER ScriptPath
    The .scr that produces the output. Must contain the literal token __OUT__
    where its output path is written.

.PARAMETER OutA
    Output path for run A. Default: <script>.runA.out

.PARAMETER OutB
    Output path for run B. Default: <script>.runB.out

.PARAMETER Marker
    Crash marker passed through to run-headless.ps1. Default: AFTER-MARKER.

.PARAMETER AcadVersion
    Optional release year to pin, forwarded to run-headless.ps1.

.PARAMETER NormalizeRegex
    Optional regex; every match in BOTH outputs is replaced with a fixed token
    before comparison. Use for timestamps/ids that are expected to differ.

.EXAMPLE
    .\verify-deterministic.ps1 -ScriptPath .\export_snapshot.scr -Marker "AFTER-EXPORT"

.EXAMPLE
    .\verify-deterministic.ps1 -ScriptPath .\report.scr `
        -NormalizeRegex '"generatedAt"\s*:\s*"[^"]*"'

.OUTPUTS
    Exit 0 = deterministic (byte-identical after optional normalization),
    1 = NON-deterministic, 2 = a run failed, 3 = setup error.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)] [string] $ScriptPath,
    [string] $OutA,
    [string] $OutB,
    [string] $Marker = "AFTER-MARKER",
    [string] $AcadVersion,
    [string] $NormalizeRegex
)

$ErrorActionPreference = "Stop"
$harness = Join-Path $PSScriptRoot "run-headless.ps1"

if (-not (Test-Path -LiteralPath $harness)) {
    Write-Host "SETUP ERROR: run-headless.ps1 not found beside this script." -ForegroundColor Red
    exit 3
}
if (-not (Test-Path -LiteralPath $ScriptPath)) {
    Write-Host "SETUP ERROR: script not found: $ScriptPath" -ForegroundColor Red
    exit 3
}
$ScriptPath = (Resolve-Path -LiteralPath $ScriptPath).Path

$templateText = Get-Content -LiteralPath $ScriptPath -Raw
if ($templateText -notmatch "__OUT__") {
    Write-Host "SETUP ERROR: script does not contain the literal token __OUT__ where its output path should go." -ForegroundColor Red
    exit 3
}

if (-not $OutA) { $OutA = [System.IO.Path]::ChangeExtension($ScriptPath, ".runA.out") }
if (-not $OutB) { $OutB = [System.IO.Path]::ChangeExtension($ScriptPath, ".runB.out") }

function Invoke-Run {
    param([string] $OutPath, [string] $Tag)

    Remove-Item -LiteralPath $OutPath -ErrorAction SilentlyContinue
    # Materialize a run-specific .scr with __OUT__ substituted.
    $runScr = [System.IO.Path]::ChangeExtension($ScriptPath, ".$Tag.scr")
    # Forward slashes avoid AutoLISP backslash-escaping issues; .Replace is a
    # literal substitution (no regex/$-token surprises in either operand).
    $fwdSlash = ($OutPath -replace '\\', '/')
    $templateText.Replace("__OUT__", $fwdSlash) |
        Set-Content -LiteralPath $runScr -Encoding UTF8

    $fwd = @{ ScriptPath = $runScr; Marker = $Marker }
    if ($AcadVersion) { $fwd.AcadVersion = $AcadVersion }

    Write-Host "=== Run $Tag ===" -ForegroundColor Cyan
    & $harness @fwd | Out-Host
    $code = $LASTEXITCODE
    Remove-Item -LiteralPath $runScr -ErrorAction SilentlyContinue
    return $code
}

$codeA = Invoke-Run -OutPath $OutA -Tag "runA"
if ($codeA -ne 0) { Write-Host "Run A did not pass (exit $codeA); cannot judge determinism." -ForegroundColor Red; exit 2 }

$codeB = Invoke-Run -OutPath $OutB -Tag "runB"
if ($codeB -ne 0) { Write-Host "Run B did not pass (exit $codeB); cannot judge determinism." -ForegroundColor Red; exit 2 }

if (-not (Test-Path -LiteralPath $OutA) -or -not (Test-Path -LiteralPath $OutB)) {
    Write-Host "FAIL: one or both runs did not produce the expected output file." -ForegroundColor Red
    exit 2
}

function Get-CompareHash {
    param([string] $Path, [string] $Regex)
    if ($Regex) {
        # Text-mode comparison with volatile fields masked.
        $text = Get-Content -LiteralPath $Path -Raw
        $masked = [regex]::Replace($text, $Regex, "<<NORMALIZED>>")
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($masked)
        $sha = [System.Security.Cryptography.SHA256]::Create()
        return ([BitConverter]::ToString($sha.ComputeHash($bytes))) -replace '-', ''
    }
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}

$hashA = Get-CompareHash -Path $OutA -Regex $NormalizeRegex
$hashB = Get-CompareHash -Path $OutB -Regex $NormalizeRegex

Write-Host ("-" * 60)
Write-Host "Out A : $OutA"
Write-Host "Out B : $OutB"
if ($NormalizeRegex) { Write-Host "Normalized with regex: $NormalizeRegex" -ForegroundColor Yellow }
Write-Host "SHA-256 A: $hashA"
Write-Host "SHA-256 B: $hashB"

if ($hashA -eq $hashB) {
    Write-Host "RESULT : DETERMINISTIC (byte-identical)" -ForegroundColor Green
    exit 0
} else {
    Write-Host "RESULT : NON-DETERMINISTIC (outputs differ)" -ForegroundColor Red
    Write-Host "Tip: diff the two files to find the volatile field, then mask it with -NormalizeRegex if it is expected to vary." -ForegroundColor Yellow
    exit 1
}
