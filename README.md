# ArchiBridge: Claude and ChatGPT connected to Archicad

Talk to your Archicad project. ArchiBridge connects Claude Desktop (free plan included), Claude Code and ChatGPT to the Archicad running on your computer, Windows or Mac, in one prompt.

It uses Archicad's own local JSON API and the open-source [Tapir](https://github.com/ENZYME-APD/tapir-archicad-automation) add-on. ArchiBridge adds the MCP server, the one-prompt install, the safety rules and the skills.

## What you get

- **The AI reads your open project**: stories, elements, properties, quantities, attributes, layouts.
- **The AI changes the project** through 426 Tapir commands: walls, slabs, roofs, doors, windows, zones, MEP routes and more. Your AI app asks you before each change.
- **The AI sees the result** with pictures of the 3D and 2D windows.
- **Skills**: a working method (metric units, staged builds, visual checks) and a read-only MEP review (open ports, elements outside a system, clashes).

## Supported platforms

| System | Status |
|---|---|
| Windows 10 or 11 | Supported, tested on Windows 11 |
| macOS 11 or newer, Apple silicon or Intel | Supported. The Mac installer has not been run on a real Mac yet: see [macOS](#macos) |

- Archicad 25 to 30. MEP commands need Archicad 28 or newer.
- Claude Desktop (free or paid), Claude Code, or the ChatGPT app with Codex.

## Tested with

Archicad 29.0.0 (build 3000, INT) and Tapir 1.7.3, on Windows 11: install, reading a project, creating walls, plan and 3D pictures, and undo. A single Ctrl+Z undid a whole `CreateWalls` call.

Other Archicad versions, other languages, macOS and the MEP review have not been tested yet.

## Install

### Option A: one prompt (Claude Pro or higher)

In Claude Desktop, open the **Code** tab (or start Claude Code), then paste:

```
Install ArchiBridge to connect Claude to my Archicad: https://github.com/ayoubmep/archibridge-mcp
Follow INSTALL.md step by step, then tell me what to do next.
```

Claude checks whether you use Windows or macOS and runs the matching installer. It asks for permission before each command. Your system also asks once, to copy Tapir into Archicad's folder: on Windows click **Yes**, on a Mac enter your password.

### Option B: one command (free plan, or without Claude Code)

**Windows**: open **PowerShell** (not as administrator) and paste:

```powershell
irm https://raw.githubusercontent.com/ayoubmep/archibridge-mcp/main/install.ps1 | iex
```

**macOS**: open **Terminal** (Applications > Utilities) and paste:

```bash
curl -fsSL https://raw.githubusercontent.com/ayoubmep/archibridge-mcp/main/install.sh | bash
```

### Then

1. Restart Archicad so it loads Tapir, then open a project.
2. Quit your AI app completely and open it again. For Claude Desktop on Windows: right-click the Claude icon near the clock, then **Quit**. On a Mac: **Claude > Quit Claude** (Cmd+Q).
3. Try one of the prompts below.

## Prompts to try

- "Read the archibridge skill, then describe my open Archicad project."
- "List the stories and count the elements of each type."
- "Create a 10 × 8 m house with 3 m walls on the ground floor, then show me a 3D picture."
- "Review my MEP model with the archicad-mep-review skill."
- "Select all the doors on this story and tell me their sizes."

## How it works

```
Claude / ChatGPT  <->  ArchiBridge MCP server  <->  Archicad JSON API + Tapir  <->  your project
```

Everything stays on your computer: the server only talks to Archicad on `127.0.0.1`. What the AI reads does go to the AI provider, as described below.

| Tool | Purpose |
|---|---|
| `archicad_instances` | List running Archicads and open projects |
| `archicad_search_commands` | Find a command |
| `archicad_command_schema` | Read a command's exact parameters |
| `archicad_read` | Run a command that changes nothing |
| `archicad_modify` | Run a command that changes the project |
| `archicad_view_image` | See the current window |
| `archicad_get_skill` | Read a working method |

## macOS

ArchiBridge has no Windows-only part. The server is plain Python that talks to Archicad's JSON API, which Archicad offers on both systems, and Tapir publishes Mac builds for Archicad 25 to 30, signed and notarized by its authors. The Mac installer, `install.sh`, does the same job as the Windows one, in Mac locations:

| What | Where on a Mac |
|---|---|
| uv, only if it is missing | `~/.local/bin/uv`, from astral.sh. It brings the server's own Python, so Homebrew, Python and Node are not needed. |
| The MCP server | `~/.local/bin/archibridge` |
| Tapir | `Add-Ons/Tapir` in each Archicad folder, usually `/Applications/GRAPHISOFT/Archicad <version>`. macOS asks for your password only if that folder belongs to an administrator. An existing Tapir is left as it is. |
| Claude Desktop | `~/Library/Application Support/Claude/claude_desktop_config.json`, backed up once before the first change |
| Claude Code | `claude mcp add --scope user archicad` |
| ChatGPT / Codex | `codex mcp add archicad`, or `~/.codex/config.toml` |
| Downloaded Tapir files | `~/Library/Application Support/ArchiBridge` |
| Install log | `~/Library/Logs/archibridge-install.log` |

What works on a Mac: everything listed under [What you get](#what-you-get), with Claude Desktop, Claude Code and ChatGPT / Codex.

What has not been tested: the Mac installer and the server have so far only been checked on Windows, with a simulated Mac and the real Tapir Mac files. Nobody has run them on a Mac with Archicad yet. If you do, please tell us how it went in an [issue](../../issues), with the install log.

Good to know:

- Archicad 25 is an Intel app, and so is Tapir's build for it: on Apple silicon both run through Rosetta. Archicad 26 to 30 and their Tapir builds run natively on Apple silicon and Intel.
- Use Cmd+Z in Archicad to undo what the AI did.

## Safety

- Reads and modifications are separate tools. Any command ArchiBridge doesn't recognise counts as a modification, so your AI app can ask you first. If you choose "always allow" for `archicad_modify`, it stops asking.
- `OpenProject`, `CloseProject`, `NewProject`, `QuitArchicad`, `TeamworkSend` and `TeamworkReceive` are refused by default.
- With several Archicads open, ArchiBridge refuses to guess which one to use.

Set the `ARCHIBRIDGE_POLICY` environment variable in your MCP config to change this:

| Value | Effect |
|---|---|
| `readonly` | Only reads run |
| `ask` | The default: reads and modifications run, restricted commands are refused |
| `full` | Restricted commands run too. Use it only if you accept the risk of lost work |

## Privacy

What the AI reads from your project (names, properties, results, pictures) is sent to the AI provider (Anthropic, OpenAI). Check your project's confidentiality rules before using it on real work, and try it first on a copy.

## Update

Run the install command again. It updates everything without duplicating anything.

## Uninstall

Windows, in PowerShell:

```powershell
irm https://raw.githubusercontent.com/ayoubmep/archibridge-mcp/main/uninstall.ps1 | iex
```

macOS, in Terminal:

```bash
curl -fsSL https://raw.githubusercontent.com/ayoubmep/archibridge-mcp/main/uninstall.sh | bash
```

Tapir stays in Archicad, because other tools can use it.

## Troubleshooting

| Problem | Solution |
|---|---|
| The AI doesn't see the `archicad_*` tools | Quit the app completely and reopen it. Windows: icon near the clock > Quit. Mac: Claude > Quit Claude (Cmd+Q). |
| "Archicad has no open project" | Open a project. Archicad's API answers only then. |
| "needs the Tapir add-on" | Restart Archicad. If it persists, run the installer again and accept the system prompt: **Yes** on Windows, your password on a Mac. |
| "Several Archicads are ready" | Tell the AI which project to use, or close one Archicad. |
| Commands time out | Archicad may be showing a dialog. Close it. |
| Something else | Open an [issue](../../issues) and attach the install log: `%TEMP%\archibridge-install.log` on Windows, `~/Library/Logs/archibridge-install.log` on a Mac. |

## Credits and license

- Tapir add-on: [Tapir Archicad Automation](https://github.com/ENZYME-APD/tapir-archicad-automation), by Enzyme APD (MIT license). See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
- ArchiBridge: MIT license, see [LICENSE](LICENSE).

ArchiBridge is an independent project, not affiliated with Graphisoft.
