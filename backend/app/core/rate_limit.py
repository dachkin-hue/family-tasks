import asyncio
import math
import time
from collections import deque
from collections.abc import Callable
from dataclasses import dataclass
from typing import Protocol


@dataclass(frozen=True, slots=True)
class RateLimitRule:
    """Не более `attempts` неудач за `window_seconds`."""

    attempts: int
    window_seconds: int


@dataclass(frozen=True, slots=True)
class RateLimitVerdict:
    allowed: bool
    retry_after: int = 0


class RateLimiter(Protocol):
    """Счётчик событий с окном.

    Что именно считать, решает вызывающий: вход записывает только неудачи
    (успешный вход не должен расходовать лимит), а регистрация — каждую
    попытку, потому что там вредна как раз успешная массовая операция.
    """

    async def check(self, key: str, rule: RateLimitRule) -> RateLimitVerdict:
        """Проверка без изменения счётчика."""
        ...

    async def record(self, key: str, rule: RateLimitRule) -> None: ...

    async def reset(self, key: str) -> None: ...


_EMPTY: deque[float] = deque()  # только для чтения


class InMemoryRateLimiter:
    """Скользящее окно в памяти процесса.

    ВАЖНО: состояние не разделяется между процессами. При запуске uvicorn
    с несколькими воркерами фактический лимит умножается на их число.
    Поэтому в Dockerfile стоит `--workers 1`; если понадобится больше —
    реализуйте этот же протокол поверх Redis (INCR + EXPIRE) и подмените
    `auth_limiter` в этом модуле. Остальной код менять не придётся.
    """

    _SWEEP_EVERY = 500

    def __init__(self, clock: Callable[[], float] = time.monotonic) -> None:
        # Храним не моменты попыток, а моменты их истечения — тогда очистка
        # не зависит от того, по какому правилу запись была создана.
        self._expiries: dict[str, deque[float]] = {}
        self._lock = asyncio.Lock()
        self._clock = clock
        self._writes = 0

    async def check(self, key: str, rule: RateLimitRule) -> RateLimitVerdict:
        now = self._clock()
        async with self._lock:
            expiries = self._prune(key, now)
            if len(expiries) < rule.attempts:
                return RateLimitVerdict(allowed=True)
            return RateLimitVerdict(allowed=False, retry_after=max(1, math.ceil(expiries[0] - now)))

    async def record(self, key: str, rule: RateLimitRule) -> None:
        now = self._clock()
        async with self._lock:
            expiries = self._expiries.setdefault(key, deque())
            while expiries and expiries[0] <= now:
                expiries.popleft()
            expiries.append(now + rule.window_seconds)
            self._sweep_if_needed(now)

    async def reset(self, key: str) -> None:
        async with self._lock:
            self._expiries.pop(key, None)

    async def reset_all(self) -> None:
        """Нужен тестам; в бою не вызывается."""
        async with self._lock:
            self._expiries.clear()
            self._writes = 0

    # --- внутреннее ---------------------------------------------------------

    def _prune(self, key: str, now: float) -> deque[float]:
        expiries = self._expiries.get(key)
        if expiries is None:
            return _EMPTY
        while expiries and expiries[0] <= now:
            expiries.popleft()
        if not expiries:
            del self._expiries[key]
            return _EMPTY
        return expiries

    def _sweep_if_needed(self, now: float) -> None:
        """Иначе словарь растёт на каждый новый IP и никогда не уменьшается."""
        self._writes += 1
        if self._writes < self._SWEEP_EVERY:
            return
        self._writes = 0
        for key in list(self._expiries):
            self._prune(key, now)


# Единственный экземпляр на процесс.
auth_limiter: RateLimiter = InMemoryRateLimiter()
