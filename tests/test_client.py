import pytest

from archibridge import client


def test_no_archicad_running(archicads):
    assert client.instances() == []
    with pytest.raises(client.ArchicadError, match="not running"):
        client.pick_port()


def test_no_project_open_is_reported(archicads):
    fake = archicads(project_open=False)
    assert client.instances()[0]["status"] == "no_project"
    with pytest.raises(client.ArchicadError, match="no open project"):
        client.pick_port()
    with pytest.raises(client.ArchicadError, match="Open a project"):
        client.call("GetStories", None, fake.port)


def test_describe_ready_instance(archicads):
    fake = archicads()
    info = client.instances()[0]
    assert info["status"] == "ready"
    assert info["port"] == fake.port
    assert info["tapir"] == "1.7.3"
    assert info["project"]["projectName"] == "Tower"
    assert info["archicad"]["version"] == 29


def test_describe_without_tapir(archicads):
    archicads(tapir=False)
    info = client.instances()[0]
    assert info["status"] == "ready"
    assert info["tapir"] is None


def test_single_ready_instance_is_picked_over_one_without_project(archicads):
    archicads(project_open=False)
    ready = archicads()
    assert client.pick_port() == ready.port


def test_several_ready_instances_are_not_guessed(archicads):
    archicads()
    archicads()
    with pytest.raises(client.ArchicadError, match="Several Archicads"):
        client.pick_port()


def test_explicit_and_configured_ports_win(archicads, monkeypatch):
    assert client.pick_port(19800) == 19800
    monkeypatch.setenv("ARCHIBRIDGE_PORT", "19801")
    assert client.pick_port() == 19801


def test_builtin_command_is_sent_directly(archicads):
    fake = archicads()
    assert client.call("API.IsAlive", None, fake.port) == {"isAlive": True}
    assert fake.requests[-1] == {"command": "API.IsAlive", "parameters": {}}


def test_tapir_command_is_wrapped(archicads):
    fake = archicads()
    fake.tapir_results["GetStories"] = {"stories": []}
    assert client.call("GetStories", {"a": 1}, fake.port) == {"stories": []}
    sent = fake.requests[-1]
    assert sent["command"] == "API.ExecuteAddOnCommand"
    assert sent["parameters"]["addOnCommandId"]["commandNamespace"] == "TapirCommand"
    assert sent["parameters"]["addOnCommandId"]["commandName"] == "GetStories"
    assert sent["parameters"]["addOnCommandParameters"] == {"a": 1}


def test_tapir_failure_raises_its_message(archicads):
    fake = archicads()
    fake.tapir_results["CreateWalls"] = {"success": False, "error": {"code": 1, "message": "bad wall"}}
    with pytest.raises(client.ArchicadError, match="bad wall"):
        client.call("CreateWalls", {}, fake.port)


def test_missing_tapir_is_explained(archicads):
    fake = archicads(tapir=False)
    with pytest.raises(client.ArchicadError, match="needs the Tapir add-on"):
        client.call("GetStories", None, fake.port)


def test_unknown_builtin_keeps_archicad_message(archicads):
    fake = archicads()
    with pytest.raises(client.ArchicadError, match="not found"):
        client.call("API.Nope", None, fake.port)


def test_unreachable_port_is_an_archicad_error():
    with pytest.raises(client.ArchicadError, match="No answer"):
        client.call("API.IsAlive", None, 1, timeout=1)
