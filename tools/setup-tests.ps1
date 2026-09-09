$ErrorActionPreference = 'Stop'
$workspaceRoot = Split-Path -Parent $PSScriptRoot
$testRuntime = Join-Path $workspaceRoot '.local-tools/python'
$nativeFixture = Join-Path $workspaceRoot '.local-tools/AceSerializer-3.0.lua'
New-Item -ItemType Directory -Force -Path $testRuntime | Out-Null
& python -m pip install --target $testRuntime -r (Join-Path $PSScriptRoot 'requirements-test.txt') --disable-pip-version-check
if ($LASTEXITCODE -ne 0) { throw 'Lua test runtime installation failed' }
& curl.exe -L --fail --retry 2 --max-time 30 -sS 'https://raw.githubusercontent.com/WoWUIDev/Ace3/master/AceSerializer-3.0/AceSerializer-3.0.lua' -o $nativeFixture
if ($LASTEXITCODE -ne 0) { throw 'Native serializer fixture download failed' }
$expectedHash = 'AF2D55FD5DED8CCA07608D20C40CC8AA776AFBD417F936F5078C8B0054E713FF'
if ((Get-FileHash -LiteralPath $nativeFixture -Algorithm SHA256).Hash -ne $expectedHash) {
    throw 'Native serializer fixture changed. Review upstream before updating the pinned hash.'
}
Write-Output 'Lua 5.1 runtime and pinned native AceSerializer fixture are ready.'
