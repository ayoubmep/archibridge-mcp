"""Regenerates src/archibridge/data/catalog.json from a Tapir release and the Archicad docs.

Usage: python scripts/update_catalog.py 1.7.3 29
"""

import json
import re
import sys
import urllib.request
from pathlib import Path

TAPIR_DOCS = "https://raw.githubusercontent.com/ENZYME-APD/tapir-archicad-automation/{version}/docs/archicad-addon/{file}"
ARCHICAD_DOCS = "https://archicadapi.graphisoft.com/archicadPythonPackage/archicad.releases.ac{release}.html"
TARGET = Path(__file__).resolve().parent.parent / "src" / "archibridge" / "data" / "catalog.json"


def fetch(url):
    with urllib.request.urlopen(url, timeout=60) as response:
        return response.read().decode("utf-8")


def javascript_value(text, opening, closing):
    return json.loads(text[text.index(opening) : text.rindex(closing) + 1])


def builtin_commands(release):
    pattern = rf'id="archicad\.releases\.ac{release}\.b\d+commands\.Commands\.([A-Z]\w+)"'
    return sorted(set(re.findall(pattern, fetch(ARCHICAD_DOCS.format(release=release)))))


def main():
    version, release = sys.argv[1], sys.argv[2]
    groups = javascript_value(fetch(TAPIR_DOCS.format(version=version, file="command_definitions.js")), "[", "]")
    definitions = javascript_value(fetch(TAPIR_DOCS.format(version=version, file="common_schema_definitions.js")), "{", "}")
    catalog = {
        "tapirVersion": version,
        "archicadRelease": int(release),
        "groups": groups,
        "definitions": definitions,
        "builtin": builtin_commands(release),
    }
    TARGET.parent.mkdir(parents=True, exist_ok=True)
    TARGET.write_text(json.dumps(catalog, ensure_ascii=False, separators=(",", ":")), encoding="utf-8", newline="\n")
    count = sum(len(group["commands"]) for group in groups)
    print(f"{TARGET.name}: {count} Tapir and {len(catalog['builtin'])} built-in commands, {TARGET.stat().st_size} bytes")


if __name__ == "__main__":
    main()
