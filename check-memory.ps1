# candidates: A tools\check-public-docs.ps1 (same family, but it scans wording, not links) | B lychee / mdlinkscheck (link-only, needs a new toolchain; node/npm absent here) | C write it myself (also needs line budgets + orphan memory files; no existing tool does both)
# check-memory.ps1 - read-only hygiene check for AGENTS.md and memory\INDEX.md.
#
# Checks:
#   1. line budgets (AGENTS <= -MaxAgentsLines, INDEX <= -MaxIndexLines)
#   2. every backticked path in AGENTS.md / INDEX.md resolves on disk
#   3. memory\*.md files that nothing references (orphans, warning only)
#   4. every tools\*.ps1 declares a "# candidates:" line (process gate)
#
# Exit code: 0 = no errors (warnings allowed), 1 = missing targets.
# With -Strict a warning also makes it exit 1, so it can gate a hook.
#
# Output is ASCII-only on purpose: this file stays safe to run from
# powershell.exe 5.1, which decodes non-ASCII source as GBK. The documents
# are read with explicit UTF8 encoding so Chinese paths still match.
param(
    [string]$Root,
    [int]$MaxAgentsLines = 120,
    [int]$MaxIndexLines = 40,
    [string]$AgentsFile = 'AGENTS.md',
    [string]$IndexFile = 'memory\INDEX.md',
    [string]$MemoryDir = 'memory',
    [string]$ToolsDir = 'tools',
    [switch]$Strict,
    [switch]$ShowOrphans
)
$ErrorActionPreference = 'Stop'

if (-not $Root) { $Root = Split-Path -Parent $PSScriptRoot }
$Root = (Resolve-Path -LiteralPath $Root).Path
$agentsPath = Join-Path $Root $AgentsFile
$indexPath = Join-Path $Root $IndexFile
$memDir = Join-Path $Root $MemoryDir

$errors = @()
$warns = @()

function Read-Utf8([string]$p) {
    if (-not (Test-Path -LiteralPath $p)) { return $null }
    return (Get-Content -LiteralPath $p -Raw -Encoding UTF8)
}

function Get-BacktickTokens([string]$text) {
    if (-not $text) { return @() }
    $out = @()
    foreach ($m in [regex]::Matches($text, '`([^`\r\n]+)`')) { $out += $m.Groups[1].Value.Trim() }
    return $out
}

function Test-Target([string]$token) {
    # returns $null when the token is not a path candidate, else $true/$false
    if ($token -match '[<>*]') { return $null }
    if ($token -match '^/') { return $null }                       # switches: /qn /S /VERYSILENT
    $isAbs = $token -match '^[A-Za-z]:[\\/]'
    $hasSep = $token -match '[\\/]'
    $hasExt = $token -match '\.(md|ps1|psm1|json|txt|exe|yaml|yml)$'
    if (-not $isAbs) {
        # bare names are only checked for documents; a bare "powershell.exe" is a
        # command name, not a path. Executables need a separator or a drive letter.
        $bareDoc = ($token -match '\.(md|ps1|psm1|json|txt|yaml|yml)$') -and (-not $hasSep) -and ($token -notmatch '^\.')
        if (-not ($hasSep -and $hasExt) -and -not $bareDoc) { return $null }
    }
    # known files that live in a repo, not in this workspace
    if ($token -match '^docs[\\/]') { return $null }

    $p = $token -replace '/', '\'
    $p = $p.TrimEnd('\')
    if ($p.StartsWith('.\')) { $p = $p.Substring(2) }

    $cands = @()
    if ($isAbs) {
        $cands += $p
    } else {
        $cands += (Join-Path $Root $p)
        foreach ($sub in @($MemoryDir, 'modes', $ToolsDir, 'projects')) {
            $cands += (Join-Path (Join-Path $Root $sub) $p)
        }
    }
    foreach ($c in $cands) { if (Test-Path -LiteralPath $c) { return $true } }
    return $false
}

Write-Output "[check-memory] root: $Root"

# ---- 1. sizes -------------------------------------------------------------
Write-Output '[1/4] line budgets'
$agentsText = Read-Utf8 $agentsPath
$indexText = Read-Utf8 $indexPath

if (-not $agentsText) { $errors += 'AGENTS.md not found'; Write-Output '  AGENTS.md  MISSING' }
else {
    # Not Get-Content: under powershell.exe 5.1 the default encoding mis-decodes
    # UTF-8 and reports 36 lines for a 110-line file. ReadAllLines is correct in both.
    $n = [IO.File]::ReadAllLines($agentsPath).Count
    if ($n -gt $MaxAgentsLines) { $warns += "AGENTS.md $n lines > $MaxAgentsLines"; $flag = 'OVER' } else { $flag = 'ok' }
    Write-Output ("  AGENTS.md  {0,4} lines  limit {1,4}  {2}" -f $n, $MaxAgentsLines, $flag)
}
if (-not $indexText) { $errors += 'memory\INDEX.md not found'; Write-Output '  INDEX.md   MISSING' }
else {
    $n = [IO.File]::ReadAllLines($indexPath).Count
    if ($n -gt $MaxIndexLines) { $warns += "INDEX.md $n lines > $MaxIndexLines"; $flag = 'OVER' } else { $flag = 'ok' }
    Write-Output ("  INDEX.md   {0,4} lines  limit {1,4}  {2}" -f $n, $MaxIndexLines, $flag)
}

# ---- 2. backticked paths --------------------------------------------------
Write-Output '[2/4] backticked targets'
$tokens = @(Get-BacktickTokens $agentsText) + @(Get-BacktickTokens $indexText)
$checked = 0
$missing = @()
foreach ($t in ($tokens | Sort-Object -Unique)) {
    $r = Test-Target $t
    if ($null -eq $r) { continue }
    $checked++
    if (-not $r) { $missing += $t }
}
foreach ($m in $missing) { $errors += "missing target: $m"; Write-Output "  MISSING  $m" }
Write-Output ("  checked {0} path-like tokens, {1} missing" -f $checked, $missing.Count)

# ---- 3. orphan memory files ----------------------------------------------
Write-Output '[3/4] unreferenced memory files'
$orphans = @()
if (Test-Path -LiteralPath $memDir) {
    $hay = "$agentsText`n$indexText"
    foreach ($f in (Get-ChildItem -LiteralPath $memDir -Filter '*.md' -File)) {
        if ($f.Name -match '^handoff-') { continue }   # dated snapshots are one-offs by design
        if ($hay -notmatch [regex]::Escape($f.Name)) { $orphans += $f.Name }
    }
}
if ($orphans.Count -eq 0) { Write-Output '  none' }
else {
    foreach ($o in $orphans) { $warns += "orphan: memory\$o"; Write-Output "  ORPHAN   memory\$o" }
    if (-not $ShowOrphans) { Write-Output '  (orphans are warnings; route them from INDEX.md or delete)' }
}

# ---- 4. tool header declarations ------------------------------------------
Write-Output '[4/4] tool header declarations'
$toolsDir = Join-Path $Root $ToolsDir
$noDecl = @()
if (Test-Path -LiteralPath $toolsDir) {
    foreach ($f in (Get-ChildItem -LiteralPath $toolsDir -Filter '*.ps1' -File)) {
        $head = ([IO.File]::ReadAllLines($f.FullName) | Select-Object -First 25) -join "`n"
        if ($head -notmatch '(?m)^#\s*candidates:') { $noDecl += $f.Name }
    }
}
if ($noDecl.Count -eq 0) { Write-Output '  all declared' }
else {
    foreach ($d in $noDecl) { $errors += "no candidates line: tools\$d"; Write-Output "  NO-DECL  tools\$d" }
}

# ---- summary --------------------------------------------------------------
Write-Output ''
if ($errors.Count -eq 0 -and $warns.Count -eq 0) {
    Write-Output '[check-memory] OK - no errors, no warnings'
    exit 0
}
if ($errors.Count -eq 0) {
    Write-Output ("[check-memory] OK - {0} warning(s)" -f $warns.Count)
    if ($Strict) { exit 1 }
    exit 0
}
Write-Output ("[check-memory] FAILED - {0} error(s), {1} warning(s)" -f $errors.Count, $warns.Count)
exit 1
