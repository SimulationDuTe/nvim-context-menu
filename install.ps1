# nvim-context-menu
# Adds "Open with Neovim" to the Windows Explorer context menu.
# No admin required: writes only HKCU.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File install.ps1
#   powershell -ExecutionPolicy Bypass -File install.ps1 -NvimExe "C:\tools\nvim\nvim.exe"
#   powershell -ExecutionPolicy Bypass -File install.ps1 -Label "用 Neovim 打开"
#
# The launcher is placed in %LOCALAPPDATA%\nvim-context-menu and resolves nvim at
# run time (PATH -> recorded path -> NVIM_EXE), so drive letters do not matter.

param(
    [string]$NvimExe = '',
    [string]$Label = 'Open with Neovim',
    [switch]$SkipNilesoft
)

$ErrorActionPreference = 'Stop'

function Find-NvimExe {
    if ($NvimExe) {
        if (-not (Test-Path $NvimExe)) { throw "Given -NvimExe not found: $NvimExe" }
        return (Resolve-Path $NvimExe).Path
    }
    $onPath = Get-Command nvim.exe -ErrorAction SilentlyContinue
    if ($onPath) { return $onPath.Source }
    $candidates = @(
        (Join-Path $env:LOCALAPPDATA 'Programs\Neovim\bin\nvim.exe'),
        (Join-Path $env:ProgramFiles 'Neovim\bin\nvim.exe'),
        'C:\tools\neovim\nvim-win64\bin\nvim.exe',
        (Join-Path $env:USERPROFILE 'scoop\apps\neovim\current\bin\nvim.exe'),
        (Join-Path $env:LOCALAPPDATA 'nvim\bin\nvim.exe')
    )
    foreach ($c in $candidates) { if (Test-Path $c) { return (Resolve-Path $c).Path } }
    return $null
}

$nvim = Find-NvimExe
if (-not $nvim) {
    throw 'nvim.exe not found. Add Neovim to PATH, or pass -NvimExe <full path>.'
}
Write-Host "Using nvim: $nvim"

$appDir = Join-Path $env:LOCALAPPDATA 'nvim-context-menu'
New-Item -ItemType Directory -Force -Path $appDir | Out-Null
$launcher = Join-Path $appDir 'nvim-open.cmd'

$cmdContent = @'
@echo off
setlocal
set "TARGET=%~1"
if not defined TARGET exit /b 1

rem resolve nvim: PATH -> recorded path -> NVIM_EXE
set "NVIM="
for /f "delims=" %%I in ('where nvim.exe 2^>nul') do if not defined NVIM set "NVIM=%%I"
if not defined NVIM if exist "%~dp0nvim-path.txt" set /p NVIM=<"%~dp0nvim-path.txt"
if not defined NVIM if defined NVIM_EXE set "NVIM=%NVIM_EXE%"
if not defined NVIM (
    echo nvim.exe not found. Add Neovim to PATH or set NVIM_EXE.
    pause
    exit /b 1
)

rem resolve Windows Terminal: PATH -> default alias location
set "WT="
for /f "delims=" %%I in ('where wt.exe 2^>nul') do if not defined WT set "WT=%%I"
if not defined WT if exist "%LOCALAPPDATA%\Microsoft\WindowsApps\wt.exe" set "WT=%LOCALAPPDATA%\Microsoft\WindowsApps\wt.exe"

if exist "%TARGET%\" (
    if defined WT (start "" "%WT%" -d "%TARGET%" "%NVIM%") else (start "" "%NVIM%")
) else (
    for %%I in ("%TARGET%") do set "DIR=%%~dpI"
    if defined WT (start "" "%WT%" -d "%DIR%" "%NVIM%" "%TARGET%") else (start "" "%NVIM%" "%TARGET%")
)
'@
Set-Content -Path $launcher -Value $cmdContent -Encoding ASCII
Set-Content -Path (Join-Path $appDir 'nvim-path.txt') -Value $nvim -Encoding ASCII
Write-Host "Launcher: $launcher"

# --- registry verbs (HKCU only) ---
$icon = "$nvim,0"
$verbs = @(
    @{ Sub = '*\shell\OpenWithNeovim';                    Arg = '%1' },
    @{ Sub = 'Directory\shell\OpenWithNeovim';            Arg = '%1' },
    @{ Sub = 'Directory\Background\shell\OpenWithNeovim'; Arg = '%V' }
)

foreach ($v in $verbs) {
    $key = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey("Software\Classes\$($v.Sub)")
    $key.SetValue('MUIVerb', $Label, [Microsoft.Win32.RegistryValueKind]::String)
    $key.SetValue('Icon', $icon, [Microsoft.Win32.RegistryValueKind]::String)
    $cmdKey = $key.CreateSubKey('command')
    $cmdKey.SetValue('', '"' + $launcher + '" "' + $v.Arg + '"', [Microsoft.Win32.RegistryValueKind]::String)
    $cmdKey.Close()
    $key.Close()
    Write-Host "Registered: $($v.Sub)"
}

# --- optional: Nilesoft Shell top-level entry ---
$nssBlock = @"
// >>> nvim-context-menu
menu(type='file|dir|back|drive|namespace' mode='multiple' title='$Label' image='$nvim')
{
    item(type='file' mode='multiple' title='Open file' cmd='$launcher' args='`"@sel.path`"')
    item(type='dir' mode='multiple' title='Open folder here' cmd='$launcher' args='`"@sel.path`"')
    item(type='back|drive|namespace' mode='multiple' title='Open folder here' cmd='$launcher' args='`"@sel.dir`"')
}
// <<< nvim-context-menu
"@

$nsDirs = @(
    (Join-Path $env:LOCALAPPDATA 'Programs\Nilesoft Shell'),
    (Join-Path $env:ProgramFiles 'Nilesoft Shell')
)
$nsDone = $false
if (-not $SkipNilesoft) {
    foreach ($d in $nsDirs) {
        $nss = Join-Path $d 'shell.nss'
        if (Test-Path $nss) {
            $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
            $content = [System.IO.File]::ReadAllText($nss, [System.Text.Encoding]::UTF8)
            $pattern = '(?s)// >>> nvim-context-menu.*?// <<< nvim-context-menu\r?\n?'
            if ($content -match $pattern) {
                $content = [regex]::Replace($content, $pattern, '')
            }
            $content = $content.TrimEnd() + "`r`n`r`n" + $nssBlock + "`r`n"
            [System.IO.File]::WriteAllText($nss, $content, $utf8NoBom)
            Write-Host "Nilesoft Shell: updated $nss"
            $nsDone = $true
            break
        }
    }
}
if (-not $nsDone -and -not $SkipNilesoft) {
    $snippet = Join-Path $appDir 'nilesoft.nss'
    Set-Content -Path $snippet -Value $nssBlock -Encoding UTF8
    Write-Host "Nilesoft Shell not detected. Top-level menu snippet saved to: $snippet"
    Write-Host 'Install Nilesoft Shell from https://nilesoft.org, then import that file.'
}

Write-Host ''
Write-Host 'Done. Right-click a file or folder -> Show more options -> ' -NoNewline
Write-Host $Label -ForegroundColor Green
