$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot

function Find-Game {
    $candidates = @(
        "D:\Program Files (x86)\Steam\steamapps\common\DeathRoadToCanada",
        "C:\Program Files (x86)\Steam\steamapps\common\DeathRoadToCanada",
        "C:\Program Files\Steam\steamapps\common\DeathRoadToCanada"
    )
    $steam = $null
    try { $steam = (Get-ItemProperty 'HKCU:\Software\Valve\Steam' -ErrorAction Stop).SteamPath } catch { }
    if (-not $steam) {
        try { $steam = (Get-ItemProperty 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam' -ErrorAction Stop).InstallPath } catch { }
    }
    if ($steam) {
        $candidates += (Join-Path $steam 'steamapps\common\DeathRoadToCanada')
        $lf = Join-Path $steam 'steamapps\libraryfolders.vdf'
        if (Test-Path $lf) {
            foreach ($m in [regex]::Matches((Get-Content $lf -Raw), '"path"\s*"([^"]+)"')) {
                $lib = $m.Groups[1].Value -replace '\\\\', '\'
                $candidates += (Join-Path $lib 'steamapps\common\DeathRoadToCanada')
            }
        }
    }
    foreach ($c in $candidates) {
        if (Test-Path (Join-Path $c 'deathforth\boot.df')) { return $c }
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
