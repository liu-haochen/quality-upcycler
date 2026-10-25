$ErrorActionPreference='Stop'
$sourceRoot=Join-Path $PSScriptRoot 'mod'
$factorioRoot=Split-Path (Split-Path $PSScriptRoot)
$targetRoot=Join-Path $factorioRoot 'mods/quality-upcycler_0.1.0'
New-Item -ItemType Directory -Path $targetRoot -Force | Out-Null
Copy-Item -Path "$sourceRoot/*" -Destination $targetRoot -Recurse -Force
Write-Output "Installed: $targetRoot"
