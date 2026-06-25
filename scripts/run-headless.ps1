<#
.SYNOPSIS
    Runs a .scr script through accoreconsole.exe (headless AutoCAD / Civil 3D)
    and adjudicates the result by EVIDENCE, not just by exit code.

.DESCRIPTION
    Headless native crashes (0xC0000005) cannot be caught by managed code and may
    leave a misleadingly clean exit code. This harness therefore treats the
    presence of a crash marker in stdout as the source of truth: if the marker is
    absent, the run is a FATAL CRASH regardless of exit code.

    The harness:
      - auto-detects the newest installed accoreconsole.exe (override with -AcadVersion)
      - runs the supplied .scr (optionally opening a seed .dwg)
      - captures stdout + stderr to a log file
      - enforces a timeout (kills the process and reports a STALL on overrun)
      - scans stdout for the crash marker and for the "Unknown command" signature
      - returns a structured result object and a non-zero exit code on failure

.PARAMETER ScriptPath
    Path to the .scr script to execute. Required.

.PARAMETER DwgPath
    Optional seed DWG to open with /i. If omitted, accoreconsole starts on its
    default empty drawing.

.PARAMETER AcadVersion
    Release year to pin (e.g. 2026). If omitted, the newest installed version is used.

.PARAMETER AcadRoot
    Full path to accoreconsole.exe, bypassing auto-detection entirely.

.PARAMETER Marker
    The crash-marker string expected at the end of the script's output.
    Must match the (princ "...") emitted by the .scr. Default: AFTER-MARKER.

.PARAMETER TimeoutSec
    Seconds before the run is killed and reported as a STALL. Default: 180.

.PARAMETER LogPath
    Where to write the captured output. Default: alongside the .scr as <name>.log.

.EXAMPLE
    .\run-headless.ps1 -ScriptPath .\run_smoke.scr -DwgPath .\seed.dwg -Marker "AFTER-MYTEST-MARKER"

.OUTPUTS
    A PSCustomObject: Passed, Reason, ExitCode, MarkerSeen, DurationSec, LogPath.
    Exit code 0 = PASS, 1 = FAIL (crash / missing marker / unknown command),
    2 = STALL (timeout), 3 = setup error (engine or script not found).
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)] [string] $ScriptPath,
    [string] $DwgPath,
    [string] $AcadVersion,
    [string] $AcadRoot,
    [string] $Marker = "AFTER-MARKER",
    [int]    $TimeoutSec = 180,
    [string] $LogPath
)

$ErrorActionPreference = "Stop"

function Resolve-AccoreConsole {
    param([string] $Version, [string] $Explicit)

    if ($Explicit) {
        if (Test-Path -LiteralPath $Explicit) { return (Resolve-Path -LiteralPath $Explicit).Path }
        throw "accoreconsole.exe not found at -AcadRoot '$Explicit'."
    }

    $autodesk = Join-Path ${env:ProgramFiles} "Autodesk"
    if (-not (Test-Path -LiteralPath $autodesk)) {
        throw "Autodesk install root not found at '$autodesk'."
    }

    # Folders look like 'AutoCAD 2026'. Civil 3D installs inside the same folder.
    $candidates = Get-ChildItem -LiteralPath $autodesk -Directory -Filter "AutoCAD *" |
        ForEach-Object {
            $exe = Join-Path $_.FullName "accoreconsole.exe"
            if (Test-Path -LiteralPath $exe) {
                $year = 0
                if ($_.Name -match "(\d{4})") { $year = [int]$Matches[1] }
                [PSCustomObject]@{ Year = $year; Exe = $exe }
            }
        } | Where-Object { $_ }

    if (-not $candidates) {
        throw "No accoreconsole.exe found under '$autodesk'. Is AutoCAD/Civil 3D installed?"
    }

    if ($Version) {
        $pick = $candidates | Where-Object { $_.Year -eq [int]$Version } | Select-Object -First 1
        if (-not $pick) {
            $have = ($candidates.Year | Sort-Object -Unique) -join ", "
            throw "Requested version $Version not installed. Found: $have."
        }
        return $pick.Exe
    }

    return ($candidates | Sort-Object Year -Descending | Select-Object -First 1).Exe
}

function New-Result {
    param($Passed, $Reason, $ExitCode, $MarkerSeen, $DurationSec, $LogPath)
    [PSCustomObject]@{
        Passed      = $Passed
        Reason      = $Reason
        ExitCode    = $ExitCode
        MarkerSeen  = $MarkerSeen
        DurationSec = [math]::Round($DurationSec, 2)
        LogPath     = $LogPath
    }
}

# --- setup -----------------------------------------------------------------
if (-not (Test-Path -LiteralPath $ScriptPath)) {
    Write-Host "SETUP ERROR: script not found: $ScriptPath" -ForegroundColor Red
    exit 3
}
$ScriptPath = (Resolve-Path -LiteralPath $ScriptPath).Path

if ($DwgPath) {
    if (-not (Test-Path -LiteralPath $DwgPath)) {
        Write-Host "SETUP ERROR: DWG not found: $DwgPath" -ForegroundColor Red
        exit 3
    }
    $DwgPath = (Resolve-Path -LiteralPath $DwgPath).Path
}

try {
    $engine = Resolve-AccoreConsole -Version $AcadVersion -Explicit $AcadRoot
} catch {
    Write-Host "SETUP ERROR: $($_.Exception.Message)" -ForegroundColor Red
    exit 3
}

if (-not $LogPath) {
    $LogPath = [System.IO.Path]::ChangeExtension($ScriptPath, ".log")
}

Write-Host "Engine : $engine"
Write-Host "Script : $ScriptPath"
if ($DwgPath) { Write-Host "Seed   : $DwgPath" }
Write-Host "Marker : $Marker"
Write-Host "Timeout: ${TimeoutSec}s"
Write-Host ("-" * 60)

# --- run -------------------------------------------------------------------
$argList = @()
if ($DwgPath) { $argList += @("/i", "`"$DwgPath`"") }
$argList += @("/s", "`"$ScriptPath`"")

$stdoutFile = [System.IO.Path]::GetTempFileName()
$stderrFile = [System.IO.Path]::GetTempFileName()
$start = Get-Date

$proc = Start-Process -FilePath $engine -ArgumentList $argList -NoNewWindow -PassThru `
    -RedirectStandardOutput $stdoutFile -RedirectStandardError $stderrFile

$timedOut = $false
if (-not $proc.WaitForExit($TimeoutSec * 1000)) {
    $timedOut = $true
    try { $proc.Kill() } catch { }
    $proc.WaitForExit()
}
$duration = ((Get-Date) - $start).TotalSeconds
$exitCode = $proc.ExitCode

$stdout = if (Test-Path $stdoutFile) { Get-Content -LiteralPath $stdoutFile -Raw } else { "" }
$stderr = if (Test-Path $stderrFile) { Get-Content -LiteralPath $stderrFile -Raw } else { "" }
Set-Content -LiteralPath $LogPath -Value ($stdout + "`n" + $stderr) -Encoding UTF8
Remove-Item $stdoutFile, $stderrFile -ErrorAction SilentlyContinue

# --- adjudicate (evidence first) -------------------------------------------
$markerSeen = $stdout -match [regex]::Escape($Marker)

if ($timedOut) {
    $r = New-Result $false "STALL: exceeded ${TimeoutSec}s timeout and was killed." $exitCode $markerSeen $duration $LogPath
    Write-Host "RESULT : STALL (timeout)" -ForegroundColor Red
    $r | Format-List | Out-Host
    exit 2
}

# 'Unknown command' means the engine suppressed/rejected a command headlessly.
if ($stdout -match "Unknown command") {
    $r = New-Result $false "FAIL: engine reported 'Unknown command' (suppressed/unsupported headlessly). See pitfalls.md." $exitCode $markerSeen $duration $LogPath
    Write-Host "RESULT : FAIL (unknown command)" -ForegroundColor Red
    $r | Format-List | Out-Host
    exit 1
}

if (-not $markerSeen) {
    $r = New-Result $false "FAIL: crash marker '$Marker' absent -> fatal native crash (likely 0xC0000005). Exit code alone is NOT proof." $exitCode $markerSeen $duration $LogPath
    Write-Host "RESULT : FAIL (crash - marker missing)" -ForegroundColor Red
    $r | Format-List | Out-Host
    exit 1
}

$r = New-Result $true "PASS: ran to completion and emitted the crash marker." $exitCode $markerSeen $duration $LogPath
Write-Host "RESULT : PASS" -ForegroundColor Green
$r | Format-List | Out-Host
exit 0
