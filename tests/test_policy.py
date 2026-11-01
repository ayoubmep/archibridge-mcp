import re

import pytest

from archibridge import catalog, policy


def tapir_names():
    return list(catalog._by_name())


def test_reads():
    for name in ("GetStories", "API.GetAllElements", "API.IsAlive", "FilterElements", "ChangeWindow"):
        assert policy.classify(name) == policy.READ


def test_unknown_commands_count_as_modifications():
    assert policy.classify("FrobnicateElements") == policy.MODIFY


def test_commands_that_block_archicad_are_not_reads():
    assert policy.classify("GetPointFromUser") == policy.MODIFY
    assert policy.classify("GetElementFromUser") == policy.MODIFY
    assert policy.classify("GetScriptUIResult") == policy.MODIFY


def test_a_name_that_only_starts_like_a_read_prefix_is_not_special_cased_away():
    assert policy.classify("ImportFavorites") == policy.MODIFY
    assert policy.classify("IFCFileOperation") == policy.MODIFY


def test_every_mutating_verb_in_the_catalog_is_a_modification():
    verbs = (
        "Create", "Set", "Delete", "Modify", "Update", "Rename", "Move", "Remove",
        "Import", "Save", "Add", "Apply", "Connect", "Rotate", "Mirror", "Lock",
    )
    pattern = re.compile("^(" + "|".join(verbs) + ")[A-Z0-9]")
    allowed = {"SetZoom"}
    for name in tapir_names():
        if pattern.match(name) and name not in allowed:
            assert policy.classify(name) != policy.READ, name


def test_every_read_exception_exists_in_the_catalog():
    names = set(tapir_names())
    assert policy.EXTRA_READS <= names
    assert policy.NOT_READS <= names
    assert policy.RESTRICTED_COMMANDS <= names


def test_ask_policy(monkeypatch):
    monkeypatch.delenv("ARCHIBRIDGE_POLICY", raising=False)
    assert policy.current() == "ask"
    assert policy.refusal("CreateWalls") is None
    assert "restricted" in policy.refusal("QuitArchicad")


def test_readonly_policy(monkeypatch):
    monkeypatch.setenv("ARCHIBRIDGE_POLICY", "readonly")
    assert "readonly" in policy.refusal("CreateWalls")


def test_full_policy(monkeypatch):
    monkeypatch.setenv("ARCHIBRIDGE_POLICY", "full")
    assert policy.refusal("QuitArchicad") is None


@pytest.mark.parametrize("value", ["", "yolo", "auto"])
def test_unknown_policy_falls_back_to_readonly(monkeypatch, value):
    monkeypatch.setenv("ARCHIBRIDGE_POLICY", value)
    assert policy.current() == "readonly"
