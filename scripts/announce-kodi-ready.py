#!/usr/bin/env python3
"""Envoie une confirmation vocale (via le serveur Piper TTS) une fois que
Kodi a démarré, pour vérifier à l'oreille que le son fonctionne bien."""

import json
import os
import socket
import sys

SOCKET_PATH = os.environ.get("PIPER_SOCKET", "/tmp/piper_tts.sock")
TEXT = os.environ.get(
    "ANNOUNCE_TEXT", "Kodi est démarré. Le son fonctionne correctement."
)
TIMEOUT = float(os.environ.get("ANNOUNCE_TIMEOUT", "10"))


def main() -> int:
    if not os.path.exists(SOCKET_PATH):
        print(f"[announce-kodi-ready] socket introuvable: {SOCKET_PATH}", file=sys.stderr)
        return 1

    try:
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as sock:
            sock.settimeout(TIMEOUT)
            sock.connect(SOCKET_PATH)
            payload = json.dumps({"mode": "fast", "text": TEXT}) + "\n"
            sock.sendall(payload.encode("utf-8"))
            response = sock.makefile("r").readline().strip()
            print(f"[announce-kodi-ready] réponse serveur Piper: {response}")
    except OSError as exc:
        print(f"[announce-kodi-ready] erreur de connexion au socket Piper: {exc}", file=sys.stderr)
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())
