param([string]$Factorio='E:/steam/steamapps/common/Factorio/bin/x64/Factorio.exe')
$ErrorActionPreference='Stop'
$labRoot=$PSScriptRoot
$runtimeRoot=Join-Path $labRoot 'runtime'
$modsRoot=Join-Path $runtimeRoot 'mods'
New-Item -ItemType Directory -Force -Path "$modsRoot/quality-upcycler_0.1.0","$modsRoot/quality-upcycler-probe_0.1.0" | Out-Null
Copy-Item -Path "$labRoot/mod/*" -Destination "$modsRoot/quality-upcycler_0.1.0" -Recurse -Force
Copy-Item -Path "$labRoot/probe/*" -Destination "$modsRoot/quality-upcycler-probe_0.1.0" -Recurse -Force
'{"mods":[{"name":"base","enabled":true},{"name":"space-age","enabled":true},{"name":"quality","enabled":true},{"name":"recycler","enabled":true},{"name":"elevated-rails","enabled":true},{"name":"quality-upcycler","enabled":true},{"name":"quality-upcycler-probe","enabled":true}]}' | Set-Content -LiteralPath "$modsRoot/mod-list.json" -Encoding utf8
$dataPath=Join-Path (Split-Path (Split-Path (Split-Path $Factorio))) 'data'
@"
[path]
read-data=$($dataPath.Replace('\','/'))
write-data=$($runtimeRoot.Replace('\','/'))
"@ | Set-Content -LiteralPath "$runtimeRoot/config.ini" -Encoding utf8
function Run-Factorio([string[]]$Extra) {
  $all=@('--config',"$runtimeRoot/config.ini",'--mod-directory',$modsRoot)+$Extra
  $quoted=$all | ForEach-Object {'"'+$_+'"'}
  $psi=New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName=$Factorio
  $psi.Arguments=($quoted -join ' ')
  $psi.UseShellExecute=$false
  $psi.RedirectStandardOutput=$true
  $psi.RedirectStandardError=$true
  $psi.CreateNoWindow=$true
  $process=New-Object System.Diagnostics.Process
  $process.StartInfo=$psi
  [void]$process.Start()
  $stdout=$process.StandardOutput.ReadToEnd()
  $stderr=$process.StandardError.ReadToEnd()
  $process.WaitForExit()
  Set-Content -LiteralPath "$runtimeRoot/stdout.txt" -Value $stdout -Encoding utf8
  Set-Content -LiteralPath "$runtimeRoot/stderr.txt" -Value $stderr -Encoding utf8
  if ($process.ExitCode -ne 0) {
    Get-Content "$runtimeRoot/stdout.txt" -Tail 25
    Get-Content "$runtimeRoot/stderr.txt" -Tail 20
    throw "Factorio returned $($process.ExitCode)"
  }
}
Run-Factorio @('--create',"$runtimeRoot/probe.zip",'--map-gen-seed','13579')
Run-Factorio @('--benchmark',"$runtimeRoot/probe.zip",'--benchmark-ticks','9060','--benchmark-runs','1')
Get-Content -LiteralPath "$runtimeRoot/script-output/upcycler-buffer.json"
Get-Content -LiteralPath "$runtimeRoot/script-output/upcycler-report.json"



