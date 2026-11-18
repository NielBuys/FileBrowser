# Builds FileBrowser.exe with lazbuild, then the Inno Setup installer.
# Output: installer\Output\FileBrowser-Setup-<version>.exe
# Run from anywhere:  powershell -ExecutionPolicy Bypass -File installer\build-installer.ps1

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$lazbuild = 'C:\lazarus\lazbuild.exe'
$iscc = "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe"

if (Get-Process FileBrowser -ErrorAction SilentlyContinue) {
    throw 'File Browser is running. Close it first so the exe can be rebuilt.'
}

& $lazbuild --lazarusdir=C:\lazarus -B (Join-Path $root 'FileBrowser.lpi')
if ($LASTEXITCODE -ne 0) { throw "lazbuild failed ($LASTEXITCODE)" }

& $iscc (Join-Path $PSScriptRoot 'FileBrowser.iss')
if ($LASTEXITCODE -ne 0) { throw "ISCC failed ($LASTEXITCODE)" }

Get-ChildItem (Join-Path $PSScriptRoot 'Output') -Filter 'FileBrowser-Setup-*.exe' |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1 FullName, Length
