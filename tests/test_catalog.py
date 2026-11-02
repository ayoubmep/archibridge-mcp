import pytest

from archibridge import catalog


def test_catalog_has_tapir_and_builtin_commands():
    found = catalog.search(limit=1000)
    names = {command["name"] for command in found["commands"]}
    assert {"CreateWalls", "GetMEPPorts", "API.GetAllElements", "API.GetProductInfo"} <= names
    assert found["total"] > 400


def test_search_needs_every_word():
    names = [item["name"] for item in catalog.search("mep port")["commands"]]
    assert "GetMEPPorts" in names
    assert "CreateWalls" not in names


def test_search_by_access():
    found = catalog.search("wall", access="modify", limit=200)
    names = [item["name"] for item in found["commands"]]
    assert "CreateWalls" in names
    assert "GetDetailsOfElements" not in names


def test_search_reports_minimum_archicad():
    entry = catalog.search("GetCurrentViewImage")["commands"][0]
    assert entry["minimumArchicad"] == 30


def test_empty_search_lists_groups():
    assert "MEP Commands" in catalog.search()["groups"]


def test_resolve():
    assert catalog.resolve("GetStories") == "GetStories"
    assert catalog.resolve("API.GetAllElements") == "API.GetAllElements"
    assert catalog.resolve("IsAlive") == "API.IsAlive"
    assert catalog.resolve("SomethingNew") == "SomethingNew"


def test_schema_of_a_command_includes_definitions():
    found = catalog.schema("CreateWalls")
    assert found["access"] == "modify"
    assert "wallsData" in found["input"]["properties"]
    assert "Coordinate2D" in found["definitions"]


def test_schema_of_a_definition():
    found = catalog.schema("#/ElementId")
    assert "guid" in found["definition"]["properties"]
    assert "Guid" in found["definitions"]


def test_schema_of_a_builtin_points_to_the_docs():
    found = catalog.schema("API.GetAllElements")
    assert found["documentation"].startswith("https://")


def test_a_name_in_both_tapir_and_builtin_gives_the_tapir_schema():
    assert "input" in catalog.schema("GetElementsByType")
    assert "documentation" in catalog.schema("API.GetElementsByType")


def test_shallow_schema_lists_what_it_left_out():
    found = catalog.schema("GetDetailsOfElements", depth=1)
    assert found["moreDefinitions"]
    assert not set(found["moreDefinitions"]) & set(found["definitions"])


def test_unknown_name():
    with pytest.raises(KeyError):
        catalog.schema("NotACommand")
