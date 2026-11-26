$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$srcDf = Join-Path $root 'hack\hack.df'

function Test-Dir([string]$path) {
    if ([string]::IsNullOrWhiteSpace($path)) { return $false }
    try { return [System.IO.Directory]::Exists($path) } catch { return $false }
}

function Add-Candidate($list, [string]$path) {
    if (-not (Test-Dir $path)) { return }
    foreach ($c in $list) { if ($c -eq $path) { return } }
    [void]$list.Add($path)
}

function Get-SteamRoots {
    $roots = New-Object System.Collections.ArrayList
    $steam = $null
    try { $steam = (Get-ItemProperty 'HKCU:\Software\Valve\Steam' -ErrorAction Stop).SteamPath } catch { }
    if (-not $steam) {
        try { $steam = (Get-ItemProperty 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam' -ErrorAction Stop).InstallPath } catch { }
    }
    if ($steam) { Add-Candidate $roots (($steam -replace '/', '\').TrimEnd('\')) }

    # Fall back to the usual default install locations.
    foreach ($p in @(
        'C:\Program Files (x86)\Steam',
        'C:\Program Files\Steam',
        'D:\Program Files (x86)\Steam',
        'D:\Steam'
    )) { Add-Candidate $roots $p }
    return $roots
}

function Find-Game {
    $candidates = New-Object System.Collections.ArrayList
    $roots = Get-SteamRoots

    # 1) default library inside every known Steam root (always tried first)
    foreach ($r in $roots) {
        Add-Candidate $candidates (Join-Path $r 'steamapps\common\DeathRoadToCanada')
    }

    # 2) extra libraries from libraryfolders.vdf, validated one by one
    foreach ($r in $roots) {
        $lf = Join-Path $r 'steamapps\libraryfolders.vdf'
        if (-not (Test-Path -LiteralPath $lf)) { continue }
        try { $raw = Get-Content -LiteralPath $lf -Raw -ErrorAction Stop } catch { continue }
        foreach ($m in [regex]::Matches($raw, '"path"\s*"([^"]+)"')) {
            $lib = $m.Groups[1].Value -replace '\\\\', '\' -replace '/', '\'
            # Check the drive / folder before building any path, so a stale
            # entry such as E:\ on a machine without E: is simply skipped.
            if (-not (Test-Dir $lib)) { continue }
            Add-Candidate $candidates ([System.IO.Path]::Combine($lib, 'steamapps\common\DeathRoadToCanada'))
        }
    }

    # 3) last-resort custom library guesses
    foreach ($p in @(
        'E:\SteamLibrary\steamapps\common\DeathRoadToCanada',
        'D:\SteamLibrary\steamapps\common\DeathRoadToCanada'
    )) { Add-Candidate $candidates $p }

    foreach ($c in $candidates) {
        if (Test-Path -LiteralPath (Join-Path $c 'deathforth\boot.df')) { return $c }
    }
    return $null
}

Write-Host ''
Write-Host '=== DR2C Cheat Installer ===' -ForegroundColor Cyan

if (-not (Test-Path $srcDf)) { Write-Host "ERROR: missing $srcDf" -ForegroundColor Red; exit 1 }

$game = Find-Game
if (-not $game) {
    Write-Host 'ERROR: Death Road to Canada not found.' -ForegroundColor Red
    Write-Host 'Open tools\install.ps1 and add your Steam folder to Get-SteamRoots.'
    exit 1
}
Write-Host "Game folder: $game"

# 1) back up the save folder
$saveDir = Join-Path $env:APPDATA '.madgarden\DR2C'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backup = Join-Path $root "backup\install-$stamp"
if (Test-Path $saveDir) {
    $saveItems = @(Get-ChildItem $saveDir -Force -ErrorAction SilentlyContinue)
    if ($saveItems.Count -gt 0) {
        New-Item -ItemType Directory -Force -Path $backup | Out-Null
        Copy-Item (Join-Path $saveDir '*') $backup -Recurse -Force
        Write-Host "Saves backed up: $backup"
    } else {
        Write-Host 'Save folder is empty - skipping backup.'
    }
} else {
    Write-Host 'No save folder yet (game never started) - skipping backup.'
}

# 2) install the mod file
$hackDir = Join-Path $game 'deathforth\hack'
New-Item -ItemType Directory -Force -Path $hackDir | Out-Null
$dst = Join-Path $hackDir 'hack.df'
Copy-Item $srcDf $dst -Force

# 3) the game parser rejects a UTF-8 BOM as an unknown word - guard against it
$bytes = [System.IO.File]::ReadAllBytes($dst)
if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
    $text = [System.IO.File]::ReadAllText($dst)
    [System.IO.File]::WriteAllText($dst, $text, (New-Object System.Text.UTF8Encoding($false)))
    Write-Host 'Removed UTF-8 BOM from hack.df.' -ForegroundColor Yellow
}

Write-Host ''
Write-Host 'Installed:' -ForegroundColor Green
Write-Host "  $dst"
Write-Host ''
Write-Host 'Next steps:'
Write-Host '  1. Start the game (through Steam), wait for the main menu.'
Write-Host '  2. Double-click "Start Panel.bat" (启动面板.bat).'
Write-Host '  3. Tick the boxes you want.'
Write-Host ''
Write-Host 'Hotkeys also work without the panel: Ctrl+1..6, Ctrl+0 = all.'
Write-Host ''

