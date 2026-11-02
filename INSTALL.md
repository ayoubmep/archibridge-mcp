# ArchiBridge: install guide for AI agents

This file is for an AI agent (Claude Code, Codex, or similar) asked to install ArchiBridge on the user's Windows PC. Follow it step by step and keep the user informed in their own language.

## What gets installed

- **uv**, only if it is missing. It installs the server and its own Python, and touches no existing Python.
- **The ArchiBridge MCP server**, as a uv tool (`archibridge.exe`).
- **The Tapir add-on** for each Archicad version found, from the official Tapir GitHub release, checked against a pinned SHA-256 hash. It goes in `<Archicad>\Add-Ons\Tapir`, the same place Tapir's own installer uses, so Archicad loads it at startup. An existing Tapir is left as it is.
- **The `archicad` MCP server entry**, registered with Claude Desktop, and with Claude Code and Codex / ChatGPT when they are installed.

The installer never changes other MCP servers. It backs up the Claude Desktop config (`claude_desktop_config.json.archibridge-backup`) before editing it.

## Step 1. Tell the user two things

1. Windows shows one permission prompt, to copy Tapir into Program Files. The user should click **Yes**. You can't answer it for them, and the installer waits for it.
2. Archicad can stay open during the install, but it must be restarted afterwards to load Tapir. Ask the user to save their work first.

## Step 2. Run the installer

Run this in PowerShell as the normal user, not as administrator. Give the command a long timeout (10 minutes):

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/ayoubmep/archibridge-mcp/main/install.ps1 | iex"
```

Read the whole output:

- `[OK]` a step worked.
- `[..]` a step is running.
- `[!!]` a warning. Read it: some need the user.
- `[XX]` an error. The installer stopped. Fix the cause (see Troubleshooting), then run the same command again. Running it twice is safe.

The installer saves a full log to `%TEMP%\archibridge-install.log`.

## Step 3. Check the result

Ask the user to restart Archicad and open a project, then run:

```powershell
& "$(uv tool dir --bin)\archibridge.exe" doctor
```

It prints every running Archicad as JSON. Each one has a `status`:

| Status | Meaning |
|---|---|
| `ready` | A project is open. |
| `no_project` | Archicad is open but no project is. Ask the user to open one. |
| `busy` | A dialog is open, or Archicad is working. |

An empty `instances` list means Archicad is not running.

`"tapir"` must show a version. `null` means the add-on is not loaded, and only Archicad's 73 built-in commands work. See Troubleshooting.

## Step 4. Tell the user what to do next

1. Quit the AI app completely and open it again, so it loads the new MCP server.
   - Claude Desktop: right-click the Claude icon near the clock, then **Quit**.
   - Claude Code: start a new session.
   - ChatGPT desktop app: quit and reopen it.
2. In a new chat, try: "Read the archibridge skill, then describe my open Archicad project."
3. When the AI changes the model, the AI app asks for approval first, unless the user has told it to always allow the `archicad_modify` tool.

You are probably running in the session that did the install: the `archicad_*` tools only appear after the restart.

## Troubleshooting

| Symptom | Fix |
|---|---|
| `[XX] The server could not be installed` | The AI app may be running the old server. Quit it and run the installer again from a PowerShell window. |
| A Tapir download fails, or its hash doesn't match | Don't bypass the check. Run the installer again. If it keeps failing, the network may block GitHub. |
| `doctor` lists nothing | Archicad isn't running, or it's older than version 25. |
| `doctor` shows `busy` | Close the open dialog in Archicad. |
| `Tapir was not added` | The Windows prompt was refused or failed. Run the installer again and have the user click **Yes**. If that isn't possible, the user can add the `.apx` the installer printed in Archicad: **Options > Add-On Manager > Edit List of Available Add-Ons > Add**. |
| `"tapir": null` | Restart Archicad. Check that `<Archicad>\Add-Ons\Tapir` holds the `.apx` for that Archicad version. |
| "needs the Tapir add-on" | Same as above. `API.*` commands still work. |
| "Several Archicads are ready" | Pass `port`, or set the `ARCHIBRIDGE_PORT` environment variable in the MCP config. |
| No `archicad_*` tools after the restart | Check that the Claude Desktop config has `mcpServers.archicad` with a `command` pointing to `archibridge.exe`. The config is either `%LOCALAPPDATA%\Claude-Data\<profile>\claude_desktop_config.json` or `%APPDATA%\Claude\claude_desktop_config.json`. The server's log, `mcp-server-archicad.log`, is in the `logs` folder beside it. |
| Claude Desktop config is not valid JSON | The installer leaves it untouched and prints the entry to add. Fix the file it names, then run the installer again. |

## Uninstall

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/ayoubmep/archibridge-mcp/main/uninstall.ps1 | iex"
```

It removes the MCP registrations, the server and the downloaded Tapir files. Tapir stays in Archicad, because other tools can use it.

## Rules

- Never run the installer as administrator. Its only elevated step is the Tapir copy, which Windows asks the user to approve.
- Don't change `ARCHIBRIDGE_POLICY` unless the user asks.
- Don't edit or remove other MCP servers in any config file.
- Don't install anything that this guide doesn't list.
- Don't run `TapirInstaller_Win.exe`: it isn't code signed, and this installer already adds the `.apx`.
