#!/bin/bash
# ArchiBridge uninstaller for macOS (the Windows uninstaller is uninstall.ps1)
#
# Removes the archicad MCP connection from your AI apps, the ArchiBridge server and the
# downloaded Tapir files. Archicad, the Tapir add-on inside it and your projects are not touched.
#
#     curl -fsSL https://raw.githubusercontent.com/ayoubmep/archibridge-mcp/main/uninstall.sh | bash
#
# Keep this file ASCII-only and compatible with the bash 3.2 that ships with macOS.

MCP_NAME=archicad

ok() { printf '[OK] %s\n' "$1"; }
note() { printf '[!!] %s\n' "$1"; }

# Finds a command on PATH, or where its installers usually put it.
find_tool() {
    local found folder
    found=$(type -P "$1" 2>/dev/null)
    if [ -n "$found" ]; then
        printf '%s\n' "$found"
        return 0
    fi
    for folder in "$HOME/.local/bin" "$HOME/.cargo/bin" "$HOME/.claude/local" "$HOME/.npm-global/bin" /opt/homebrew/bin /usr/local/bin; do
        if [ -x "$folder/$1" ]; then
            printf '%s\n' "$folder/$1"
            return 0
        fi
    done
    return 1
}

# A Python to edit the JSON config: the server's own first, because it is removed last.
find_python() {
    local uv=$1 tool_dir candidate
    if [ -n "$uv" ]; then
        tool_dir=$("$uv" tool dir 2>/dev/null)
        for candidate in "$tool_dir/archibridge/bin/python3" "$tool_dir/archibridge/bin/python"; do
            if [ -n "$tool_dir" ] && [ -x "$candidate" ]; then
                printf '%s\n' "$candidate"
                return 0
            fi
        done
        candidate=$("$uv" python find 2>/dev/null)
        if [ -n "$candidate" ] && [ -x "$candidate" ]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    fi
    # /usr/bin/python3 is only a stub that offers to install Xcode tools when they are missing.
    if xcode-select -p >/dev/null 2>&1 && [ -x /usr/bin/python3 ]; then
        printf '%s\n' /usr/bin/python3
        return 0
    fi
    return 1
}

# Sets CONFIG_HELPER to a script that removes the entry from the JSON and TOML configs.
write_config_helper() {
    local folder=${TMPDIR:-/tmp}
    CONFIG_HELPER=$(mktemp "${folder%/}/archibridge-config.XXXXXX") || return 1
    cat > "$CONFIG_HELPER" <<'PYTHON'
import json
import os
import re
import sys


def note(text):
    print('[!!] ' + text)


def read(path):
    if not os.path.exists(path):
        return ''
    with open(path, encoding='utf-8-sig') as file:
        return file.read()


def write(path, text):
    with open(path, 'w', encoding='utf-8', newline='\n') as file:
        file.write(text)


def desktop_remove(path, name):
    """Removes mcpServers.<name> from a Claude Desktop config. Returns 10 when it isn't there."""
    raw = read(path)
    if not raw.strip():
        return 10
    try:
        config = json.loads(raw)
    except ValueError:
        note('%s is not valid JSON, left untouched.' % path)
        return 2
    servers = config.get('mcpServers') if isinstance(config, dict) else None
    if not isinstance(servers, dict) or name not in servers:
        return 10
    del servers[name]
    write(path, json.dumps(config, indent=2, ensure_ascii=False) + '\n')
    return 0


def codex_remove(path, name):
    """Removes [mcp_servers.<name>] and its sub-tables from Codex's config.toml."""
    text = read(path)
    pattern = r'(?ms)^\s*\[mcp_servers\.' + re.escape(name) + r'(\.[^\]\n]*)?\].*?(?=^\s*\[|\Z)'
    cleaned = re.sub(pattern, '', text)
    if cleaned == text:
        return 10
    write(path, cleaned)
    return 0


ACTIONS = {'desktop-remove': desktop_remove, 'codex-remove': codex_remove}

if __name__ == '__main__':
    try:
        sys.exit(ACTIONS[sys.argv[1]](*sys.argv[2:]))
    except Exception as error:
        note('Could not update %s: %s' % (sys.argv[2], error))
        sys.exit(1)
PYTHON
}

uninstall_archibridge() {
    local claude_cli codex_cli uv python desktop_config codex_config folder

    echo ""
    echo "ArchiBridge uninstaller"
    echo ""

    if [ "$(uname -s)" != "Darwin" ]; then
        printf '[XX] %s\n' "This uninstaller is for macOS. On Windows, run this in PowerShell:"
        echo "     irm https://raw.githubusercontent.com/ayoubmep/archibridge-mcp/main/uninstall.ps1 | iex"
        return 1
    fi
    if [ -z "$HOME" ]; then
        printf '[XX] %s\n' "HOME is not set."
        return 1
    fi

    claude_cli=$(find_tool claude)
    if [ -n "$claude_cli" ] && "$claude_cli" mcp remove --scope user "$MCP_NAME" >/dev/null 2>&1; then
        ok "Claude Code: removed."
    fi

    uv=$(find_tool uv)
    python=$(find_python "$uv")
    if [ -n "$python" ] && ! write_config_helper; then
        python=""
    fi

    desktop_config="$HOME/Library/Application Support/Claude/claude_desktop_config.json"
    if [ -f "$desktop_config" ]; then
        if [ -n "$python" ]; then
            if "$python" -I "$CONFIG_HELPER" desktop-remove "$desktop_config" "$MCP_NAME"; then
                ok "Claude Desktop: removed from $desktop_config"
            fi
        elif grep -q "\"$MCP_NAME\"" "$desktop_config" 2>/dev/null; then
            note "No Python found to edit $desktop_config. Remove \"$MCP_NAME\" from its \"mcpServers\" by hand."
        fi
    fi

    codex_cli=$(find_tool codex)
    codex_config="$HOME/.codex/config.toml"
    if [ -n "$codex_cli" ]; then
        if "$codex_cli" mcp remove "$MCP_NAME" >/dev/null 2>&1; then
            ok "Codex: removed."
        fi
    elif [ -f "$codex_config" ]; then
        if [ -n "$python" ]; then
            if "$python" -I "$CONFIG_HELPER" codex-remove "$codex_config" "$MCP_NAME"; then
                ok "ChatGPT / Codex: removed from .codex/config.toml"
            fi
        elif grep -q "^\[mcp_servers\.$MCP_NAME" "$codex_config" 2>/dev/null; then
            note "No Python found to edit $codex_config. Remove its [mcp_servers.$MCP_NAME] section by hand."
        fi
    fi
    if [ -n "$python" ]; then
        rm -f "$CONFIG_HELPER"
    fi

    if [ -n "$uv" ] && "$uv" tool uninstall archibridge >/dev/null 2>&1; then
        ok "ArchiBridge server: removed."
    fi

    folder="$HOME/Library/Application Support/ArchiBridge"
    if [ -d "$folder" ] && rm -rf "$folder"; then
        ok "Removed $folder"
    fi
    note "Tapir stays in Archicad, because other tools can use it. To remove it, delete the Tapir folder in Archicad's Add-Ons folder."
    echo ""
}

# Nothing reads the terminal: when the script comes from curl, the rest of it would be read as input.
uninstall_archibridge < /dev/null
exit $?
