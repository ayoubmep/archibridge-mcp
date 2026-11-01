# ArchiBridge: Claude and ChatGPT connected to Archicad

Talk to your Archicad project. ArchiBridge connects Claude Desktop (free plan included), Claude Code and ChatGPT to the Archicad running on your PC, in one prompt.

It uses Archicad's own local JSON API and the open-source [Tapir](https://github.com/ENZYME-APD/tapir-archicad-automation) add-on. ArchiBridge adds the MCP server, the one-prompt install, the safety rules and the skills.

## What you get

- **The AI reads your open project**: stories, elements, properties, quantities, attributes, layouts.
- **The AI changes the project** through 426 Tapir commands: walls, slabs, roofs, doors, windows, zones, MEP routes and more. Your AI app asks you before each change.
- **The AI sees the result** with pictures of the 3D and 2D windows.
- **Skills**: a working method (metric units, staged builds, visual checks) and a read-only MEP review (open ports, elements outside a system, clashes).

## Requirements

- Windows 10 or 11, Archicad 25 to 30
- Claude Desktop (free or paid), Claude Code, or the ChatGPT app with Codex

MEP commands need Archicad 28 or newer.

## Install

### Option A: one prompt (Claude Pro or higher)

In Claude Desktop, open the **Code** tab (or start Claude Code), then paste:

```
Install ArchiBridge to connect Claude to my Archicad: https://github.com/ayoubmep/archibridge-mcp
Follow INSTALL.md step by step, then tell me what to do next.
```

Claude asks for permission before each command.

### Option B: one command (free plan, or without Claude Code)

Open **PowerShell** (not as administrator) and paste:

```powershell
irm https://raw.githubusercontent.com/ayoubmep/archibridge-mcp/main/install.ps1 | iex
```

### Then

1. In Archicad, open a project. Add Tapir once: **Options > Add-On Manager > Edit List of Available Add-Ons > Add**, then choose the `.apx` file the installer printed.
2. Quit your AI app completely and open it again. For Claude Desktop: right-click the Claude icon near the clock, then **Quit**.
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

Everything stays on your PC: the server only talks to Archicad on `127.0.0.1`. What the AI reads does go to the AI provider, as described below.

| Tool | Purpose |
|---|---|
| `archicad_instances` | List running Archicads and open projects |
| `archicad_search_commands` | Find a command |
| `archicad_command_schema` | Read a command's exact parameters |
| `archicad_read` | Run a command that changes nothing |
| `archicad_modify` | Run a command that changes the project |
| `archicad_view_image` | See the current window |
| `archicad_get_skill` | Read a working method |

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

First remove Tapir in Archicad's Add-On Manager, then run:

```powershell
irm https://raw.githubusercontent.com/ayoubmep/archibridge-mcp/main/uninstall.ps1 | iex
```

## Troubleshooting

| Problem | Solution |
|---|---|
| The AI doesn't see the `archicad_*` tools | Quit the app completely (icon near the clock > Quit) and reopen it. |
| "Archicad has no open project" | Open a project. Archicad's API answers only then. |
| "needs the Tapir add-on" | Add Tapir in the Add-On Manager, see [Then](#then). |
| "Several Archicads are ready" | Tell the AI which project to use, or close one Archicad. |
| Commands time out | Archicad may be showing a dialog. Close it. |
| Something else | Open an [issue](../../issues) and attach `%TEMP%\archibridge-install.log`. |

## Credits and license

- Tapir add-on: [Tapir Archicad Automation](https://github.com/ENZYME-APD/tapir-archicad-automation), by Enzyme APD (MIT license). See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
- ArchiBridge: MIT license, see [LICENSE](LICENSE).

ArchiBridge is an independent project, not affiliated with Graphisoft.
