"""A fake Archicad: answers the JSON API the way a real one does."""

import json
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import pytest

from archibridge import client


class FakeArchicad:
    def __init__(self, project_open=True, tapir=True):
        self.project_open = project_open
        self.tapir = tapir
        self.requests = []
        self.tapir_results = {
            "GetAddOnVersion": {"version": "1.7.3"},
            "GetProjectInfo": {"isUntitled": False, "isTeamwork": False, "projectName": "Tower"},
        }

    def answer(self, request):
        self.requests.append(request)
        command = request["command"]
        if not self.project_open:
            return self.failure(4001, "Invalid program status (no open project)")
        if command == "API.IsAlive":
            return self.success({"isAlive": True})
        if command == "API.GetProductInfo":
            return self.success({"version": 29, "buildNumber": 3000, "languageCode": "INT"})
        if command == "API.IsAddOnCommandAvailable":
            return self.success({"available": self.tapir})
        if command == "API.ExecuteAddOnCommand":
            if not self.tapir:
                return self.failure(4010, "Add-on command is not available")
            name = request["parameters"]["addOnCommandId"]["commandName"]
            return self.success({"addOnCommandResponse": self.tapir_results.get(name, {"success": True})})
        return self.failure(2002, f"Command '{command}' not found")

    @staticmethod
    def success(result):
        return {"succeeded": True, "result": result}

    @staticmethod
    def failure(code, message):
        return {"succeeded": False, "error": {"code": code, "message": message}}


def serve(fake):
    class Handler(BaseHTTPRequestHandler):
        def do_POST(self):
            request = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
            body = json.dumps(fake.answer(request)).encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, *args):
            pass

    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    return server


@pytest.fixture
def archicads(monkeypatch):
    """Starts fake Archicads on demand and makes port discovery find exactly those."""
    servers = []
    ports = []
    monkeypatch.delenv("ARCHIBRIDGE_PORT", raising=False)
    monkeypatch.delenv("ARCHIBRIDGE_POLICY", raising=False)
    monkeypatch.setattr(client, "open_ports", lambda: list(ports))

    def start(**options):
        fake = FakeArchicad(**options)
        server = serve(fake)
        servers.append(server)
        fake.port = server.server_address[1]
        ports.append(fake.port)
        return fake

    yield start
    for server in servers:
        server.shutdown()
        server.server_close()
