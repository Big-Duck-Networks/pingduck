# Local release builds with the same build number CI uses: the git commit
# count. Stamps pingduck_app/pubspec.yaml and app_version.dart, builds, then
# puts both files back so the stamp is never committed.
#
#   powershell -File tools\build.ps1 apk         # build\app\outputs\flutter-apk\app-release.apk
#   powershell -File tools\build.ps1 appbundle   # unsigned unless the upload key is configured
#   powershell -File tools\build.ps1 windows     # build\windows\x64\runner\Release\PingDuck.exe
#   powershell -File tools\build.ps1 installer   # installer\windows\Output\PingDuckSetup.exe
#
# The version name (1.0.0) is edited by hand in pubspec.yaml; the build
# number there is a placeholder and is never bumped by hand.
param(
  [ValidateSet('apk', 'appbundle', 'windows', 'installer')]
  [string]$Target = 'apk'
)
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
$app = Join-Path $repo 'pingduck_app'
$stamped = @('pingduck_app/pubspec.yaml', 'pingduck_app/lib/core/constants/app_version.dart')

function Invoke-Checked([string]$what, [scriptblock]$cmd) {
  & $cmd
  if ($LASTEXITCODE -ne 0) { throw "$what failed (exit $LASTEXITCODE)" }
}

$dirty = git -C $repo status --porcelain -- $stamped
if ($dirty) { throw "Commit or discard changes to $($stamped -join ', ') first; this script restores them." }

Push-Location $app
try {
  Invoke-Checked 'stamping the build number' { dart run tools/build_number_gen.dart --git }
  $full = ((Select-String -Path pubspec.yaml -Pattern '^version:\s*(.+)$').Matches[0].Groups[1].Value).Trim()
  $version, $build = $full -split '\+'
  Write-Output "Building $Target $version ($build)"

  switch ($Target) {
    'apk' { Invoke-Checked 'flutter build apk' { flutter build apk --release } }
    'appbundle' { Invoke-Checked 'flutter build appbundle' { flutter build appbundle --release } }
    { $_ -in 'windows', 'installer' } { Invoke-Checked 'flutter build windows' { flutter build windows --release } }
  }

  if ($Target -eq 'installer') {
    Invoke-Checked 'cargo build' { cargo build --release --locked -p pingduck-agent --manifest-path (Join-Path $repo 'agent\Cargo.toml') }
    $iscc = @(
      (Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 6\ISCC.exe'),
      (Join-Path $env:LOCALAPPDATA 'Programs\Inno Setup 6\ISCC.exe')
    ) | Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $iscc) { throw 'Inno Setup 6 not found (winget install JRSoftware.InnoSetup).' }
    Invoke-Checked 'Inno Setup' { & $iscc /Q "/DAppVersion=$version" "/DAppBuild=$build" (Join-Path $repo 'installer\windows\pingduck.iss') }
    Write-Output "Built $(Join-Path $repo 'installer\windows\Output\PingDuckSetup.exe')"
  }
} finally {
  Pop-Location
  git -C $repo checkout -- $stamped
}
