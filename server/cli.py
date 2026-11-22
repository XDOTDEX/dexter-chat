"""Owner/admin CLI.

Usage (from the messaging-app folder, with the project venv):

    .venv/bin/python -m server.cli create-invite [count]
    .venv/bin/python -m server.cli stats
"""
import sys
import time

from .config import settings
from .db import DB
from .security import new_invite_code


def main(argv: list[str]) -> int:
    db = DB(settings.db_path)
    if len(argv) >= 2 and argv[1] == "create-invite":
        count = int(argv[2]) if len(argv) >= 3 else 1
        for _ in range(count):
            code = new_invite_code()
            db.execute("INSERT INTO invites (code, created_at) VALUES (?, ?)",
                       (code, time.time()))
            print(code)
        return 0
    if len(argv) >= 2 and argv[1] == "stats":
        users = db.query_one("SELECT COUNT(*) AS n FROM users")["n"]
        unused = db.query_one(
            "SELECT COUNT(*) AS n FROM invites WHERE used_by IS NULL")["n"]
        queued = db.query_one("SELECT COUNT(*) AS n FROM messages")["n"]
        print(f"users={users} unused_invites={unused} queued_messages={queued}")
        return 0
    print(__doc__)
    return 2


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
