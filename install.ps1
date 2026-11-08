<#
ArchiBridge installer

Connects Claude Desktop (free plan included), Claude Code and ChatGPT / Codex to Archicad
through a local MCP server, and installs the Tapir add-on that gives it full model access.

Run it in a normal PowerShell window (not as administrator). Windows asks for permission once,
to copy Tapir into Archicad's Add-Ons folder in Program Files.

    irm https://raw.githubusercontent.com/ayoubmep/archibridge-mcp/main/install.ps1 | iex

Running it again is safe: it updates everything without duplicating it.

Optional environment variables, set before running:
    ARCHIBRIDGE_REPO     GitHub repo to install from (default ayoubmep/archibridge-mcp)
    ARCHIBRIDGE_BRANCH   Branch to install from (default main)
#>

function Install-ArchiBridge {
    $ErrorActionPreference = 'Stop'
    $ProgressPreference = 'SilentlyContinue'

    $Repo = 'ayoubmep/archibridge-mcp'
    if ($env:ARCHIBRIDGE_REPO) { $Repo = $env:ARCHIBRIDGE_REPO }
    $Branch = 'main'
    if ($env:ARCHIBRIDGE_BRANCH) { $Branch = $env:ARCHIBRIDGE_BRANCH }
    $McpName = 'archicad'
    $PythonVersion = '3.12'

    $TapirVersion = '1.7.3'
    $TapirHashes = @{
        25 = '5a14e119396be3c3955ef4c5ff3463617dff6bcd07ebfa14094a2ddd1dfde7c4'
        26 = '657e8a0fd3b2719fc37f1f1e4ca9e2bdf6c98d21438546091c78661f6270fb9c'
        27 = '8897968ec910a34c491f9e562bae0acdad639159d1a8bbdc653b534f15f5058f'
        28 = 'acb1329d8ad551c247b93cc3d1b56eb471cbe02bf22de5d2a7bc1f2febf7cf9b'
        29 = '4e72176c854e01d2602d16347506dbf18eb6bf08788aa25511448e76b9dd481d'
        30 = '4ef77f85d6845b73105e6f8c56cd68310678705c8d87e0a00bf6b69b58242b0c'
    }

    function Write-Step([string]$Text) { Write-Host ('[..] ' + $Text) -ForegroundColor Cyan }
    function Write-Ok([string]$Text) { Write-Host ('[OK] ' + $Text) -ForegroundColor Green }
    function Write-Note([string]$Text) { Write-Host ('[!!] ' + $Text) -ForegroundColor Yellow }
    function Write-Fail([string]$Text) { Write-Host ('[XX] ' + $Text) -ForegroundColor Red }

    # Runs a native program, shows its output indented, returns its exit code.
    function Invoke-Native([string]$Exe, [string[]]$Arguments) {
        $previous = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        $lines = @()
        $code = 1
        try {
            $lines = @(& $Exe @Arguments 2>&1 | ForEach-Object { $_.ToString() })
            $code = $LASTEXITCODE
        }
        catch {
            $lines = @($_.Exception.Message)
            $code = 1
        }
        finally {
            $ErrorActionPreference = $previous
        }
        foreach ($line in $lines) {
            if ($line -and $line.Trim()) { Write-Host ('     ' + $line.TrimEnd()) }
        }
        return $code
    }

    function Get-NativeText([string]$Exe, [string[]]$Arguments) {
        $previous = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try {
            $text = (& $Exe @Arguments 2>$null | ForEach-Object { $_.ToString() }) -join "`n"
            return @{ Code = $LASTEXITCODE; Text = $text }
        }
        catch {
            return @{ Code = 1; Text = $_.Exception.Message }
        }
        finally {
            $ErrorActionPreference = $previous
        }
    }

    function Write-Utf8File([string]$Path, [string]$Text) {
        $folder = Split-Path -Parent $Path
        if ($folder -and -not (Test-Path -LiteralPath $folder)) {
            New-Item -ItemType Directory -Path $folder -Force | Out-Null
        }
        [System.IO.File]::WriteAllText($Path, $Text, (New-Object System.Text.UTF8Encoding($false)))
    }

    function Test-IsAdmin {
        try {
            $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
            return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        }
        catch {
            return $false
        }
    }

    function Get-ArchicadVersions {
        $versions = @()
        foreach ($version in 25..30) {
            $exe = Join-Path $env:ProgramFiles ('Graphisoft\Archicad {0}\Archicad.exe' -f $version)
            if (Test-Path -LiteralPath $exe) { $versions += $version }
        }
        return $versions
    }

    function Find-Tool([string]$Name) {
        $command = Get-Command $Name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($command) { return $command.Path }
        $folders = @(
            (Join-Path $env:USERPROFILE '.local\bin'),
            (Join-Path $env:APPDATA 'npm'),
            (Join-Path $env:USERPROFILE 'scoop\shims')
        )
        foreach ($folder in $folders) {
            foreach ($extension in @('.exe', '.cmd', '.bat')) {
                $candidate = Join-Path $folder ($Name + $extension)
                if (Test-Path -LiteralPath $candidate) { return $candidate }
            }
        }
        return $null
    }

    function Get-PackageSource {
        if ($PSScriptRoot -and (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'pyproject.toml'))) {
            return $PSScriptRoot
        }
        return ('https://github.com/{0}/archive/refs/heads/{1}.zip' -f $Repo, $Branch)
    }

    # Downloads the add-on for one Archicad version and checks it against the pinned hash.
    function Get-TapirAddOn([int]$Version, [string]$Folder) {
        $name = 'TapirAddOn_AC{0}_Win.apx' -f $Version
        $path = Join-Path $Folder $name
        $expected = $TapirHashes[$Version]
        if ((Test-Path -LiteralPath $path) -and ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -eq $expected)) {
            return $path
        }
        New-Item -ItemType Directory -Path $Folder -Force | Out-Null
        $url = 'https://github.com/ENZYME-APD/tapir-archicad-automation/releases/download/{0}/{1}' -f $TapirVersion, $name
        Write-Step ('Downloading {0}...' -f $name)
        Invoke-WebRequest -Uri $url -OutFile $path -UseBasicParsing
        if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $expected) {
            Remove-Item -LiteralPath $path -Force
            throw ('{0} does not match its expected SHA-256 hash.' -f $name)
        }
        return $path
    }

    # The folder's name changes with Archicad's language, but it always holds XReadCfg.txt.
    function Get-AddOnsFolder([int]$Version) {
        $install = Join-Path $env:ProgramFiles ('Graphisoft\Archicad {0}' -f $Version)
        foreach ($folder in @(Get-ChildItem -LiteralPath $install -Directory -ErrorAction SilentlyContinue)) {
            if (Test-Path -LiteralPath (Join-Path $folder.FullName 'XReadCfg.txt')) { return $folder.FullName }
        }
        return $null
    }

    # Archicad loads what is in its Add-Ons folder, which is how Tapir's own installer works.
    # Program Files needs administrator rights, so only this copy is elevated. An existing
    # Tapir is never replaced: it may be newer, and Archicad locks it while running.
    function Install-TapirAddOn([string]$Source, [string]$AddOnsFolder, [string]$ExpectedHash) {
        if (@(Get-ChildItem -LiteralPath $AddOnsFolder -Recurse -Filter 'TapirAddOn_*.apx' -ErrorAction SilentlyContinue).Count -gt 0) {
            return 'present'
        }
        $name = Split-Path -Leaf $Source
        $command = @'
$ErrorActionPreference = 'Stop'
$tapir = Join-Path '@ADDONS@' 'Tapir'
New-Item -ItemType Directory -Path $tapir -Force | Out-Null
$target = Join-Path $tapir '@NAME@'
Copy-Item -LiteralPath '@SOURCE@' -Destination $target -Force
if ((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -ne '@HASH@') { Remove-Item -LiteralPath $target -Force; exit 3 }
'@
        $command = (($command -split "`r?`n") -join '; ').Replace('@ADDONS@', $AddOnsFolder.Replace("'", "''")).Replace('@NAME@', $name).Replace('@SOURCE@', $Source.Replace("'", "''")).Replace('@HASH@', $ExpectedHash)
        $arguments = '-NoProfile -ExecutionPolicy Bypass -Command "' + $command + '"'
        try {
            $process = Start-Process -FilePath 'powershell.exe' -Verb RunAs -WindowStyle Hidden -Wait -PassThru -ArgumentList $arguments
        }
        catch {
            return 'declined'
        }
        $target = Join-Path $AddOnsFolder ('Tapir\' + $name)
        if ($process.ExitCode -eq 0 -and (Test-Path -LiteralPath $target) -and ((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -eq $ExpectedHash)) {
            return 'installed'
        }
        return 'failed'
    }

    # Claude Desktop may keep its config per profile under Claude-Data instead of Roaming.
    # Roaming is only created when no other config exists, so a file nothing reads is never made.
    function Get-ClaudeDesktopConfigPaths {
        $paths = @()
        $dataRoot = Join-Path $env:LOCALAPPDATA 'Claude-Data'
        if (Test-Path -LiteralPath $dataRoot) {
            foreach ($folder in @(Get-ChildItem -LiteralPath $dataRoot -Directory -ErrorAction SilentlyContinue)) {
                $candidate = Join-Path $folder.FullName 'claude_desktop_config.json'
                if (Test-Path -LiteralPath $candidate) { $paths += $candidate }
            }
        }
        $packages = Join-Path $env:LOCALAPPDATA 'Packages'
        if (Test-Path -LiteralPath $packages) {
            foreach ($package in @(Get-ChildItem -LiteralPath $packages -Directory -Filter '*Claude*' -ErrorAction SilentlyContinue)) {
                $candidate = Join-Path $package.FullName 'LocalCache\Roaming\Claude\claude_desktop_config.json'
                if (Test-Path -LiteralPath $candidate) { $paths += $candidate }
            }
        }
        $roaming = Join-Path $env:APPDATA 'Claude\claude_desktop_config.json'
        if ($paths.Count -eq 0 -or (Test-Path -LiteralPath $roaming)) { $paths += $roaming }
        return $paths
    }

    # Adds or updates mcpServers.archicad in a Claude Desktop config, keeping everything else.
    function Set-ClaudeDesktopEntry([string]$Path, [string]$Exe) {
        $raw = ''
        if (Test-Path -LiteralPath $Path) { $raw = [System.IO.File]::ReadAllText($Path) }
        if ($raw.Trim().Length -gt 0) {
            try {
                $config = $raw | ConvertFrom-Json
            }
            catch {
                Write-Note ('{0} is not valid JSON, left untouched. Add this under "mcpServers" by hand: "{1}": {{ "command": "{2}" }}' -f $Path, $McpName, $Exe.Replace('\', '\\'))
                return $false
            }
            if ($config -isnot [System.Management.Automation.PSCustomObject]) {
                Write-Note ('{0} has an unexpected format, left untouched.' -f $Path)
                return $false
            }
            # Keep the user's original config: back it up only once.
            $backup = $Path + '.archibridge-backup'
            if (-not (Test-Path -LiteralPath $backup)) {
                Copy-Item -LiteralPath $Path -Destination $backup
            }
        }
        else {
            $config = New-Object PSObject
        }

        if (-not ($config.PSObject.Properties.Name -contains 'mcpServers') -or $null -eq $config.mcpServers) {
            $config | Add-Member -MemberType NoteProperty -Name 'mcpServers' -Value (New-Object PSObject) -Force
        }
        $entry = New-Object PSObject
        $entry | Add-Member -MemberType NoteProperty -Name 'command' -Value $Exe
        $config.mcpServers | Add-Member -MemberType NoteProperty -Name $McpName -Value $entry -Force

        Write-Utf8File $Path ($config | ConvertTo-Json -Depth 64)
        return $true
    }

    # Adds [mcp_servers.archicad] to Codex's config.toml when the codex command is not available.
    function Set-CodexTomlEntry([string]$Exe) {
        $path = Join-Path $env:USERPROFILE '.codex\config.toml'
        $text = ''
        if (Test-Path -LiteralPath $path) { $text = [System.IO.File]::ReadAllText($path) }
        if ($text -match ('(?m)^\s*\[mcp_servers\.' + $McpName + '\]')) {
            return 'exists'
        }
        if ($Exe.Contains("'")) {
            $command = '"' + $Exe.Replace('\', '\\').Replace('"', '\"') + '"'
        }
        else {
            $command = "'" + $Exe + "'"
        }
        $block = "[mcp_servers.$McpName]`ncommand = $command`n"
        if ($text.Length -gt 0 -and -not $text.EndsWith("`n")) { $text += "`n" }
        if ($text.Length -gt 0) { $text += "`n" }
        Write-Utf8File $path ($text + $block)
        return 'added'
    }

    # ---------------------------------------------------------------- start
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    }
    catch { }

    Write-Host ''
    Write-Host 'ArchiBridge installer: Claude and ChatGPT connected to Archicad' -ForegroundColor White
    Write-Host ''

    if ($env:OS -ne 'Windows_NT') {
        Write-Fail 'This installer is for Windows. On macOS, run this in Terminal instead:'
        Write-Host ('     curl -fsSL https://raw.githubusercontent.com/{0}/{1}/install.sh | bash' -f $Repo, $Branch)
        return
    }
    if (Test-IsAdmin) {
        Write-Note 'This window runs as administrator. Run the installer again from a normal PowerShell window so everything is set up for your own account.'
    }

    # 1. Archicad
    $versions = @(Get-ArchicadVersions)
    if ($versions.Count -gt 0) {
        Write-Ok ('Archicad found: {0}' -f ($versions -join ', '))
    }
    else {
        Write-Note 'No Archicad 25 to 30 found in Program Files. Continuing: the connection will work once one is installed.'
    }

    # 2. uv, which installs the server and its own Python
    $uv = Find-Tool 'uv'
    if (-not $uv) {
        Write-Step 'Installing uv from astral.sh (the tool that runs the ArchiBridge server)...'
        Invoke-RestMethod 'https://astral.sh/uv/install.ps1' | Invoke-Expression
        $uv = Find-Tool 'uv'
        if (-not $uv) {
            Write-Fail 'uv could not be installed. Install it from https://docs.astral.sh/uv/, then run this installer again.'
            return
        }
    }
    Write-Ok ('uv found: {0}' -f $uv)

    # 3. The MCP server
    $source = Get-PackageSource
    Write-Step ('Installing the ArchiBridge server from {0}...' -f $source)
    $arguments = @('tool', 'install', '--force', '--reinstall', '--refresh', '--python', $PythonVersion, $source)
    if ((Invoke-Native $uv $arguments) -ne 0) {
        Write-Fail 'The server could not be installed. If your AI app is running ArchiBridge, quit it and run this installer again.'
        return
    }
    $binary = Get-NativeText $uv @('tool', 'dir', '--bin')
    $server = Join-Path $binary.Text.Trim() 'archibridge.exe'
    if (-not (Test-Path -LiteralPath $server)) {
        Write-Fail ('The server is missing from {0}.' -f $server)
        return
    }
    Write-Ok ('Server installed: {0}' -f $server)

    # 4. Tapir add-on
    $tapirFolder = Join-Path $env:LOCALAPPDATA ('ArchiBridge\Tapir\' + $TapirVersion)
    $tapirManual = @()
    $tapirAdded = $false
    foreach ($version in $versions) {
        try {
            $file = Get-TapirAddOn $version $tapirFolder
            $addOns = Get-AddOnsFolder $version
            if (-not $addOns) {
                Write-Note ('The Add-Ons folder of Archicad {0} was not found.' -f $version)
                $tapirManual += $file
                continue
            }
            Write-Step ('Adding Tapir to Archicad {0}. Windows asks for permission if it is missing: click Yes.' -f $version)
            $state = Install-TapirAddOn $file $addOns $TapirHashes[$version]
            if ($state -eq 'present') {
                Write-Ok ('Tapir is already in Archicad {0}: left as it is.' -f $version)
            }
            elseif ($state -eq 'installed') {
                Write-Ok ('Tapir {0} added to Archicad {1}, and its hash is verified.' -f $TapirVersion, $version)
                $tapirAdded = $true
            }
            else {
                Write-Note ('Tapir was not added to Archicad {0} ({1}).' -f $version, $state)
                $tapirManual += $file
            }
        }
        catch {
            Write-Note ('Could not get Tapir for Archicad {0}: {1}' -f $version, $_.Exception.Message)
        }
    }

    # 5. MCP clients
    $configured = @()

    $claudeCli = Find-Tool 'claude'
    if ($claudeCli) {
        Write-Step 'Registering the archicad MCP server with Claude Code...'
        [void](Get-NativeText $claudeCli @('mcp', 'remove', '--scope', 'user', $McpName))
        if ((Invoke-Native $claudeCli @('mcp', 'add', '--scope', 'user', $McpName, '--', $server)) -eq 0) {
            Write-Ok 'Claude Code: done (user scope).'
            $configured += 'Claude Code'
        }
        else {
            Write-Note ('Claude Code registration failed. Try later: claude mcp add --scope user {0} -- "{1}"' -f $McpName, $server)
        }
    }
    else {
        Write-Note 'Claude Code command not found: skipped (normal if you only use Claude Desktop).'
    }

    $desktopFound = (Test-Path -LiteralPath (Join-Path $env:APPDATA 'Claude')) -or (Test-Path -LiteralPath (Join-Path $env:LOCALAPPDATA 'AnthropicClaude')) -or (Test-Path -LiteralPath (Join-Path $env:LOCALAPPDATA 'Claude-Data'))
    $desktopDone = $false
    foreach ($path in @(Get-ClaudeDesktopConfigPaths)) {
        try {
            if (Set-ClaudeDesktopEntry $path $server) {
                Write-Ok ('Claude Desktop: {0}' -f $path)
                $desktopDone = $true
            }
        }
        catch {
            Write-Note ('Could not update {0}: {1}' -f $path, $_.Exception.Message)
        }
    }
    if ($desktopDone -and $desktopFound) {
        $configured += 'Claude Desktop'
    }
    elseif ($desktopDone) {
        Write-Note 'Claude Desktop is not installed yet: its config is ready for when you install it (claude.ai/download).'
    }

    $codexCli = Find-Tool 'codex'
    if ($codexCli) {
        Write-Step 'Registering the archicad MCP server with Codex (ChatGPT)...'
        [void](Get-NativeText $codexCli @('mcp', 'remove', $McpName))
        if ((Invoke-Native $codexCli @('mcp', 'add', $McpName, '--', $server)) -eq 0) {
            Write-Ok 'Codex / ChatGPT: done.'
            $configured += 'ChatGPT / Codex'
        }
        else {
            Write-Note ('Codex registration failed. Try later: codex mcp add {0} -- "{1}"' -f $McpName, $server)
        }
    }
    elseif (Test-Path -LiteralPath (Join-Path $env:USERPROFILE '.codex')) {
        try {
            $state = Set-CodexTomlEntry $server
            if ($state -eq 'added') { Write-Ok 'ChatGPT / Codex: added to .codex\config.toml' }
            else { Write-Ok 'ChatGPT / Codex: already configured.' }
            $configured += 'ChatGPT / Codex'
        }
        catch {
            Write-Note ('Could not update .codex\config.toml: {0}' -f $_.Exception.Message)
        }
    }

    # 6. Status
    Write-Step 'Archicad status:'
    [void](Invoke-Native $server @('doctor'))

    Write-Host ''
    if ($configured.Count -gt 0) {
        Write-Ok ('ArchiBridge is installed. Connected apps: {0}' -f ($configured -join ', '))
    }
    else {
        Write-Note 'The server is ready, but no AI app was found. Install Claude Desktop (claude.ai/download), then run this installer again.'
    }
    Write-Host ''
    Write-Host 'Next steps:' -ForegroundColor White
    if ($tapirAdded -and (Get-Process -Name 'Archicad' -ErrorAction SilentlyContinue)) {
        Write-Host '  1. Save your work and restart Archicad so it loads Tapir, then open a project.'
    }
    else {
        Write-Host '  1. Start Archicad and open a project.'
    }
    if ($tapirManual.Count -gt 0) {
        Write-Host '     To add Tapir yourself, run the installer again and click Yes, or in Archicad use'
        Write-Host '     Options > Add-On Manager > Edit List of Available Add-Ons > Add, and pick:'
        foreach ($file in $tapirManual) { Write-Host ('     ' + $file) }
    }
    Write-Host '  2. Quit your AI app completely and open it again.'
    Write-Host '     Claude Desktop: right-click the Claude icon near the clock > Quit. Claude Code: start a new session.'
    Write-Host '  3. Try: "Read the archibridge skill, then describe my open Archicad project."'
    Write-Host '  4. When the AI wants to change the model, your AI app asks you first.'
    Write-Host ''
}

$archibridgeLog = Join-Path $env:TEMP 'archibridge-install.log'
$archibridgeTranscript = $false
try {
    Start-Transcript -Path $archibridgeLog -Force | Out-Null
    $archibridgeTranscript = $true
}
catch { }
try {
    Install-ArchiBridge
}
catch {
    Write-Host ('[XX] Unexpected error: {0}' -f $_.Exception.Message) -ForegroundColor Red
}
finally {
    if ($archibridgeTranscript) {
        try { Stop-Transcript | Out-Null } catch { }
        Write-Host ('Install log: {0}' -f $archibridgeLog)
    }
}
