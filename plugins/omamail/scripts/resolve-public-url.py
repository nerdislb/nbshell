#!/usr/bin/env python3
"""Resolve an HTTP(S) URL once and emit a curl --resolve pin for a public IP."""

from __future__ import annotations

import ipaddress
import socket
import sys
from urllib.parse import urlsplit


def main() -> int:
    if len(sys.argv) != 2 or "\r" in sys.argv[1] or "\n" in sys.argv[1]:
        return 2
    parsed = urlsplit(sys.argv[1])
    if parsed.scheme not in {"http", "https"} or not parsed.hostname:
        return 2
    if parsed.username is not None or parsed.password is not None:
        return 2
    try:
        port = parsed.port or (443 if parsed.scheme == "https" else 80)
        addresses = {
            ipaddress.ip_address(item[4][0])
            for item in socket.getaddrinfo(parsed.hostname, port, type=socket.SOCK_STREAM)
        }
    except (OSError, ValueError):
        return 2
    if not addresses or any(not address.is_global for address in addresses):
        return 2
    selected = sorted(addresses, key=lambda address: (address.version != 4, str(address)))[0]
    rendered = f"[{selected}]" if selected.version == 6 else str(selected)
    print(f"{parsed.hostname}:{port}:{rendered}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
