"""Client for Archicad's local JSON API, including the Tapir add-on commands.

Every running Archicad listens on its own port on localhost, starting at 19723.
Commands named "API.Something" are built into Archicad. Any other name is a Tapir
command, sent through API.ExecuteAddOnCommand.
"""

from __future__ import annotations

import json
import os
import socket
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from typing import Any

HOST = "127.0.0.1"
FIRST_PORT = 19723
PORT_COUNT = 21
TAPIR_NAMESPACE = "TapirCommand"
NO_PROJECT_CODE = 4001

CALL_TIMEOUT = 120.0
PROBE_TIMEOUT = 5.0
CONNECT_TIMEOUT = 0.3

NO_PROJECT_HELP = "Open a project in Archicad, then try again."

# Archicad only ever runs on this machine, so a system proxy must never be used.
_opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))


class ArchicadError(Exception):
    """Archicad refused a command, or could not be reached."""

    def __init__(self, message: str, code: int | None = None):
        super().__init__(message)
        self.code = code


def _post(port: int, payload: dict, timeout: float) -> dict:
    request = urllib.request.Request(
        f"http://{HOST}:{port}",
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json"},
    )
    try:
        with _opener.open(request, timeout=timeout) as response:
            body = response.read()
    except (OSError, urllib.error.URLError) as error:
        raise ArchicadError(
            f"No answer from Archicad on port {port}: {error}. It may be busy with a dialog."
        ) from error
    try:
        return json.loads(body.decode("utf-8"))
    except ValueError as error:
        raise ArchicadError(f"Archicad on port {port} sent invalid JSON: {error}") from error


def _raise_failure(response: dict, command: str) -> None:
    error = response.get("error") or {}
    code = error.get("code")
    message = error.get("message", "unknown error")
    if code == NO_PROJECT_CODE:
        raise ArchicadError(f"{message}. {NO_PROJECT_HELP}", code)
    raise ArchicadError(f"{command} failed: {message}", code)


def _builtin(port: int, command: str, parameters: dict | None, timeout: float) -> Any:
    response = _post(port, {"command": command, "parameters": parameters or {}}, timeout)
    if not response.get("succeeded"):
        _raise_failure(response, command)
    return response.get("result", {})


def _command_id(name: str) -> dict:
    return {"commandNamespace": TAPIR_NAMESPACE, "commandName": name}


def tapir_available(port: int, timeout: float = PROBE_TIMEOUT) -> bool:
    result = _builtin(
        port,
        "API.IsAddOnCommandAvailable",
        {"addOnCommandId": _command_id("GetAddOnVersion")},
        timeout,
    )
    return bool(result.get("available"))


def _tapir(port: int, command: str, parameters: dict | None, timeout: float) -> Any:
    payload = {
        "addOnCommandId": _command_id(command),
        "addOnCommandParameters": parameters or {},
    }
    try:
        result = _builtin(port, "API.ExecuteAddOnCommand", payload, timeout)
    except ArchicadError as error:
        if error.code != NO_PROJECT_CODE and not _safe_tapir_check(port):
            raise ArchicadError(
                f"{command} needs the Tapir add-on, which is not loaded in this Archicad. "
                "See INSTALL.md, or use an API.* command.",
                error.code,
            ) from error
        raise
    data = result.get("addOnCommandResponse", result)
    if isinstance(data, dict) and data.get("success") is False:
        _raise_failure(data, command)
    return data


def _safe_tapir_check(port: int) -> bool:
    try:
        return tapir_available(port)
    except ArchicadError:
        return True


def call(command: str, parameters: dict | None, port: int, timeout: float = CALL_TIMEOUT) -> Any:
    """Runs a built-in ("API.*") or Tapir command and returns its result."""
    if command.startswith("API."):
        return _builtin(port, command, parameters, timeout)
    return _tapir(port, command, parameters, timeout)


def _port_open(port: int) -> bool:
    try:
        with socket.create_connection((HOST, port), timeout=CONNECT_TIMEOUT):
            return True
    except OSError:
        return False


def open_ports() -> list[int]:
    ports = range(FIRST_PORT, FIRST_PORT + PORT_COUNT)
    with ThreadPoolExecutor(max_workers=PORT_COUNT) as pool:
        found = list(pool.map(_port_open, ports))
    return [port for port, is_open in zip(ports, found) if is_open]


def describe(port: int) -> dict:
    """Reports what is running on a port. Status: ready, no_project or busy."""
    info: dict[str, Any] = {"port": port}
    try:
        _builtin(port, "API.IsAlive", None, PROBE_TIMEOUT)
    except ArchicadError as error:
        info["status"] = "no_project" if error.code == NO_PROJECT_CODE else "busy"
        info["message"] = str(error)
        return info

    info["status"] = "ready"
    try:
        info["archicad"] = _builtin(port, "API.GetProductInfo", None, PROBE_TIMEOUT)
        if not tapir_available(port):
            info["tapir"] = None
            return info
        info["tapir"] = _tapir(port, "GetAddOnVersion", None, PROBE_TIMEOUT).get("version")
        info["project"] = _tapir(port, "GetProjectInfo", None, PROBE_TIMEOUT)
    except ArchicadError as error:
        info["warning"] = str(error)
    return info


def instances() -> list[dict]:
    ports = open_ports()
    if not ports:
        return []
    with ThreadPoolExecutor(max_workers=len(ports)) as pool:
        return list(pool.map(describe, ports))


def pick_port(port: int | None = None) -> int:
    """Chooses the Archicad to talk to, and refuses to guess between several."""
    if port is not None:
        return port
    configured = os.environ.get("ARCHIBRIDGE_PORT")
    if configured:
        return int(configured)

    found = instances()
    if not found:
        raise ArchicadError("Archicad is not running. Start it and open a project.")
    ready = [item for item in found if item["status"] == "ready"]
    if len(ready) == 1:
        return ready[0]["port"]
    if ready:
        names = ", ".join(
            f"{item['port']} ({(item.get('project') or {}).get('projectName', 'unknown project')})"
            for item in ready
        )
        raise ArchicadError(f"Several Archicads are ready: {names}. Pass the port to use.")
    if any(item["status"] == "no_project" for item in found):
        raise ArchicadError(f"Archicad has no open project. {NO_PROJECT_HELP}", NO_PROJECT_CODE)
    raise ArchicadError("Archicad is busy. Close any open dialog and try again.")
