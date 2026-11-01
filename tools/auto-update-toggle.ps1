# =============================================================
#  Antigravity auto-update toggle (official setting, safe & reversible)
#
#  Antigravity ships a built-in setting "autoCheckForUpdates"
#  (see dist/services/settingsService.js in the official app.asar).
#  It is stored in %APPDATA%\Antigravity\app_storage.json.
#
#  When false, dist/updater.js calls stopAutoUpdateChecks() and the
#  client never contacts the update server again - so a full NSIS
#  update can never wipe app.asar (and the Chinese patch with it).
#
#  Usage:
#    powershell -NoProfile -ExecutionPolicy Bypass -File auto-update-toggle.ps1 -Value false
#    powershell -NoProfile -ExecutionPolicy Bypass -File auto-update-toggle.ps1 -Value true
#    powershell -NoProfile -ExecutionPolicy Bypass -File auto-update-toggle.ps1 -Show
# =============================================================

param(
    [string]$Value = "false",
    [switch]$Show
)

$ErrorActionPreference = "Stop"

function Fail($msg, $code) {
    Write-Host ""
    Write-Host "  [ERROR] $msg"
    Write-Host ""
    exit $code
}

$store = Join-Path $env:APPDATA "Antigravity\app_storage.json"

if (-not (Test-Path $store)) {
    Fail "settings file not found: $store  (launch Antigravity once first)" 1
}

# ---- 1. read current value ------------------------------------------
$raw  = [System.IO.File]::ReadAllText($store)
$obj  = $null
try { $obj = $raw | ConvertFrom-Json } catch { Fail "settings file is not valid JSON: $store" 3 }
if ($null -eq $obj) { $obj = New-Object PSObject }

$hasKey = $false
$curVal = "(not set, defaults to true)"
if ($obj.PSObject.Properties.Name -contains "autoCheckForUpdates") {
    $hasKey = $true
    $curVal = $obj.autoCheckForUpdates
}

if ($Show) {
    Write-Host ""
    Write-Host "  settings file : $store"
    Write-Host "  autoCheckForUpdates : $curVal"
    Write-Host ""
    exit 0
}

# ---- 2. refuse to edit while the app is running ----------------------
$running = Get-Process -Name "Antigravity" -ErrorAction SilentlyContinue
if ($running) {
    Fail "Antigravity is running. Quit it completely (including the tray icon) and retry." 2
}

# ---- 3. backup once --------------------------------------------------
$bak = "$store.bak"
if (-not (Test-Path $bak)) {
    Copy-Item -LiteralPath $store -Destination $bak -Force
    Write-Host "  Backup   : $bak"
} else {
    Write-Host "  Backup   : app_storage.json.bak already exists, kept as is"
}

# ---- 4. write the new value -----------------------------------------
if ($hasKey) {
    $obj.autoCheckForUpdates = $Value
} else {
    $obj | Add-Member -NotePropertyName "autoCheckForUpdates" -NotePropertyValue $Value
}

# ConvertTo-Json would default to depth 2; values here are flat strings,
# but keep a generous depth so nothing can be silently truncated.
$json = $obj | ConvertTo-Json -Depth 20

# The app parses this file with JSON.parse(fs.readFileSync(path, 'utf-8')).
# A UTF-8 BOM would make JSON.parse throw, so write without BOM.
$enc = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($store, $json, $enc)

# ---- 5. verify -------------------------------------------------------
$check = ([System.IO.File]::ReadAllText($store) | ConvertFrom-Json).autoCheckForUpdates
if ($check -ne $Value) {
    Fail "write finished but read-back returned '$check' - restore from $bak" 4
}

Write-Host "  Setting  : autoCheckForUpdates = $curVal  ->  $Value"
Write-Host ""
exit 0
