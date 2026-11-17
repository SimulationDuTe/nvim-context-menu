# nvim-context-menu - uninstall
# Removes the registry verbs, the launcher folder and the Nilesoft menu block.
# Does not uninstall Neovim or Nilesoft Shell itself.

$ErrorActionPreference = 'SilentlyContinue'

$verbs = @('*\shell\OpenWithNeovim', 'Directory\shell\OpenWithNeovim', 'Directory\Background\shell\OpenWithNeovim')

$classes = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Software\Classes', $true)
if ($classes) {
    foreach ($v in $verbs) {
        try {
            $classes.DeleteSubKeyTree($v, $false)
            Write-Host "Removed: $v"
        } catch {
            Write-Host "Skip (not found): $v"
        }
    }
    $classes.Close()
}

# remove the Nilesoft menu block if present
$nsDirs = @(
    (Join-Path $env:LOCALAPPDATA 'Programs\Nilesoft Shell'),
    (Join-Path $env:ProgramFiles 'Nilesoft Shell')
)
foreach ($d in $nsDirs) {
    $nss = Join-Path $d 'shell.nss'
    if (Test-Path $nss) {
        $content = [System.IO.File]::ReadAllText($nss, [System.Text.Encoding]::UTF8)
        $pattern = '(?s)\r?\n?// >>> nvim-context-menu.*?// <<< nvim-context-menu\r?\n?'
        if ($content -match $pattern) {
            $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
            [System.IO.File]::WriteAllText($nss, [regex]::Replace($content, $pattern, "`r`n"), $utf8NoBom)
            Write-Host "Cleaned Nilesoft config: $nss"
        }
    }
}

$appDir = Join-Path $env:LOCALAPPDATA 'nvim-context-menu'
if (Test-Path $appDir) {
    Remove-Item -LiteralPath $appDir -Recurse -Force
    Write-Host "Removed launcher folder: $appDir"
}

Write-Host ''
Write-Host 'Uninstall done.' -ForegroundColor Green
