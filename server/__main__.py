"""Entry point: `python3 -m server` (run from the messaging-app folder)."""
import uvicorn

from .config import settings

if __name__ == "__main__":
    uvicorn.run("server.app:app", host=settings.host, port=settings.port,
                log_level="info")
