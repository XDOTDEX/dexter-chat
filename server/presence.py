"""In-memory WebSocket registry + presence.

At this scale (<= ~100 users) presence is simply: who has a live socket,
and when were they last seen. Nothing here is persisted.
"""
import time
from fastapi import WebSocket


class Presence:
    def __init__(self) -> None:
        self.connections: dict[int, set[WebSocket]] = {}
        self.last_seen: dict[int, float] = {}

    def add(self, user_id: int, ws: WebSocket) -> bool:
        """Returns True if this is the user's first live connection."""
        first = not self.connections.get(user_id)
        self.connections.setdefault(user_id, set()).add(ws)
        self.last_seen[user_id] = time.time()
        return first

    def remove(self, user_id: int, ws: WebSocket) -> bool:
        """Returns True if the user just went fully offline."""
        sockets = self.connections.get(user_id)
        if not sockets:
            return False
        sockets.discard(ws)
        self.last_seen[user_id] = time.time()
        if not sockets:
            del self.connections[user_id]
            return True
        return False

    def is_online(self, user_id: int) -> bool:
        return bool(self.connections.get(user_id))

    def last_seen_at(self, user_id: int) -> float | None:
        return self.last_seen.get(user_id)

    async def send_to(self, user_id: int, frame: dict) -> None:
        for ws in list(self.connections.get(user_id, ())):
            try:
                await ws.send_json(frame)
            except Exception:
                pass

    async def broadcast(self, frame: dict) -> None:
        for user_id in list(self.connections.keys()):
            await self.send_to(user_id, frame)


presence = Presence()
