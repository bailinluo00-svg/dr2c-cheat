$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot

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

    foreach ($r in $roots) {
        Add-Candidate $candidates (Join-Path $r 'steamapps\common\DeathRoadToCanada')
    }

    foreach ($r in $roots) {
        $lf = Join-Path $r 'steamapps\libraryfolders.vdf'
        if (-not (Test-Path -LiteralPath $lf)) { continue }
        try { $raw = Get-Content -LiteralPath $lf -Raw -ErrorAction Stop } catch { continue }
        foreach ($m in [regex]::Matches($raw, '"path"\s*"([^"]+)"')) {
            $lib = $m.Groups[1].Value -replace '\\\\', '\' -replace '/', '\'
            if (-not (Test-Dir $lib)) { continue }
            Add-Candidate $candidates ([System.IO.Path]::Combine($lib, 'steamapps\common\DeathRoadToCanada'))
        }
    }

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
Write-Host '=== DR2C Cheat Uninstaller ===' -ForegroundColor Cyan

$game = Find-Game
if (-not $game) { Write-Host 'ERROR: game not found.' -ForegroundColor Red; exit 1 }

$hackDir = Join-Path $game 'deathforth\hack'
$hackFile = Join-Path $hackDir 'hack.df'
if (Test-Path $hackFile) {
    Remove-Item $hackFile -Force
    Write-Host 'Removed deathforth\hack\hack.df - the game is back to vanilla.' -ForegroundColor Green
    # 只有在目录已空时才删除目录，避免误删用户的其他 mod
    if (-not (Get-ChildItem $hackDir -Force -ErrorAction SilentlyContinue)) {
        Remove-Item $hackDir -Force
    }
} else {
    Write-Host 'Nothing to remove (hack.df not present).'
}

Write-Host ''
Write-Host 'Save files were never modified by this trainer.'
Write-Host 'Backups are in the backup\ folder next to the trainer.'
Write-Host ''
