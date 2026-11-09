# ArchiBridge: install guide for AI agents

This file is for an AI agent (Claude Code, Codex, or similar) asked to install ArchiBridge on the user's computer. ArchiBridge supports **Windows and macOS**, and both installs are automatic. Follow this guide step by step and keep the user informed in their own language.

## Step 0. Check the operating system

Do this first, before telling the user anything:

- Your environment may already say it, for example `Platform: win32` (Windows) or `Platform: darwin` (macOS).
- Otherwise run `uname -s`. `Darwin` means macOS. `MINGW64_NT...`, `MSYS_NT...` or `CYGWIN_NT...` means Windows. If `uname` doesn't exist but PowerShell does, it is Windows.

Then follow only the section for that system: [Windows](#windows) or [macOS](#macos).

On a Mac, run `install.sh` as described below. Don't say that ArchiBridge or its installer is for Windows only, and don't offer a manual install instead. On Linux, tell the user that Archicad, and so ArchiBridge, only runs on Windows and macOS.

## What gets installed

- **uv**, only if it is missing. It installs the server and its own Python, and touches no existing Python.
- **The ArchiBridge MCP server**, as a uv tool: `archibridge.exe` on Windows, `~/.local/bin/archibridge` on a Mac.
- **The Tapir add-on** for each Archicad version found, from the official Tapir GitHub release, checked against a pinned SHA-256 hash. It goes in Archicad's Add-Ons folder, in a `Tapir` subfolder, the same place Tapir's own installer uses, so Archicad loads it at startup. An existing Tapir is left as it is.
  - Windows: `<Archicad>\Add-Ons\Tapir\TapirAddOn_AC<version>_Win.apx`
  - macOS: `/Applications/GRAPHISOFT/Archicad <version>/Add-Ons/Tapir/TapirAddOn_AC<version>_Mac.bundle`. Tapir's Mac builds are signed and notarized by Tapir's authors.
- **The `archicad` MCP server entry**, registered with Claude Desktop, and with Claude Code and Codex / ChatGPT when they are installed.

The installer never changes other MCP servers. It backs up the Claude Desktop config (`claude_desktop_config.json.archibridge-backup`) before editing it.

## Windows

### Step 1. Tell the user two things

1. Windows shows one permission prompt, to copy Tapir into Program Files. The user should click **Yes**. You can't answer it for them, and the installer waits for it.
2. Archicad can stay open during the install, but it must be restarted afterwards to load Tapir. Ask the user to save their work first.

### Step 2. Run the installer

Run this in PowerShell as the normal user, not as administrator. Give the command a long timeout (10 minutes):

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -Command "irm https://bimspeak.com/archibridge/install.ps1 | iex"
```

Read the whole output (see [Read the output](#read-the-output)). The installer saves a full log to `%TEMP%\archibridge-install.log`.

### Step 3. Check the result

Ask the user to restart Archicad and open a project, then run:

```powershell
& "$(uv tool dir --bin)\archibridge.exe" doctor
```

Then go to [Read the doctor output](#read-the-doctor-output).

## macOS

### Step 1. Tell the user two things

1. macOS may show one password prompt, to copy Tapir into Archicad's Add-Ons folder in Applications. It appears only when that folder belongs to an administrator. The user types their Mac password, or an administrator's name and password. You can't answer it for them, and the installer waits for it.
2. Archicad can stay open during the install, but it must be restarted afterwards to load Tapir. Ask the user to save their work first.

### Step 2. Run the installer

Run this in a shell (zsh or bash) as the normal user, not with `sudo`. Give the command a long timeout (10 minutes):

```bash
curl -fsSL https://bimspeak.com/archibridge/install.sh | bash
```

It needs nothing but macOS itself: no Homebrew, Python, Node or Xcode tools. It installs uv if it is missing, and uv brings the server's own Python.

The installer writes outside the current folder (`~/.local`, `~/Library` and Archicad's Add-Ons folder) and downloads from GitHub, PyPI and astral.sh. If your commands run in a sandbox that blocks this, run this one command outside the sandbox.

Read the whole output (see [Read the output](#read-the-output)). The installer saves a full log to `~/Library/Logs/archibridge-install.log`.

### Step 3. Check the result

Ask the user to restart Archicad and open a project, then run:

```bash
"$HOME/.local/bin/archibridge" doctor
```

If the installer's `Server installed:` line shows another path, run that one with `doctor`. Then go to [Read the doctor output](#read-the-doctor-output).

## Read the output

Both installers mark each line the same way:

- `[OK]` a step worked.
- `[..]` a step is running.
- `[!!]` a warning. Read it: some need the user.
- `[XX]` an error. The installer stopped. Fix the cause (see [Troubleshooting](#troubleshooting)), then run the same command again. Running it twice is safe.

## Read the doctor output

`doctor` prints every running Archicad as JSON. Each one has a `status`:

| Status | Meaning |
|---|---|
| `ready` | A project is open. |
| `no_project` | Archicad is open but no project is. Ask the user to open one. |
| `busy` | A dialog is open, or Archicad is working. |

An empty `instances` list means Archicad is not running.

`"tapir"` must show a version. `null` means the add-on is not loaded, and only Archicad's 73 built-in commands work. See Troubleshooting.

## Step 4. Tell the user what to do next

1. Quit the AI app completely and open it again, so it loads the new MCP server.
   - Claude Desktop on Windows: right-click the Claude icon near the clock, then **Quit**.
   - Claude Desktop on macOS: **Claude > Quit Claude** in the menu bar (Cmd+Q). Closing the window is not enough.
   - Claude Code: start a new session.
   - ChatGPT desktop app: quit and reopen it.
2. In a new chat, try: "Read the archibridge skill, then describe my open Archicad project."
3. When the AI changes the model, the AI app asks for approval first, unless the user has told it to always allow the `archicad_modify` tool.

You are probably running in the session that did the install: the `archicad_*` tools only appear after the restart.

## Troubleshooting

### Windows

| Symptom | Fix |
|---|---|
| `[XX] The server could not be installed` | The AI app may be running the old server. Quit it and run the installer again from a PowerShell window. |
| `Tapir was not added` | The Windows prompt was refused or failed. Run the installer again and have the user click **Yes**. If that isn't possible, the user can add the `.apx` the installer printed in Archicad: **Options > Add-On Manager > Edit List of Available Add-Ons > Add**. |
| `"tapir": null` | Restart Archicad. Check that `<Archicad>\Add-Ons\Tapir` holds the `.apx` for that Archicad version. |
| No `archicad_*` tools after the restart | Check that the Claude Desktop config has `mcpServers.archicad` with a `command` pointing to `archibridge.exe`. The config is either `%LOCALAPPDATA%\Claude-Data\<profile>\claude_desktop_config.json` or `%APPDATA%\Claude\claude_desktop_config.json`. The server's log, `mcp-server-archicad.log`, is in the `logs` folder beside it. |

### macOS

| Symptom | Fix |
|---|---|
| `[XX] This runs as root (sudo)` | Run the same command again without `sudo`. |
| `[XX] uv could not be installed` | The network may block astral.sh. Install uv from https://docs.astral.sh/uv/ (or with `brew install uv`), then run the installer again. |
| `[XX] The server could not be installed` | Read the uv output above it. Usually the network blocks GitHub or PyPI. Fix that, then run the installer again. If uv says a package has no ready-made build (wheel) for this Mac, don't install compilers to work around it: open an issue with the install log. |
| `Tapir was not added (declined)` or `(failed)` | The password prompt was cancelled, or the user is not an administrator. Run the installer again and have the user enter their password, or an administrator's name and password. If that isn't possible, the user can add the `.bundle` the installer printed in Archicad: **Options > Add-On Manager > Edit List of Available Add-Ons > Add**. |
| `The Add-Ons folder of Archicad <version> was not found` | Use the Add-On Manager with the `.bundle` the installer printed, as above. |
| `"tapir": null` | Restart Archicad. Check that `Add-Ons/Tapir` in the Archicad folder (usually `/Applications/GRAPHISOFT/Archicad <version>`) holds `TapirAddOn_AC<version>_Mac.bundle`. |
| No `archicad_*` tools after the restart | Check that `~/Library/Application Support/Claude/claude_desktop_config.json` has `mcpServers.archicad` with a `command` pointing to `~/.local/bin/archibridge` (written in full). The server's log is `~/Library/Logs/Claude/mcp-server-archicad.log`. |

### Both systems

| Symptom | Fix |
|---|---|
| A Tapir download fails, or its hash doesn't match | Don't bypass the check. Run the installer again. If it keeps failing, the network may block GitHub. |
| `doctor` lists nothing | Archicad isn't running, or it's older than version 25. |
| `doctor` shows `busy` | Close the open dialog in Archicad. |
| "needs the Tapir add-on" | Same as `"tapir": null` above. `API.*` commands still work. |
| "Several Archicads are ready" | Pass `port`, or set the `ARCHIBRIDGE_PORT` environment variable in the MCP config. |
| Claude Desktop config is not valid JSON | The installer leaves it untouched and prints the entry to add. Fix the file it names, then run the installer again. |

## Uninstall

Windows:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -Command "irm https://bimspeak.com/archibridge/uninstall.ps1 | iex"
```

macOS:

```bash
curl -fsSL https://bimspeak.com/archibridge/uninstall.sh | bash
```

It removes the MCP registrations, the server and the downloaded Tapir files. Tapir stays in Archicad, because other tools can use it.

## Rules

- Check the operating system first, and run only the installer for it.
- Never run the installer as administrator on Windows, or with `sudo` on a Mac. Its only elevated step is the Tapir copy, which the system asks the user to approve.
- Don't change `ARCHIBRIDGE_POLICY` unless the user asks.
- Don't edit or remove other MCP servers in any config file.
- Don't install anything that this guide doesn't list.
- Don't run Tapir's own installers. `TapirInstaller_Win.exe` isn't code signed, and both ArchiBridge installers already add the add-on.
