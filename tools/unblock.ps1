# 解除本工具目录内所有文件的“网络来源”锁定，尽量消除 SmartScreen 拦截。
# 原理：执行 Unblock-File 并删除 Zone.Identifier（文件来自互联网的标记）。
# 注意：这只处理下载标记，不能替代“受信任的代码签名”；仍被拦时见 README 第 3 节。
$root = Split-Path -Parent $PSScriptRoot

$files = Get-ChildItem $root -Recurse -File
$done = 0
foreach ($f in $files) {
    if ($f.Name -eq 'unblock.ps1') { continue }
    try {
        Unblock-File -Path $f.FullName -ErrorAction SilentlyContinue
        Remove-Item -Path ($f.FullName + ':Zone.Identifier') -Force -ErrorAction SilentlyContinue
        $done++
    } catch { }
}

Write-Host ''
Write-Host "已处理 $done 个文件：解除锁定 / 清除 Zone.Identifier 完成。"
Write-Host ''
Write-Host '如果双击 启动面板.bat 或 install.bat 没反应：'
Write-Host '  1) 右键 → 以管理员身份运行；'
Write-Host '  2) 或在 PowerShell 里执行：Set-ExecutionPolicy -Scope CurrentUser RemoteSigned；'
Write-Host '  3) 也可以先双击本脚本解除整包锁定后再试。'
Write-Host ''
