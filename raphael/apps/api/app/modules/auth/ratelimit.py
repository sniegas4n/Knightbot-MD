"""Limitation de débit des échecs de connexion (fenêtre glissante, en mémoire).

Clés limitées séparément : l'adresse IP et l'e-mail visé. Un attaquant qui change d'IP reste
bloqué sur l'e-mail ; un attaquant qui essaie plusieurs e-mails reste bloqué sur son IP.
La mémoire suffit pour une instance mono-processus (cas d'un assistant personnel) ; un
déploiement multi-processus devra déplacer ce compteur dans PostgreSQL ou Redis.
"""
import time
from collections import defaultdict, deque
from threading import Lock


class FailureLimiter:
    def __init__(self, max_failures: int, window_seconds: int) -> None:
        self.max_failures = max_failures
        self.window = window_seconds
        self._hits: dict[str, deque[float]] = defaultdict(deque)
        self._lock = Lock()

    def _prune(self, key: str, now: float) -> deque[float]:
        hits = self._hits[key]
        while hits and hits[0] <= now - self.window:
            hits.popleft()
        if not hits:
            self._hits.pop(key, None)
        return hits

    def retry_after(self, *keys: str) -> int:
        """Secondes d'attente si une des clés est bloquée, sinon 0."""
        now = time.monotonic()
        wait = 0.0
        with self._lock:
            for key in keys:
                hits = self._prune(key, now)
                if len(hits) >= self.max_failures:
                    wait = max(wait, hits[0] + self.window - now)
        return int(wait) + 1 if wait > 0 else 0

    def record_failure(self, *keys: str) -> None:
        now = time.monotonic()
        with self._lock:
            for key in keys:
                self._hits[key].append(now)

    def reset(self, *keys: str) -> None:
        with self._lock:
            for key in keys:
                self._hits.pop(key, None)
