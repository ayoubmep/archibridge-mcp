"""Decides which commands may run through which tool.

Reads run freely. Anything else goes through the archicad_modify tool, so the AI app
can ask the user first. A command this file does not recognise counts as a modification.

ARCHIBRIDGE_POLICY:
    readonly   only reads run
    ask        the default: reads and modifications run, restricted commands do not
    full       restricted commands run too
"""

from __future__ import annotations

import os

READ = "read"
MODIFY = "modify"
RESTRICTED = "restricted"

POLICIES = ("readonly", "ask", "full")
DEFAULT_POLICY = "ask"

READ_PREFIXES = ("Get", "Is")

# These start with Get but stop Archicad until the user clicks, or clear stored data.
NOT_READS = {"GetPointFromUser", "GetElementFromUser", "GetScriptUIResult"}

# Calculations with no side effect, and commands that only move the user's view.
EXTRA_READS = {
    "ConvertRevealOffsets",
    "FilterElements",
    "MeasureTexts",
    "RegularizePolygons",
    "RegularizePolylines",
    "SolveStairBaseline",
    "TriangulatePolygonsOfElements",
    "ChangeSelectionOfElements",
    "ChangeWindow",
    "FitInWindow",
    "HighlightElements",
    "RebuildView",
    "ResetZoom",
    "SetZoom",
}

# These can lose the user's work or reach other people, so "ask" does not allow them.
RESTRICTED_COMMANDS = {
    "CloseProject",
    "NewProject",
    "OpenProject",
    "QuitArchicad",
    "TeamworkReceive",
    "TeamworkSend",
}


_RESTRICTED_KEYS = {name.casefold() for name in RESTRICTED_COMMANDS}
_NOT_READ_KEYS = {name.casefold() for name in NOT_READS}


def classify(command: str) -> str:
    name = command.removeprefix("API.")
    if name.casefold() in _RESTRICTED_KEYS:
        return RESTRICTED
    if name.casefold() in _NOT_READ_KEYS:
        return MODIFY
    if name in EXTRA_READS or name.startswith(READ_PREFIXES):
        return READ
    return MODIFY


def current() -> str:
    value = os.environ.get("ARCHIBRIDGE_POLICY", DEFAULT_POLICY).strip().lower()
    return value if value in POLICIES else "readonly"


def refusal(command: str) -> str | None:
    """Returns why the current policy blocks a modification, or None when it may run."""
    active = current()
    if active == "readonly":
        return f"{command} changes the project, and ArchiBridge is in readonly mode."
    if classify(command) == RESTRICTED and active != "full":
        return (
            f"{command} is restricted because it can lose work or affect other users. "
            "Ask the user to do it in Archicad. ARCHIBRIDGE_POLICY=full allows it."
        )
    return None
