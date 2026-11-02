#requires -version 5.1
# candidates: (legacy, not recorded)
<#
  DeepSeek API peak/off-peak indicator (Asia/Shanghai).

  Peak: Mon-Fri 09:00-12:00 and 14:00-18:00 CST, except Chinese public holidays.
  Off-peak price is half of peak. Source: api-docs.deepseek.com/quick_start/pricing

  Usage:
    powershell -NoProfile -File tools\ds-peak.ps1
    powershell -NoProfile -File tools\ds-peak.ps1 -Json
    powershell -NoProfile -File tools\ds-peak.ps1 -Watch

  Holidays: one yyyy-MM-dd per line in tools\ds-peak-holidays.txt (optional).
#>
[CmdletBinding()]
param(
    [switch]$Json,
    [switch]$Watch,
    [string]$HolidaysFile = ''
)

$ErrorActionPreference = 'Stop'
if (-not $HolidaysFile) { $HolidaysFile = Join-Path $PSScriptRoot 'ds-peak-holidays.txt' }

function Get-HolidaySet {
    param([string]$Path)
    $set = @{}
    if (Test-Path -LiteralPath $Path) {
        foreach ($line in Get-Content -LiteralPath $Path -ErrorAction SilentlyContinue) {
            $s = $line.Trim()
            if ($s -and -not $s.StartsWith('#')) { $set[$s] = $true }
        }
    }
    return $set
}

$holidays = Get-HolidaySet -Path $HolidaysFile

function Test-Peak {
    param([datetime]$Now)
    if ($Now.DayOfWeek -eq [DayOfWeek]::Saturday -or $Now.DayOfWeek -eq [DayOfWeek]::Sunday) { return $false }
    if ($holidays.ContainsKey($Now.ToString('yyyy-MM-dd'))) { return $false }
    $h = $Now.Hour
    return (($h -ge 9 -and $h -lt 12) -or ($h -ge 14 -and $h -lt 18))
}

function Get-NextChange {
    param([datetime]$Now, [bool]$IsPeak)
    if ($IsPeak) {
        if ($Now.Hour -lt 12) { return $Now.Date.AddHours(12) }
        return $Now.Date.AddHours(18)
    }
    for ($i = 0; $i -lt 10; $i++) {
        $day = $Now.Date.AddDays($i)
        if ($day.DayOfWeek -eq [DayOfWeek]::Saturday -or $day.DayOfWeek -eq [DayOfWeek]::Sunday) { continue }
        if ($holidays.ContainsKey($day.ToString('yyyy-MM-dd'))) { continue }
        foreach ($hh in 9, 14) {
            $cand = $day.AddHours($hh)
            if ($cand -gt $Now) { return $cand }
        }
    }
    return $Now.AddDays(1)
}

function Write-State {
    $now = Get-Date
    $peak = Test-Peak -Now $now
    $next = Get-NextChange -Now $now -IsPeak $peak
    if ($Json) {
        [pscustomobject]@{
            now        = $now.ToString('yyyy-MM-dd HH:mm:ss')
            state      = $(if ($peak) { 'peak' } else { 'off-peak' })
            multiplier = $(if ($peak) { 2 } else { 1 })
            next_state = $(if ($peak) { 'off-peak' } else { 'peak' })
            next_at    = $next.ToString('yyyy-MM-dd HH:mm:ss')
        } | ConvertTo-Json -Compress
        return
    }
    $state = $(if ($peak) { 'PEAK    ' } else { 'OFF-PEAK' })
    $nextState = $(if ($peak) { 'off-peak' } else { 'peak' })
    $span = $next - $now
    $left = '{0}h{1:00}m' -f [int]$span.TotalHours, $span.Minutes
    '{0}  {1}  x{2}  next {3} at {4} (in {5})' -f $state, $now.ToString('yyyy-MM-dd HH:mm ddd'), $(if ($peak) { 2 } else { 1 }), $nextState, $next.ToString('yyyy-MM-dd HH:mm'), $left
}

if ($Watch) {
    $last = ''
    while ($true) {
        $line = Write-State
        if ($line -ne $last) { $line; $last = $line }
        Start-Sleep -Seconds 30
    }
}
else {
    Write-State
}
