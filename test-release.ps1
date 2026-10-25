param([string]$Factorio='E:/steam/steamapps/common/Factorio/bin/x64/Factorio.exe')
$ErrorActionPreference='Stop'
$runtimeRoot=Join-Path $PSScriptRoot 'runtime-release'
$modsRoot=Join-Path $runtimeRoot 'mods'
foreach ($directory in @('saves','script-output','temp','scenarios','config')) {
  New-Item -ItemType Directory -Force -Path (Join-Path $runtimeRoot $directory) | Out-Null
}
# Precreate reports for the Windows sandbox, and prevent stale results from a
# previous run from being mistaken for a successful check.
foreach ($folder in @('probe','release-probe')) {
  Get-ChildItem (Join-Path $PSScriptRoot $folder) -Filter '*.lua' | ForEach-Object {
    foreach ($match in [regex]::Matches((Get-Content -LiteralPath $_.FullName -Raw),'write_file\("([^"\r\n]+)"')) {
      Set-Content -LiteralPath (Join-Path "$runtimeRoot/script-output" $match.Groups[1].Value) -Value '' -Encoding utf8
    }
  }
}
foreach ($entry in @(@('mod','quality-upcycler_0.1.0'),@('probe','quality-upcycler-probe_0.1.0'),@('release-probe','quality-upcycler-release-probe_0.1.0'))) {
  $target=Join-Path $modsRoot $entry[1]
  New-Item -ItemType Directory -Force -Path $target | Out-Null
  Copy-Item -Path (Join-Path $PSScriptRoot ($entry[0]+'/*')) -Destination $target -Recurse -Force
}
'{"mods":[{"name":"base","enabled":true},{"name":"space-age","enabled":true},{"name":"quality","enabled":true},{"name":"recycler","enabled":true},{"name":"elevated-rails","enabled":true},{"name":"quality-upcycler","enabled":true},{"name":"quality-upcycler-probe","enabled":true},{"name":"quality-upcycler-release-probe","enabled":true}]}' | Set-Content -LiteralPath "$modsRoot/mod-list.json" -Encoding utf8
$dataPath=Join-Path (Split-Path (Split-Path (Split-Path $Factorio))) 'data'
@"
[path]
read-data=$($dataPath.Replace('\','/'))
write-data=$($runtimeRoot.Replace('\','/'))
"@ | Set-Content -LiteralPath "$runtimeRoot/config.ini" -Encoding utf8
function Run-Factorio([string[]]$Extra) {
  $arguments=@('--config',"$runtimeRoot/config.ini",'--mod-directory',$modsRoot)+$Extra
  $psi=New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName=$Factorio
  $psi.Arguments=(($arguments | ForEach-Object {'"'+$_+'"'}) -join ' ')
  $psi.UseShellExecute=$false;$psi.CreateNoWindow=$true
  $psi.RedirectStandardOutput=$true;$psi.RedirectStandardError=$true
  $process=New-Object System.Diagnostics.Process;$process.StartInfo=$psi
  [void]$process.Start()
  $stdoutTask=$process.StandardOutput.ReadToEndAsync();$stderrTask=$process.StandardError.ReadToEndAsync()
  $process.WaitForExit()
  $stdout=$stdoutTask.Result;$stderr=$stderrTask.Result
  Set-Content -LiteralPath "$runtimeRoot/stdout.txt" -Value $stdout -Encoding utf8
  Set-Content -LiteralPath "$runtimeRoot/stderr.txt" -Value $stderr -Encoding utf8
  if ($process.ExitCode -ne 0) { Write-Output $stdout;Write-Output $stderr;throw "Factorio returned $($process.ExitCode)" }
}
Run-Factorio @('--create',"$runtimeRoot/probe.zip",'--map-gen-seed','13579')
Run-Factorio @('--benchmark',"$runtimeRoot/probe.zip",'--benchmark-ticks','9060','--benchmark-runs','1')
Get-Content -LiteralPath "$runtimeRoot/script-output/upcycler-release-report.json"
