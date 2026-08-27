#!/usr/bin/env python3
"""Exercise the real Quickshell greetd client against a fake greetd socket."""

from __future__ import annotations

import json
import os
from pathlib import Path
import socket
import struct
import subprocess
import sys
import tempfile
import threading


ROOT = Path(__file__).resolve().parents[1]
QML = ROOT / "greeter/qml"


def send_message(connection: socket.socket, payload: dict[str, object]) -> None:
    data = json.dumps(payload, separators=(",", ":")).encode()
    connection.sendall(struct.pack("=I", len(data)) + data)


def receive_exact(connection: socket.socket, length: int) -> bytes:
    chunks: list[bytes] = []
    remaining = length
    while remaining:
        chunk = connection.recv(remaining)
        if not chunk:
            raise AssertionError("greetd client closed the socket unexpectedly")
        chunks.append(chunk)
        remaining -= len(chunk)
    return b"".join(chunks)


def receive_message(connection: socket.socket) -> dict[str, object]:
    length = struct.unpack("=I", receive_exact(connection, 4))[0]
    return json.loads(receive_exact(connection, length))


def write_config(path: Path) -> None:
    path.write_text(
        json.dumps(
            {
                "username": "test-user",
                "wallpaper": "",
                "background": "#1a1b26",
                "foreground": "#c0caf5",
                "bright": "#ffffff",
                "muted": "#565f89",
                "accent": "#7aa2f7",
                "red": "#f7768e",
                "font": "JetBrainsMono Nerd Font",
                "fontSize": 14,
                "dimOpacity": 0.48,
                "hourFormat": "24",
                "showSecondsRing": False,
                "showPowerActions": False,
                "autoStartAuthentication": True,
                "sessions": [{"name": "Test", "command": ["/bin/true"]}],
            }
        )
        + "\n",
        encoding="utf-8",
    )


def run_conversation(message_type: str, response: str, include_info: bool) -> None:
    with tempfile.TemporaryDirectory(prefix="nbshell-greetd-mock.") as directory:
        temporary = Path(directory)
        socket_path = temporary / "greetd.sock"
        config_path = temporary / "config.json"
        write_config(config_path)
        server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        server.bind(str(socket_path))
        server.listen(1)
        server.settimeout(8)
        failure: list[BaseException] = []

        def serve() -> None:
            try:
                connection, _ = server.accept()
                with connection:
                    connection.settimeout(8)
                    request = receive_message(connection)
                    assert request == {
                        "type": "create_session",
                        "username": "test-user",
                    }, request
                    if include_info:
                        send_message(
                            connection,
                            {
                                "type": "auth_message",
                                "auth_message_type": "info",
                                "auth_message": "Touch the fingerprint sensor",
                            },
                        )
                        request = receive_message(connection)
                        assert request.get("type") == "post_auth_message_response", request
                        assert request.get("response") is None, request
                    send_message(
                        connection,
                        {
                            "type": "auth_message",
                            "auth_message_type": message_type,
                            "auth_message": "Password:" if message_type == "secret" else "One-time code:",
                        },
                    )
                    request = receive_message(connection)
                    assert request == {
                        "type": "post_auth_message_response",
                        "response": response,
                    }, request
                    send_message(connection, {"type": "success"})
                    request = receive_message(connection)
                    assert request.get("type") == "start_session", request
                    assert request.get("cmd") == ["/bin/true"], request
                    launch_environment = request.get("env")
                    assert isinstance(launch_environment, list), request
                    assert "XDG_SESSION_TYPE=wayland" in launch_environment, request
                    send_message(connection, {"type": "success"})
            except BaseException as error:  # propagated to the main test thread
                failure.append(error)

        thread = threading.Thread(target=serve, daemon=True)
        thread.start()
        environment = os.environ.copy()
        environment.update(
            {
                "GREETD_SOCK": str(socket_path),
                "NBSHELL_GREETER_CONFIG": str(config_path),
                "NBSHELL_GREETER_INTEGRATION_TEST": "1",
                "NBSHELL_GREETER_TEST_RESPONSE": response,
            }
        )
        process = subprocess.Popen(
            ["quickshell", "-p", str(QML)],
            env=environment,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
        )
        thread.join(timeout=10)
        if failure or thread.is_alive():
            process.terminate()
        try:
            output, _ = process.communicate(timeout=3)
        except subprocess.TimeoutExpired:
            process.kill()
            output, _ = process.communicate(timeout=3)
        server.close()
        if failure:
            raise failure[0]
        assert not thread.is_alive(), "fake greetd server did not finish"
        assert process.returncode == 0, output
        assert "Failed to load configuration" not in output, output


def verify_preview_isolation() -> None:
    with tempfile.TemporaryDirectory(prefix="nbshell-greetd-preview.") as directory:
        temporary = Path(directory)
        socket_path = temporary / "greetd.sock"
        config_path = temporary / "config.json"
        write_config(config_path)
        server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        server.bind(str(socket_path))
        server.listen(1)
        server.settimeout(1)
        environment = os.environ.copy()
        environment.update(
            {
                "GREETD_SOCK": str(socket_path),
                "NBSHELL_GREETER_CONFIG": str(config_path),
                "NBSHELL_GREETER_PREVIEW": "1",
            }
        )
        process = subprocess.Popen(
            ["quickshell", "-p", str(QML)],
            env=environment,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
        )
        try:
            try:
                connection, _ = server.accept()
            except TimeoutError:
                connection = None
            if connection is not None:
                with connection:
                    connection.settimeout(1)
                    try:
                        data = connection.recv(1)
                    except TimeoutError:
                        data = b""
                    assert data == b"", "preview mode sent a greetd request"
            assert process.poll() is None, "preview exited before its smoke-test window"
        finally:
            process.terminate()
            try:
                process.wait(timeout=3)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=3)
            server.close()


def main() -> int:
    if not os.environ.get("WAYLAND_DISPLAY"):
        print("Greetd mock integration: SKIP (no Wayland display)")
        return 0
    run_conversation("secret", "correct horse", include_info=True)
    run_conversation("visible", "123456", include_info=False)
    verify_preview_isolation()
    print("Greetd mock integration: OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())