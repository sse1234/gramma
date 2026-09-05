# Packages the Windows release bundle as a zip.
# Usage: tool/package-windows.ps1 -Version 1.0.1 -Arch x64|arm64 -Out dist
param([string]$Version, [string]$Arch, [string]$Out)
$ErrorActionPreference = "Stop"
$root = Resolve-Path (Join-Path $PSScriptRoot "..")
$bundle = Join-Path $root "app\build\windows\$Arch\runner\Release"
if (-not (Test-Path (Join-Path $bundle "gramma.exe"))) { throw "no bundle at $bundle" }
New-Item -ItemType Directory -Force $Out | Out-Null
$staging = Join-Path ([System.IO.Path]::GetTempPath()) "gramma-$Version"
if (Test-Path $staging) { Remove-Item -Recurse -Force $staging }
Copy-Item -Recurse $bundle $staging
Compress-Archive -Path $staging -DestinationPath (Join-Path $Out "gramma-$Version-windows-$Arch.zip") -Force
Get-ChildItem $Out
