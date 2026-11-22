"""Boots a real server subprocess on a free port with a temp DB."""
import os
import socket
import subprocess
import sys
import tempfile
import time
from pathlib import Path

import httpx
import pytest

TESTS_DIR = Path(__file__).resolve().parent
PROJECT_ROOT = TESTS_DIR.parents[1]          # messaging-app/
sys.path.insert(0, str(TESTS_DIR))

ADMIN_KEY = "test-admin-key"


def free_port() -> int:
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


@pytest.fixture(scope="session")
def server_env():
    port = free_port()
    # NOTE: keep the temp DB on the project disk — /tmp may be a tiny tmpfs.
    tmp = tempfile.mkdtemp(prefix="dexterchat-test-", dir=PROJECT_ROOT)
    db_path = os.path.join(tmp, "test.db")
    env = dict(os.environ,
               MSG_DB=db_path, MSG_PORT=str(port), MSG_HOST="127.0.0.1",
               MSG_ADMIN_KEY=ADMIN_KEY, MSG_DEV_MODE="1",
               MSG_SWEEP_INTERVAL="0.5")
    proc = subprocess.Popen(
        [sys.executable, "-m", "server"], cwd=PROJECT_ROOT, env=env,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    base = f"http://127.0.0.1:{port}"
    try:
        deadline = time.time() + 90
        while time.time() < deadline:
            try:
                if httpx.get(base + "/health", timeout=2,
                             trust_env=False).status_code == 200:
                    break
            except Exception:
                time.sleep(0.2)
        else:
            proc.terminate()
            try:
                out, _ = proc.communicate(timeout=5)
            except Exception:
                proc.kill()
                out, _ = proc.communicate()
            raise RuntimeError(f"server did not start:\n{out}")
        yield {"base": base, "db_path": db_path, "admin_key": ADMIN_KEY}
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=5)
        except Exception:
            proc.kill()


@pytest.fixture()
def make_invite(server_env):
    def _make() -> str:
        r = httpx.post(server_env["base"] + "/admin/invites",
                       headers={"X-Admin-Key": server_env["admin_key"]},
                       timeout=10, trust_env=False)
        r.raise_for_status()
        return r.json()["invite_code"]
    return _make
