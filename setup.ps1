# setup.ps1 — descarga las herramientas del proyecto en ./tools (no toca el sistema).
# Uso:  powershell -ExecutionPolicy Bypass -File setup.ps1

$ErrorActionPreference = "Stop"
$dir = Join-Path $PSScriptRoot "tools"
New-Item -ItemType Directory -Force -Path $dir | Out-Null

$headers = @{ "User-Agent" = "coin-island-setup" }

function Get-GhAsset($repo, $pattern, $outName) {
    Write-Host "Descargando $repo ..." -ForegroundColor Cyan
    $release = Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/releases/latest" -Headers $headers
    $asset = $release.assets | Where-Object { $_.name -match $pattern } | Select-Object -First 1
    if (-not $asset) { throw "No encuentro un asset que case con '$pattern' en $repo" }

    $zip = Join-Path $dir "_tmp.zip"
    Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $zip
    Expand-Archive -Path $zip -DestinationPath $dir -Force
    Remove-Item $zip
    Write-Host "  OK  $($release.tag_name)  ->  $outName" -ForegroundColor Green
}

# Rojo: sincroniza esta carpeta con Roblox Studio
Get-GhAsset "rojo-rbx/rojo" "windows-x86_64" "rojo.exe"

# El plugin de Studio, para no tener que buscarlo en la web
$release = Invoke-RestMethod -Uri "https://api.github.com/repos/rojo-rbx/rojo/releases/latest" -Headers $headers
$plugin = $release.assets | Where-Object { $_.name -eq "Rojo.rbxm" } | Select-Object -First 1
Invoke-WebRequest -Uri $plugin.browser_download_url -OutFile (Join-Path $dir "Rojo.rbxm")
Write-Host "  OK  Rojo.rbxm (plugin de Studio)" -ForegroundColor Green

# StyLua: formateador de Luau
Get-GhAsset "JohnnyMorganz/StyLua" "windows-x86_64" "stylua.exe"

Write-Host ""
Write-Host "Listo. Herramientas en: $dir" -ForegroundColor Yellow
Write-Host "Siguiente paso: instalar el plugin de Studio (ver README, paso 3)." -ForegroundColor Yellow
