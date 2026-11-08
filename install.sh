#!/bin/bash
# ArchiBridge installer for macOS (the Windows installer is install.ps1)
#
# Connects Claude Desktop (free plan included), Claude Code and ChatGPT / Codex to Archicad
# through a local MCP server, and installs the Tapir add-on that gives it full model access.
#
# Run it in Terminal as your normal user, not with sudo. If Archicad's Add-Ons folder belongs
# to an administrator, macOS asks once for a password to copy Tapir into it.
#
#     curl -fsSL https://raw.githubusercontent.com/ayoubmep/archibridge-mcp/main/install.sh | bash
#
# Running it again is safe: it updates everything without duplicating it.
# It needs nothing but macOS: uv, installed if missing, brings the server's own Python.
#
# Optional environment variables, set before running:
#     ARCHIBRIDGE_REPO     GitHub repo to install from (default ayoubmep/archibridge-mcp)
#     ARCHIBRIDGE_BRANCH   Branch to install from (default main)
#
# Keep this file ASCII-only and compatible with the bash 3.2 that ships with macOS:
# no associative arrays, no mapfile, no ${var,,}, no empty "${array[@]}".

REPO=${ARCHIBRIDGE_REPO:-ayoubmep/archibridge-mcp}
BRANCH=${ARCHIBRIDGE_BRANCH:-main}
MCP_NAME=archicad
PYTHON_VERSION=3.12
TAPIR_VERSION=1.7.3
# Only tests change this. Archicad itself is always installed under /Applications.
APPLICATIONS=${ARCHIBRIDGE_APPLICATIONS:-/Applications}
SCRIPT_FILE=${BASH_SOURCE[0]:-}
TAB=$(printf '\t')
LOG_FILE="$HOME/Library/Logs/archibridge-install.log"

# SHA-256 of TapirAddOn_AC<version>_Mac.zip in the Tapir release, from the release's asset digests.
tapir_hash() {
    case "$1" in
        25) echo 2c3df1579fca4d1107712d0ae31f894c488e71d13d9b38e524b971a1936cc412 ;;
        26) echo d6cfc444884bdc1096da87d65d5d8191a8e7f27e06615c043735ead0a4a72a8b ;;
        27) echo 58120fd8f0c36d2d3c548e61b1d498a142e0ca6c28441f3f295f6ab6a22cc609 ;;
        28) echo c03264347a4903caf1f4c79f2dae42656edb89aafd90fb523a1a0bc8bd6c4c51 ;;
        29) echo 7fb41baf3d4e75b0bd479a0f4893cfe77377a913b0ef58952866633824514e9a ;;
        30) echo 1476bd5006d1aa716fbb97ae77cfdd0c0298bfe545726998ff5facd93dbcfb62 ;;
        *) return 1 ;;
    esac
}

step() { printf '[..] %s\n' "$1"; }
ok() { printf '[OK] %s\n' "$1"; }
note() { printf '[!!] %s\n' "$1"; }
fail() { printf '[XX] %s\n' "$1"; }

# Runs a program, shows its output indented, returns its exit code.
run_indented() {
    local output status
    output=$("$@" 2>&1)
    status=$?
    if [ -n "$output" ]; then
        printf '%s\n' "$output" | sed -e '/^[[:space:]]*$/d' -e 's/^/     /'
    fi
    return $status
}

lowercase() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

# Quotes a value for a shell command line.
shell_quote() { printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"; }

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

# A local clone installs from its own folder, the one-line install from GitHub.
package_source() {
    local folder
    if [ -n "$SCRIPT_FILE" ] && [ -f "$SCRIPT_FILE" ]; then
        folder=$(cd "$(dirname "$SCRIPT_FILE")" 2>/dev/null && pwd -P)
        if [ -n "$folder" ] && [ -f "$folder/pyproject.toml" ]; then
            printf '%s\n' "$folder"
            return
        fi
    fi
    printf 'https://github.com/%s/archive/refs/heads/%s.zip\n' "$REPO" "$BRANCH"
}

sha256_of() {
    if type -P shasum >/dev/null 2>&1; then
        shasum -a 256 "$1" 2>/dev/null | awk '{ print $1 }'
    else
        openssl dgst -sha256 -r "$1" 2>/dev/null | awk '{ print $1 }'
    fi
}

has_archicad_app() {
    local app
    for app in "$1"/*.app; do
        [ -d "$app" ] || continue
        case "$(lowercase "${app##*/}")" in
            *archicad*) return 0 ;;
        esac
    done
    return 1
}

# Archicad goes in /Applications/GRAPHISOFT/Archicad <version> by default, with the Archicad
# app and its Add-Ons folder inside. Like Tapir's own installer, this looks in /Applications
# and one folder below it. Prints one line per installation: version, tab, folder.
find_archicads() {
    local parent folder name version real seen="" pattern='archicad[[:space:]]+([0-9]+)'
    for parent in "$APPLICATIONS" "$APPLICATIONS"/*; do
        [ -d "$parent" ] || continue
        case "$parent" in *.app) continue ;; esac
        for folder in "$parent"/*; do
            [ -d "$folder" ] || continue
            case "$folder" in *.app) continue ;; esac
            name=$(lowercase "${folder##*/}")
            [[ $name =~ $pattern ]] || continue
            version=${BASH_REMATCH[1]}
            tapir_hash "$version" >/dev/null || continue
            has_archicad_app "$folder" || continue
            real=$(cd "$folder" 2>/dev/null && pwd -P) || continue
            case "$seen" in *"|$real|"*) continue ;; esac
            seen="$seen|$real|"
            printf '%s\t%s\n' "$version" "$folder"
        done
    done
}

# The Add-Ons folder's name depends on Archicad's language. As in Tapir's own installer, a
# known name comes first, then the folder that holds XReadCfg.txt, which is how Graphisoft
# says to find it in every language. Names with accents are found that second way.
find_addons_folder() {
    local install=$1 entry name file relative depth best="" best_depth=99
    for entry in "$install"/*; do
        [ -d "$entry" ] || continue
        case "$entry" in *.app) continue ;; esac
        name=$(lowercase "${entry##*/}")
        case "$name" in
            add-ons | extensions | dodatki | "doplnky archicadu" | archicad-laajennukset | "extensiones archicad" | "add-on'lar")
                printf '%s\n' "$entry"
                return 0
                ;;
        esac
    done
    for entry in "$install"/*; do
        [ -d "$entry" ] && [ ! -L "$entry" ] || continue
        case "$entry" in *.app) continue ;; esac
        while IFS= read -r file; do
            [ -n "$file" ] || continue
            relative=${file#"$entry"/}
            depth=$(printf '%s' "$relative" | tr -cd '/' | wc -c | tr -d ' ')
            if [ "$depth" -lt "$best_depth" ]; then
                best_depth=$depth
                best=$entry
            fi
        done <<EOF
$(find "$entry" -maxdepth 3 -iname 'XReadCfg.txt' 2>/dev/null)
EOF
    done
    if [ -n "$best" ]; then
        printf '%s\n' "$best"
    fi
}

# Downloads the add-on for one Archicad version and checks it against the pinned hash.
# Sets TAPIR_ZIP, or TAPIR_ERROR when it fails.
get_tapir_addon() {
    local version=$1 folder=$2 name expected url output
    TAPIR_ZIP=""
    TAPIR_ERROR=""
    name="TapirAddOn_AC${version}_Mac.zip"
    expected=$(tapir_hash "$version")
    if [ -f "$folder/$name" ] && [ "$(sha256_of "$folder/$name")" = "$expected" ]; then
        TAPIR_ZIP="$folder/$name"
        return 0
    fi
    if ! mkdir -p "$folder" 2>/dev/null; then
        TAPIR_ERROR="could not create $folder"
        return 1
    fi
    url="https://github.com/ENZYME-APD/tapir-archicad-automation/releases/download/$TAPIR_VERSION/$name"
    step "Downloading $name..."
    if ! output=$(curl -fsSL --retry 2 -o "$folder/$name" "$url" 2>&1); then
        rm -f "$folder/$name"
        TAPIR_ERROR=${output:-the download from GitHub failed.}
        return 1
    fi
    if [ "$(sha256_of "$folder/$name")" != "$expected" ]; then
        rm -f "$folder/$name"
        TAPIR_ERROR="$name does not match its expected SHA-256 hash."
        return 1
    fi
    TAPIR_ZIP="$folder/$name"
}

tapir_present() {
    [ -n "$(find "$1" -maxdepth 4 -iname 'TapirAddOn_*.bundle' 2>/dev/null)" ]
}

# Archicad loads what is in its Add-Ons folder, which is where Tapir's own installer puts it.
# The copy runs as the user when the folder allows it, otherwise macOS asks for a password,
# as with Tapir's own installer. An existing Tapir is never replaced: it may be newer.
# Sets TAPIR_STATE: present, installed, declined or failed.
install_tapir_addon() {
    local zip=$1 addons=$2 version=$3 tapir bundle command output
    tapir="$addons/Tapir"
    bundle="$tapir/TapirAddOn_AC${version}_Mac.bundle"
    if tapir_present "$addons"; then
        TAPIR_STATE=present
        return
    fi
    if ! { mkdir -p "$tapir" 2>/dev/null && ditto -x -k "$zip" "$tapir" 2>/dev/null; }; then
        command="mkdir -p $(shell_quote "$tapir") && /usr/bin/ditto -x -k $(shell_quote "$zip") $(shell_quote "$tapir")"
        if ! output=$(osascript -e 'on run argv' \
            -e 'do shell script (item 1 of argv) with prompt (item 2 of argv) with administrator privileges' \
            -e 'end run' "$command" "ArchiBridge is adding the Tapir add-on to Archicad $version." 2>&1); then
            case "$output" in
                *-128* | *[Cc]ancel*) TAPIR_STATE=declined ;;
                *) TAPIR_STATE=failed ;;
            esac
            return
        fi
    fi
    if [ -f "$bundle/Contents/MacOS/TapirAddOn_AC${version}_Mac" ]; then
        TAPIR_STATE=installed
    else
        TAPIR_STATE=failed
    fi
}

# Archicad's Add-On Manager needs the bundle itself, so the download is unzipped beside it.
manual_bundle() {
    local zip=$1 version=$2 folder bundle
    folder=${zip%.zip}
    bundle="$folder/TapirAddOn_AC${version}_Mac.bundle"
    if [ -n "$folder" ] && [ "$folder" != "$zip" ] && [ ! -d "$bundle" ]; then
        rm -rf "$folder"
        mkdir -p "$folder" && ditto -x -k "$zip" "$folder" >/dev/null 2>&1
    fi
    if [ -d "$bundle" ]; then
        printf '%s\n' "$bundle"
    else
        printf '%s\n' "$zip"
    fi
}

archicad_running() {
    pgrep -i -f 'archicad[^/]*\.app/contents/macos/' >/dev/null 2>&1
}

# Claude Desktop's config is JSON, which bash can't edit safely. The server's own Python,
# installed by uv just before, does it. Sets CONFIG_HELPER.
write_config_helper() {
    local folder=${TMPDIR:-/tmp}
    CONFIG_HELPER=$(mktemp "${folder%/}/archibridge-config.XXXXXX") || return 1
    cat > "$CONFIG_HELPER" <<'PYTHON'
import json
import os
import re
import shutil
import sys


def note(text):
    print('[!!] ' + text)


def read(path):
    if not os.path.exists(path):
        return ''
    with open(path, encoding='utf-8-sig') as file:
        return file.read()


def write(path, text):
    folder = os.path.dirname(path)
    if folder:
        os.makedirs(folder, exist_ok=True)
    with open(path, 'w', encoding='utf-8', newline='\n') as file:
        file.write(text)


def desktop_add(path, name, command):
    """Adds or updates mcpServers.<name> in a Claude Desktop config, keeping everything else."""
    raw = read(path)
    config = {}
    if raw.strip():
        try:
            config = json.loads(raw)
        except ValueError:
            entry = json.dumps({name: {'command': command}})[1:-1]
            note('%s is not valid JSON, left untouched. Add this under "mcpServers" by hand: %s' % (path, entry))
            return 2
        if not isinstance(config, dict) or not isinstance(config.get('mcpServers') or {}, dict):
            note('%s has an unexpected format, left untouched.' % path)
            return 2
        # Keep the user's original config: back it up only once.
        backup = path + '.archibridge-backup'
        if not os.path.exists(backup):
            shutil.copyfile(path, backup)
    if not isinstance(config.get('mcpServers'), dict):
        config['mcpServers'] = {}
    config['mcpServers'][name] = {'command': command}
    write(path, json.dumps(config, indent=2, ensure_ascii=False) + '\n')
    return 0


def codex_add(path, name, command):
    """Adds [mcp_servers.<name>] to Codex's config.toml. Returns 10 when it is already there."""
    text = read(path)
    if re.search(r'(?m)^\s*\[mcp_servers\.' + re.escape(name) + r'\]', text):
        return 10
    if "'" in command:
        value = '"' + command.replace('\\', '\\\\').replace('"', '\\"') + '"'
    else:
        value = "'" + command + "'"
    if text and not text.endswith('\n'):
        text += '\n'
    if text:
        text += '\n'
    write(path, text + '[mcp_servers.%s]\ncommand = %s\n' % (name, value))
    return 0


ACTIONS = {'desktop-add': desktop_add, 'codex-add': codex_add}

if __name__ == '__main__':
    try:
        sys.exit(ACTIONS[sys.argv[1]](*sys.argv[2:]))
    except Exception as error:
        note('Could not update %s: %s' % (sys.argv[2], error))
        sys.exit(1)
PYTHON
}

install_archibridge() {
    local archicads versions version install addons uv package bin server tool_dir candidate python
    local tapir_folder tapir_manual="" tapir_added=0 configured="" claude_cli codex_cli
    local desktop_folder desktop_config desktop_found=0 desktop_done=0 state

    echo ""
    echo "ArchiBridge installer: Claude and ChatGPT connected to Archicad"
    echo ""

    if [ "$(uname -s)" != "Darwin" ]; then
        fail "This installer is for macOS, and Archicad runs only on macOS and Windows. On Windows, run this in PowerShell:"
        echo "     irm https://raw.githubusercontent.com/$REPO/$BRANCH/install.ps1 | iex"
        return 1
    fi
    if [ "$(id -u)" = "0" ]; then
        fail "This runs as root (sudo). Run the installer again without sudo, so everything is set up for your own account."
        return 1
    fi
    ok "macOS $(sw_vers -productVersion 2>/dev/null) on $(uname -m)"

    # 1. Archicad
    archicads=$(find_archicads | sort -n)
    if [ -n "$archicads" ]; then
        versions=$(printf '%s\n' "$archicads" | cut -f1 | tr '\n' ',' | sed -e 's/,$//' -e 's/,/, /g')
        ok "Archicad found: $versions"
    else
        note "No Archicad 25 to 30 found in /Applications. Continuing: the connection will work once one is installed."
    fi

    # 2. uv, which installs the server and its own Python
    uv=$(find_tool uv)
    if [ -z "$uv" ]; then
        step "Installing uv from astral.sh (the tool that runs the ArchiBridge server)..."
        run_indented sh -c 'curl -LsSf https://astral.sh/uv/install.sh | sh'
        uv=$(find_tool uv)
        if [ -z "$uv" ]; then
            fail "uv could not be installed. Install it from https://docs.astral.sh/uv/, then run this installer again."
            return 1
        fi
    fi
    ok "uv found: $uv"

    # 3. The MCP server
    package=$(package_source)
    step "Installing the ArchiBridge server from $package..."
    # A Mac has no compiler unless Xcode's tools are installed, so the dependencies with compiled
    # code may only come as ready-made builds: uv then picks the newest version that has one for
    # this Mac. For example, cryptography 49 and later have none for Intel Macs.
    if ! run_indented "$uv" tool install --force --reinstall --refresh --python "$PYTHON_VERSION" \
        --no-build-package cryptography --no-build-package cffi \
        --no-build-package pydantic-core --no-build-package rpds-py "$package"; then
        fail "The server could not be installed. Read the uv output above, then run this installer again."
        return 1
    fi
    bin=$("$uv" tool dir --bin 2>/dev/null)
    server="$bin/archibridge"
    if [ -z "$bin" ] || [ ! -x "$server" ]; then
        fail "The server is missing from $server."
        return 1
    fi
    ok "Server installed: $server"
    tool_dir=$("$uv" tool dir 2>/dev/null)
    python=""
    for candidate in "$tool_dir/archibridge/bin/python3" "$tool_dir/archibridge/bin/python"; do
        if [ -n "$tool_dir" ] && [ -x "$candidate" ]; then
            python=$candidate
            break
        fi
    done

    # 4. Tapir add-on
    tapir_folder="$HOME/Library/Application Support/ArchiBridge/Tapir/$TAPIR_VERSION"
    while IFS="$TAB" read -r version install <&3; do
        [ -n "$version" ] || continue
        if ! get_tapir_addon "$version" "$tapir_folder"; then
            note "Could not get Tapir for Archicad $version: $TAPIR_ERROR"
            continue
        fi
        addons=$(find_addons_folder "$install")
        if [ -z "$addons" ]; then
            note "The Add-Ons folder of Archicad $version was not found."
            tapir_manual="$tapir_manual$(manual_bundle "$TAPIR_ZIP" "$version")
"
            continue
        fi
        step "Adding Tapir to Archicad $version. macOS asks for your password if its Add-Ons folder needs it."
        install_tapir_addon "$TAPIR_ZIP" "$addons" "$version"
        state=$TAPIR_STATE
        if [ "$state" = "present" ]; then
            ok "Tapir is already in Archicad $version: left as it is."
        elif [ "$state" = "installed" ]; then
            ok "Tapir $TAPIR_VERSION added to Archicad $version, from a download with a verified hash."
            tapir_added=1
        else
            note "Tapir was not added to Archicad $version ($state)."
            tapir_manual="$tapir_manual$(manual_bundle "$TAPIR_ZIP" "$version")
"
        fi
    done 3<<EOF
$archicads
EOF

    # 5. MCP clients
    if ! write_config_helper; then
        CONFIG_HELPER=""
    fi

    claude_cli=$(find_tool claude)
    if [ -n "$claude_cli" ]; then
        step "Registering the archicad MCP server with Claude Code..."
        "$claude_cli" mcp remove --scope user "$MCP_NAME" >/dev/null 2>&1
        if run_indented "$claude_cli" mcp add --scope user "$MCP_NAME" -- "$server"; then
            ok "Claude Code: done (user scope)."
            configured="$configured, Claude Code"
        else
            note "Claude Code registration failed. Try later: claude mcp add --scope user $MCP_NAME -- \"$server\""
        fi
    else
        note "Claude Code command not found: skipped (normal if you only use Claude Desktop)."
    fi

    desktop_folder="$HOME/Library/Application Support/Claude"
    desktop_config="$desktop_folder/claude_desktop_config.json"
    if [ -d "$APPLICATIONS/Claude.app" ] || [ -d "$HOME/Applications/Claude.app" ] || [ -d "$desktop_folder" ]; then
        desktop_found=1
    fi
    if [ -n "$python" ] && [ -n "$CONFIG_HELPER" ]; then
        if "$python" -I "$CONFIG_HELPER" desktop-add "$desktop_config" "$MCP_NAME" "$server"; then
            ok "Claude Desktop: $desktop_config"
            desktop_done=1
        fi
    else
        note "Could not update $desktop_config. Add this under \"mcpServers\" by hand: \"$MCP_NAME\": { \"command\": \"$server\" }"
    fi
    if [ "$desktop_done" = 1 ] && [ "$desktop_found" = 1 ]; then
        configured="$configured, Claude Desktop"
    elif [ "$desktop_done" = 1 ]; then
        note "Claude Desktop is not installed yet: its config is ready for when you install it (claude.ai/download)."
    fi

    codex_cli=$(find_tool codex)
    if [ -n "$codex_cli" ]; then
        step "Registering the archicad MCP server with Codex (ChatGPT)..."
        "$codex_cli" mcp remove "$MCP_NAME" >/dev/null 2>&1
        if run_indented "$codex_cli" mcp add "$MCP_NAME" -- "$server"; then
            ok "Codex / ChatGPT: done."
            configured="$configured, ChatGPT / Codex"
        else
            note "Codex registration failed. Try later: codex mcp add $MCP_NAME -- \"$server\""
        fi
    elif [ -d "$HOME/.codex" ]; then
        if [ -n "$python" ] && [ -n "$CONFIG_HELPER" ]; then
            "$python" -I "$CONFIG_HELPER" codex-add "$HOME/.codex/config.toml" "$MCP_NAME" "$server"
            state=$?
            if [ "$state" = 0 ]; then
                ok "ChatGPT / Codex: added to .codex/config.toml"
                configured="$configured, ChatGPT / Codex"
            elif [ "$state" = 10 ]; then
                ok "ChatGPT / Codex: already configured."
                configured="$configured, ChatGPT / Codex"
            fi
        else
            note "Could not update .codex/config.toml. Add this to it by hand: [mcp_servers.$MCP_NAME] command = \"$server\""
        fi
    fi
    if [ -n "$CONFIG_HELPER" ]; then
        rm -f "$CONFIG_HELPER"
    fi

    # 6. Status
    step "Archicad status:"
    run_indented "$server" doctor

    echo ""
    if [ -n "$configured" ]; then
        ok "ArchiBridge is installed. Connected apps: ${configured#, }"
    else
        note "The server is ready, but no AI app was found. Install Claude Desktop (claude.ai/download), then run this installer again."
    fi
    echo ""
    echo "Next steps:"
    if [ "$tapir_added" = 1 ] && archicad_running; then
        echo "  1. Save your work and restart Archicad so it loads Tapir, then open a project."
    else
        echo "  1. Start Archicad and open a project."
    fi
    if [ -n "$tapir_manual" ]; then
        echo "     To add Tapir yourself, run the installer again and enter your password, or in Archicad use"
        echo "     Options > Add-On Manager > Edit List of Available Add-Ons > Add, and pick:"
        printf '%s' "$tapir_manual" | sed 's/^/     /'
    fi
    echo "  2. Quit your AI app completely and open it again."
    echo "     Claude Desktop: Claude menu > Quit Claude (Cmd+Q). Claude Code: start a new session."
    echo "  3. Try: \"Read the archibridge skill, then describe my open Archicad project.\""
    echo "  4. When the AI wants to change the model, your AI app asks you first."
    echo ""
}

# The whole output also goes to a log, which an issue report can attach. Nothing reads the
# terminal: when the script comes from curl, the rest of it would be read as input.
# A run as root, which the installer refuses, writes no log: sudo keeps the user's HOME, so it
# would empty the user's log or leave one owned by root that later runs can't write.
if [ "$(uname -s)" = "Darwin" ] && [ "$(id -u)" != "0" ] && [ -n "$HOME" ] && mkdir -p "${LOG_FILE%/*}" 2>/dev/null && : 2>/dev/null > "$LOG_FILE"; then
    install_archibridge < /dev/null 2>&1 | tee -a "$LOG_FILE"
    archibridge_status=${PIPESTATUS[0]}
    echo "Install log: $LOG_FILE"
else
    install_archibridge < /dev/null
    archibridge_status=$?
fi
exit "$archibridge_status"
