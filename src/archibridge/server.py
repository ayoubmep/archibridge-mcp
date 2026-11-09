"""MCP server: the tools an AI app uses to work in Archicad."""

from __future__ import annotations

import json
import os
import shutil
import sys
import tempfile
from importlib import resources
from typing import Any, Literal

from mcp.server.fastmcp import FastMCP, Image
from mcp.types import ToolAnnotations

from . import __version__, catalog, client, policy

MAX_RESULT_CHARS = 60_000
PREVIEW_CHARS = 4_000
INTERACTIVE_TIMEOUT = 300.0
INTERACTIVE_COMMANDS = {"GetPointFromUser", "GetElementFromUser"}
SKILLS = ("archibridge", "archicad-mep-review")

READ_ONLY = ToolAnnotations(readOnlyHint=True, idempotentHint=True, openWorldHint=False)
MODIFIES = ToolAnnotations(readOnlyHint=False, destructiveHint=True, openWorldHint=False)

INSTRUCTIONS = """\
ArchiBridge connects you to the Archicad running on the user's PC.

Start every task with archicad_instances. Read the skill with archicad_get_skill before
building or changing anything. Use archicad_search_commands to find a command and
archicad_command_schema for its exact parameters, because they are not guessable.
archicad_read runs commands that only read. archicad_modify runs commands that change the
project, and the user's app may ask them to approve each one.
"""

mcp = FastMCP("archibridge", instructions=INSTRUCTIONS)


def _fit(result: Any) -> Any:
    """Keeps huge results out of the conversation by saving them to a file."""
    text = json.dumps(result, ensure_ascii=False)
    if len(text) <= MAX_RESULT_CHARS:
        return result
    handle, path = tempfile.mkstemp(prefix="archibridge-result-", suffix=".json")
    with os.fdopen(handle, "w", encoding="utf-8") as file:
        file.write(text)
    return {
        "truncated": True,
        "totalCharacters": len(text),
        "savedTo": path,
        "preview": text[:PREVIEW_CHARS],
    }


def _run(command: str, parameters: dict | None, port: int | None) -> Any:
    timeout = INTERACTIVE_TIMEOUT if command in INTERACTIVE_COMMANDS else client.CALL_TIMEOUT
    return _fit(client.call(command, parameters, client.pick_port(port), timeout))


def _unwrap(command: str, parameters: dict | None) -> tuple[str, dict | None]:
    """Turns API.ExecuteAddOnCommand for a Tapir command into that command.

    Without this, a restricted command such as QuitArchicad sent inside the wrapper
    would be checked as "ExecuteAddOnCommand" and slip past the policy.
    """
    if command != "API.ExecuteAddOnCommand" or not isinstance(parameters, dict):
        return command, parameters
    target = parameters.get("addOnCommandId")
    if not isinstance(target, dict):
        return command, parameters
    namespace = str(target.get("commandNamespace", "")).strip().casefold()
    name = target.get("commandName")
    if namespace == client.TAPIR_NAMESPACE.casefold() and isinstance(name, str) and name.strip():
        return name.strip(), parameters.get("addOnCommandParameters")
    return command, parameters


@mcp.tool(annotations=READ_ONLY)
def archicad_instances() -> dict:
    """Lists the running Archicads: port, version, open project, and Tapir add-on version.

    Call this first. status is "ready", "no_project" (nothing is open yet) or "busy".
    When tapir is null, only API.* commands work until the add-on is installed.
    """
    return {
        "archibridge": __version__,
        "policy": policy.current(),
        "tapirCatalog": catalog.tapir_version(),
        "instances": client.instances(),
    }


@mcp.tool(annotations=READ_ONLY)
def archicad_search_commands(
    query: str = "",
    access: Literal["any", "read", "modify", "restricted"] = "any",
    limit: int = 40,
) -> dict:
    """Finds Archicad commands by words in their name, group or description.

    Examples: "wall", "property value", "mep port", "layout". Leave query empty to see
    the groups. minimumArchicad shows commands that need a newer Archicad.
    """
    return catalog.search(query, access, limit)


@mcp.tool(annotations=READ_ONLY)
def archicad_command_schema(name: str, depth: int = catalog.SCHEMA_DEPTH) -> dict:
    """Returns a command's input and output schemas, with the definitions they refer to.

    Read this before the first call of any command. Definitions listed in moreDefinitions
    were left out to keep the answer short: pass one of those names here to read it.
    """
    return catalog.schema(name, depth)


@mcp.tool(annotations=READ_ONLY)
def archicad_read(command: str, parameters: dict | None = None, port: int | None = None) -> Any:
    """Runs a command that does not change the project.

    command: a Tapir name such as "GetStories", or a built-in such as "API.GetAllElements".
    parameters: the command's input object. port: only needed when several Archicads are ready.
    Also allowed: commands that only move the view, such as ChangeWindow and FitInWindow.
    """
    command, parameters = _unwrap(catalog.resolve(command), parameters)
    if policy.classify(command) != policy.READ:
        raise ValueError(f"{command} is not a read command. Use archicad_modify.")
    return _run(command, parameters, port)


@mcp.tool(annotations=MODIFIES)
def archicad_modify(command: str, parameters: dict | None = None, port: int | None = None) -> Any:
    """Runs a command that changes the project, such as CreateWalls or SetDetailsOfElements.

    Send many items in one call instead of many calls. Results list one entry per item, and
    an item can fail on its own, so read the result. Restricted commands such as QuitArchicad
    and CloseProject are refused unless the user turned on the full policy.
    """
    command, parameters = _unwrap(catalog.resolve(command), parameters)
    if policy.classify(command) == policy.READ:
        raise ValueError(f"{command} only reads. Use archicad_read.")
    reason = policy.refusal(command)
    if reason:
        raise PermissionError(reason)
    return _run(command, parameters, port)


@mcp.tool(annotations=READ_ONLY)
def archicad_view_image(entire_drawing: bool = False, port: int | None = None) -> Image:
    """Returns a picture of Archicad's current window, so you can check your work.

    Works for the 3D window and for 2D windows. Switch window first if needed, with
    ChangeWindow and {"windowType": "3DModel"}, or {"windowType": "FloorPlan", "storyIndex": 0},
    then FitInWindow. entire_drawing: in a 2D window, capture the whole drawing, not just the zoom.
    """
    target = client.pick_port(port)
    folder = tempfile.mkdtemp(prefix="archibridge-")
    path = os.path.join(folder, "view.jpg")
    parameters: dict[str, Any] = {"imageFilePath": path, "format": "jpg"}
    if entire_drawing:
        parameters["entireDrawing"] = True
    try:
        client.call("SaveCurrentWindowAsImage", parameters, target)
        with open(path, "rb") as file:
            return Image(data=file.read(), format="jpeg")
    finally:
        shutil.rmtree(folder, ignore_errors=True)


@mcp.tool(annotations=READ_ONLY)
def archicad_get_skill(name: str = "archibridge") -> str:
    """Returns a working method. Skills: archibridge, archicad-mep-review."""
    if name not in SKILLS:
        raise ValueError(f"Unknown skill: {name}. Skills: {', '.join(SKILLS)}")
    skill = resources.files("archibridge").joinpath(f"skills/{name}/SKILL.md")
    return skill.read_text("utf-8")


def _doctor() -> int:
    found = client.instances()
    print(json.dumps({"archibridge": __version__, "instances": found}, indent=2, ensure_ascii=False))
    return 0 if any(item["status"] == "ready" for item in found) else 1


def main() -> None:
    if sys.argv[1:] == ["doctor"]:
        sys.exit(_doctor())
    if sys.argv[1:] == ["--version"]:
        print(__version__)
        return
    mcp.run()


if __name__ == "__main__":
    main()
