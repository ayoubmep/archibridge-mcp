import asyncio
import base64
import json
import os

import pytest
from mcp.server.fastmcp.exceptions import ToolError

from archibridge import server

JPEG = b"\xff\xd8\xff\xe0fake"


def call(tool, **arguments):
    return asyncio.run(server.mcp.call_tool(tool, arguments))


def tool_names():
    return {tool.name: tool for tool in asyncio.run(server.mcp.list_tools())}


def test_tools_are_registered_with_the_right_hints():
    tools = tool_names()
    assert set(tools) == {
        "archicad_instances",
        "archicad_search_commands",
        "archicad_command_schema",
        "archicad_read",
        "archicad_modify",
        "archicad_view_image",
        "archicad_get_skill",
    }
    for name, tool in tools.items():
        assert tool.annotations.readOnlyHint is (name != "archicad_modify"), name


def test_instances_tool(archicads):
    archicads()
    result = server.archicad_instances()
    assert result["policy"] == "ask"
    assert result["instances"][0]["tapir"] == "1.7.3"


def test_read_tool_runs_a_read(archicads):
    fake = archicads()
    fake.tapir_results["GetStories"] = {"stories": [1]}
    assert server.archicad_read("GetStories") == {"stories": [1]}


def test_read_tool_accepts_a_short_builtin_name(archicads):
    fake = archicads()
    assert server.archicad_read("IsAlive") == {"isAlive": True}
    assert fake.requests[-1]["command"] == "API.IsAlive"


def test_read_tool_refuses_modifications(archicads):
    fake = archicads()
    with pytest.raises(ValueError, match="archicad_modify"):
        server.archicad_read("CreateWalls", {"wallsData": []})
    assert not any(r["command"] == "API.ExecuteAddOnCommand" for r in fake.requests)


def test_read_tool_refuses_unknown_commands(archicads):
    archicads()
    with pytest.raises(ValueError):
        server.archicad_read("FrobnicateElements")


def test_modify_tool_runs_a_modification(archicads):
    fake = archicads()
    fake.tapir_results["CreateWalls"] = {"elements": [{"elementId": {"guid": "x"}}]}
    assert server.archicad_modify("CreateWalls", {"wallsData": []})["elements"]


def test_modify_tool_refuses_reads(archicads):
    archicads()
    with pytest.raises(ValueError, match="archicad_read"):
        server.archicad_modify("GetStories")


def test_restricted_commands_never_reach_archicad(archicads):
    fake = archicads()
    with pytest.raises(PermissionError):
        server.archicad_modify("QuitArchicad")
    assert fake.requests == []


def test_readonly_policy_blocks_modify(archicads, monkeypatch):
    fake = archicads()
    monkeypatch.setenv("ARCHIBRIDGE_POLICY", "readonly")
    with pytest.raises(PermissionError):
        server.archicad_modify("CreateWalls", {"wallsData": []})
    assert fake.requests == []


def test_large_results_are_saved_to_a_file(archicads):
    fake = archicads()
    fake.tapir_results["GetAllProperties"] = {"values": ["x" * 100] * 1000}
    result = server.archicad_read("GetAllProperties")
    assert result["truncated"] is True
    with open(result["savedTo"], encoding="utf-8") as file:
        assert len(json.load(file)["values"]) == 1000
    os.remove(result["savedTo"])


def test_view_image_returns_the_saved_picture_and_cleans_up(archicads):
    fake = archicads()
    paths = []
    original = fake.answer

    def answer(request):
        if request["command"] == "API.ExecuteAddOnCommand":
            parameters = request["parameters"]["addOnCommandParameters"]
            if "imageFilePath" in parameters:
                paths.append(parameters["imageFilePath"])
                with open(parameters["imageFilePath"], "wb") as file:
                    file.write(JPEG)
        return original(request)

    fake.answer = answer
    content = call("archicad_view_image")[0]
    assert content.type == "image"
    assert content.mimeType == "image/jpeg"
    assert base64.b64decode(content.data) == JPEG
    assert not os.path.exists(paths[0])


def test_skills_are_packaged():
    for name in server.SKILLS:
        assert server.archicad_get_skill(name).startswith("---")
    with pytest.raises(ValueError):
        server.archicad_get_skill("nope")


def test_errors_reach_the_ai_app_as_text(archicads):
    archicads(project_open=False)
    with pytest.raises(ToolError, match="Open a project"):
        call("archicad_read", command="GetStories")


def _wrapped(name, namespace="TapirCommand"):
    return {"addOnCommandId": {"commandNamespace": namespace, "commandName": name},
            "addOnCommandParameters": {}}


@pytest.mark.parametrize("name", ["QuitArchicad", "CloseProject", "TeamworkSend", "quitarchicad"])
def test_wrapped_restricted_commands_never_reach_archicad(archicads, name):
    fake = archicads()
    with pytest.raises(PermissionError):
        server.archicad_modify("API.ExecuteAddOnCommand", _wrapped(name))
    with pytest.raises(PermissionError):
        server.archicad_modify("ExecuteAddOnCommand", _wrapped(name, "tapircommand"))
    for wrapper in ("api.executeAddOnCommand", " executeaddoncommand "):
        with pytest.raises(PermissionError):
            server.archicad_modify(wrapper, _wrapped(name))
    assert fake.requests == []


def test_wrapped_read_still_runs(archicads):
    fake = archicads()
    fake.tapir_results["GetStories"] = {"stories": [1]}
    assert server.archicad_read("API.ExecuteAddOnCommand", _wrapped("GetStories")) == {"stories": [1]}
