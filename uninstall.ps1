<#
ArchiBridge uninstaller

Removes the archicad MCP connection from your AI apps, the ArchiBridge server and the
downloaded Tapir files. Archicad and your projects are not touched.

    irm https://raw.githubusercontent.com/ayoubmep/archibridge-mcp/main/uninstall.ps1 | iex
#>

function Uninstall-ArchiBridge {
    $ErrorActionPreference = 'Stop'
    $McpName = 'archicad'

    function Write-Ok([string]$Text) { Write-Host ('[OK] ' + $Text) -ForegroundColor Green }
    function Write-Note([string]$Text) { Write-Host ('[!!] ' + $Text) -ForegroundColor Yellow }

    function Find-Tool([string]$Name) {
        $command = Get-Command $Name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($command) { return $command.Path }
        foreach ($folder in @((Join-Path $env:USERPROFILE '.local\bin'), (Join-Path $env:APPDATA 'npm'))) {
            foreach ($extension in @('.exe', '.cmd', '.bat')) {
                $candidate = Join-Path $folder ($Name + $extension)
                if (Test-Path -LiteralPath $candidate) { return $candidate }
            }
        }
        return $null
    }

    function Invoke-Quiet([string]$Exe, [string[]]$Arguments) {
        $previous = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try {
            & $Exe @Arguments 2>&1 | Out-Null
            return $LASTEXITCODE
        }
        catch {
            return 1
        }
        finally {
            $ErrorActionPreference = $previous
        }
    }

    function Remove-ClaudeDesktopEntry([string]$Path) {
        if (-not (Test-Path -LiteralPath $Path)) { return }
        try {
            $config = [System.IO.File]::ReadAllText($Path) | ConvertFrom-Json
        }
        catch {
            Write-Note ('{0} is not valid JSON, left untouched.' -f $Path)
            return
        }
        if ($config.mcpServers -and ($config.mcpServers.PSObject.Properties.Name -contains $McpName)) {
            $config.mcpServers.PSObject.Properties.Remove($McpName)
            [System.IO.File]::WriteAllText($Path, ($config | ConvertTo-Json -Depth 64), (New-Object System.Text.UTF8Encoding($false)))
            Write-Ok ('Claude Desktop: removed from {0}' -f $Path)
        }
    }

    function Remove-CodexTomlEntry {
        $path = Join-Path $env:USERPROFILE '.codex\config.toml'
        if (-not (Test-Path -LiteralPath $path)) { return }
        $text = [System.IO.File]::ReadAllText($path)
        $pattern = '(?ms)^\s*\[mcp_servers\.' + $McpName + '\].*?(?=^\s*\[|\z)'
        if ($text -match $pattern) {
            [System.IO.File]::WriteAllText($path, ($text -replace $pattern, ''), (New-Object System.Text.UTF8Encoding($false)))
            Write-Ok 'ChatGPT / Codex: removed from .codex\config.toml'
        }
    }

    Write-Host ''
    Write-Host 'ArchiBridge uninstaller' -ForegroundColor White
    Write-Host ''

    $claudeCli = Find-Tool 'claude'
    if ($claudeCli -and (Invoke-Quiet $claudeCli @('mcp', 'remove', '--scope', 'user', $McpName)) -eq 0) {
        Write-Ok 'Claude Code: removed.'
    }

    Remove-ClaudeDesktopEntry (Join-Path $env:APPDATA 'Claude\claude_desktop_config.json')
    $packages = Join-Path $env:LOCALAPPDATA 'Packages'
    if (Test-Path -LiteralPath $packages) {
        foreach ($package in @(Get-ChildItem -LiteralPath $packages -Directory -Filter '*Claude*' -ErrorAction SilentlyContinue)) {
            Remove-ClaudeDesktopEntry (Join-Path $package.FullName 'LocalCache\Roaming\Claude\claude_desktop_config.json')
        }
    }

    $codexCli = Find-Tool 'codex'
    if ($codexCli) {
        if ((Invoke-Quiet $codexCli @('mcp', 'remove', $McpName)) -eq 0) { Write-Ok 'Codex: removed.' }
    }
    else {
        Remove-CodexTomlEntry
    }

    $uv = Find-Tool 'uv'
    if ($uv -and (Invoke-Quiet $uv @('tool', 'uninstall', 'archibridge')) -eq 0) {
        Write-Ok 'ArchiBridge server: removed.'
    }

    $folder = Join-Path $env:LOCALAPPDATA 'ArchiBridge'
    Write-Note 'If Archicad loads Tapir from this folder, first remove it in Options > Add-On Manager.'
    if (Test-Path -LiteralPath $folder) {
        Remove-Item -LiteralPath $folder -Recurse -Force
        Write-Ok ('Removed {0}' -f $folder)
    }
    Write-Host ''
}

try {
    Uninstall-ArchiBridge
}
catch {
    Write-Host ('[XX] Unexpected error: {0}' -f $_.Exception.Message) -ForegroundColor Red
}
