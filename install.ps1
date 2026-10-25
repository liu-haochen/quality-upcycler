param(
  [string]$FactorioRoot = (Join-Path $env:APPDATA 'Factorio')
)
$ErrorActionPreference='Stop'
$sourceRoot=Join-Path $PSScriptRoot 'mod'
$targetRoot=Join-Path $FactorioRoot 'mods/quality-upcycler_0.1.0'
New-Item -ItemType Directory -Path $targetRoot -Force | Out-Null
Copy-Item -Path "$sourceRoot/*" -Destination $targetRoot -Recurse -Force
Write-Output "Installed: $targetRoot"
