#!/usr/bin/env python3
"""Locate workspace preferences for this compositor session, without writing them."""
import hashlib
import json
from pathlib import Path
import stat
import sys


def session_state(socket_path, runtime_dir):
    socket = Path(socket_path)
    identity = socket.stat()
    if not stat.S_ISSOCK(identity.st_mode):
        raise ValueError("NIRI_SOCKET is not a socket")
    key = f"{socket.resolve()}:{identity.st_dev}:{identity.st_ino}:{identity.st_ctime_ns}"
    digest = hashlib.sha256(key.encode()).hexdigest()[:24]
    path = Path(runtime_dir) / f"pond-workspace-modes-{digest}.json"
    result = {"path": str(path), "modes": {}}
    try:
        modes = json.loads(path.read_text())["modes"]
        if not isinstance(modes, dict) or any(
            not key.isdecimal() or mode not in ("scroll", "floating")
            for key, mode in modes.items()
        ):
            raise ValueError("Invalid workspace modes")
        result["modes"] = modes
    except FileNotFoundError:
        pass
    except (OSError, ValueError, KeyError, TypeError):
        result["error"] = "pond.workspace_layout_restore_failed"
    return result


if __name__ == "__main__":
    print(json.dumps(session_state(sys.argv[1], sys.argv[2])))
