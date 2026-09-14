"""Модульные тесты самого лимитера: с поддельными часами, без сети и сна."""

import pytest

from app.core.rate_limit import InMemoryRateLimiter, RateLimitRule

RULE = RateLimitRule(attempts=3, window_seconds=60)


class FakeClock:
    def __init__(self, start: float = 1000.0) -> None:
        self.now = start

    def __call__(self) -> float:
        return self.now

    def advance(self, seconds: float) -> None:
        self.now += seconds


@pytest.fixture
def clock() -> FakeClock:
    return FakeClock()


@pytest.fixture
def limiter(clock: FakeClock) -> InMemoryRateLimiter:
    return InMemoryRateLimiter(clock=clock)


async def test_allows_until_attempts_exhausted(limiter):
    for _ in range(3):
        assert (await limiter.check("k", RULE)).allowed
        await limiter.record("k", RULE)

    verdict = await limiter.check("k", RULE)
    assert verdict.allowed is False
    assert verdict.retry_after == 60


async def test_window_slides_forward(limiter, clock):
    for _ in range(3):
        await limiter.record("k", RULE)
    assert not (await limiter.check("k", RULE)).allowed

    # Окно скользящее: через 30 с истекает не всё сразу.
    clock.advance(30)
    assert not (await limiter.check("k", RULE)).allowed

    clock.advance(31)
    assert (await limiter.check("k", RULE)).allowed


async def test_retry_after_counts_down(limiter, clock):
    for _ in range(3):
        await limiter.record("k", RULE)

    clock.advance(45)
    verdict = await limiter.check("k", RULE)
    assert verdict.retry_after == 15


async def test_retry_after_is_never_zero(limiter, clock):
    for _ in range(3):
        await limiter.record("k", RULE)

    # Ровно на границе окна: клиенту нельзя отдавать Retry-After: 0.
    clock.advance(59.5)
    assert (await limiter.check("k", RULE)).retry_after == 1


async def test_reset_clears_counter(limiter):
    for _ in range(3):
        await limiter.record("k", RULE)
    assert not (await limiter.check("k", RULE)).allowed

    await limiter.reset("k")
    assert (await limiter.check("k", RULE)).allowed


async def test_keys_are_independent(limiter):
    for _ in range(3):
        await limiter.record("first", RULE)

    assert not (await limiter.check("first", RULE)).allowed
    assert (await limiter.check("second", RULE)).allowed


async def test_expired_keys_are_forgotten(limiter, clock):
    await limiter.record("k", RULE)
    assert limiter._expiries

    clock.advance(61)
    await limiter.check("k", RULE)

    # Без очистки словарь рос бы на каждый новый IP и не уменьшался.
    assert not limiter._expiries
