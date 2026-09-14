import math
from datetime import UTC, datetime

from fastapi import APIRouter, HTTPException, Request, Response, status
from sqlalchemy import delete, func, select

from app.api.deps import CurrentUser, SessionDep
from app.core.config import settings
from app.core.datetime_utils import as_aware, utc_now
from app.core.rate_limit import RateLimitRule, auth_limiter
from app.core.security import (
    create_access_token,
    generate_invite_code,
    generate_refresh_token,
    hash_password,
    hash_refresh_token,
    refresh_token_expiry,
    verify_password,
)
from app.db.models import Family, FamilyRole, RefreshToken, User
from app.schemas.auth import AuthOut, LoginIn, RefreshIn, RegisterIn, TokensOut
from app.schemas.user import UserOut

router = APIRouter(tags=["auth"])

# Цвета аватаров раздаём по кругу, чтобы члены семьи различались в списке.
AVATAR_COLORS = ["#3B82F6", "#EC4899", "#10B981", "#F59E0B", "#8B5CF6", "#EF4444"]


# --- Ограничение частоты обращений --------------------------------------------
# Правила читаются из settings на каждом запросе: так их можно менять
# без перезапуска и переопределять в тестах.


def _account_limit(email: str) -> tuple[str, RateLimitRule]:
    rule = RateLimitRule(
        attempts=settings.login_rate_limit_account_attempts,
        window_seconds=settings.login_rate_limit_account_window_seconds,
    )
    return f"login:account:{email}", rule


def _client_host(request: Request) -> str:
    # request.client.host — это реальный адрес только если uvicorn запущен
    # с --proxy-headers за nginx. Без этого флага все запросы выглядят
    # как приходящие с 127.0.0.1, и один перебор заблокирует всех сразу.
    return request.client.host if request.client else "unknown"


def _login_ip_limit(request: Request) -> tuple[str, RateLimitRule]:
    rule = RateLimitRule(
        attempts=settings.login_rate_limit_ip_attempts,
        window_seconds=settings.login_rate_limit_ip_window_seconds,
    )
    return f"login:ip:{_client_host(request)}", rule


def _register_ip_limit(request: Request) -> tuple[str, RateLimitRule]:
    rule = RateLimitRule(
        attempts=settings.register_rate_limit_ip_attempts,
        window_seconds=settings.register_rate_limit_ip_window_seconds,
    )
    return f"register:ip:{_client_host(request)}", rule


def _retry_message(action: str, seconds: int) -> str:
    delay = f"{math.ceil(seconds / 60)} мин." if seconds >= 60 else f"{seconds} с."
    return f"Слишком много попыток {action}. Повторите через {delay}"


async def _enforce_limit(key: str, rule: RateLimitRule, action: str) -> None:
    verdict = await auth_limiter.check(key, rule)
    if verdict.allowed:
        return
    raise HTTPException(
        status_code=status.HTTP_429_TOO_MANY_REQUESTS,
        detail=_retry_message(action, verdict.retry_after),
        headers={"Retry-After": str(verdict.retry_after)},
    )


async def _issue_tokens(session: SessionDep, user: User) -> TokensOut:
    access_token, expires_in = create_access_token(user.id)
    refresh_token = generate_refresh_token()

    # Попутно выносим мусор этого пользователя: просроченные записи
    # не нужны никому — ни для проверки, ни для отзыва. Отдельный планировщик
    # ради этого заводить не стоит, работа ограничена одним пользователем.
    # Отозванные, но ещё не истёкшие оставляем: по ним позже можно будет
    # детектировать повторное использование украденного токена.
    # synchronize_session=False обязателен: иначе ORM попытается вычислить
    # условие в Python, а SQLite отдаёт naive-даты — сравнение с aware падает.
    # Здесь это безопасно: удаляются только записи, которых нет в сессии.
    await session.execute(
        delete(RefreshToken)
        .where(
            RefreshToken.user_id == user.id,
            RefreshToken.expires_at < utc_now(),
        )
        .execution_options(synchronize_session=False)
    )

    session.add(
        RefreshToken(
            user_id=user.id,
            token_hash=hash_refresh_token(refresh_token),
            expires_at=refresh_token_expiry(),
        )
    )

    return TokensOut(
        access_token=access_token,
        refresh_token=refresh_token,
        expires_in=expires_in,
    )


@router.post("/auth/register", response_model=AuthOut)
async def register(payload: RegisterIn, request: Request, session: SessionDep) -> AuthOut:
    ip_key, ip_rule = _register_ip_limit(request)
    await _enforce_limit(ip_key, ip_rule, action="регистрации")
    # Считаем каждую попытку, а не только неудачную: вред здесь наносит
    # как раз успешное массовое создание аккаунтов.
    await auth_limiter.record(ip_key, ip_rule)

    existing = await session.scalar(select(User).where(User.email == payload.email.lower()))
    if existing is not None:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Пользователь с такой почтой уже зарегистрирован.",
        )

    if payload.invite_code:
        family = await session.scalar(
            select(Family).where(Family.invite_code == payload.invite_code.upper())
        )
        if family is None:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Семья с таким кодом приглашения не найдена.",
            )
        role = FamilyRole.child
    else:
        family = Family(name=f"Семья {payload.name}", invite_code=generate_invite_code())
        session.add(family)
        await session.flush()
        role = FamilyRole.parent

    members_count = await session.scalar(
        select(func.count()).select_from(User).where(User.family_id == family.id)
    )
    color_index = (members_count or 0) % len(AVATAR_COLORS)

    user = User(
        family_id=family.id,
        name=payload.name.strip(),
        email=payload.email.lower(),
        password_hash=hash_password(payload.password),
        role=role,
        color_hex=AVATAR_COLORS[color_index],
    )
    session.add(user)
    await session.flush()

    tokens = await _issue_tokens(session, user)
    await session.commit()

    return AuthOut(**tokens.model_dump(), user=UserOut.model_validate(user))


@router.post("/auth/login", response_model=AuthOut)
async def login(payload: LoginIn, request: Request, session: SessionDep) -> AuthOut:
    email = payload.email.lower()
    account_key, account_rule = _account_limit(email)
    ip_key, ip_rule = _login_ip_limit(request)

    # Проверяем ДО обращения к базе и до bcrypt: перебор не должен
    # стоить нам хеширования, оно намеренно медленное.
    await _enforce_limit(account_key, account_rule, action="входа")
    await _enforce_limit(ip_key, ip_rule, action="входа")

    user = await session.scalar(select(User).where(User.email == email))

    # Один и тот же текст для «нет такого пользователя» и «неверный пароль»:
    # иначе эндпоинт превращается в способ проверять, кто зарегистрирован.
    if user is None or not verify_password(payload.password, user.password_hash):
        # Неудачу записываем и для несуществующей почты — иначе 429 приходил бы
        # только по зарегистрированным адресам и сам стал бы утечкой.
        await auth_limiter.record(account_key, account_rule)
        await auth_limiter.record(ip_key, ip_rule)
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Неверная почта или пароль.",
        )

    # Успешный вход обнуляет счётчик аккаунта: хозяин вспомнил пароль.
    # Счётчик IP не трогаем — иначе атакующий со своим аккаунтом
    # сбрасывал бы себе лимит после каждой серии попыток.
    await auth_limiter.reset(account_key)

    tokens = await _issue_tokens(session, user)
    await session.commit()

    return AuthOut(**tokens.model_dump(), user=UserOut.model_validate(user))


@router.post("/auth/refresh", response_model=TokensOut)
async def refresh(payload: RefreshIn, session: SessionDep) -> TokensOut:
    token_hash = hash_refresh_token(payload.refresh_token)
    stored = await session.scalar(select(RefreshToken).where(RefreshToken.token_hash == token_hash))

    invalid = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Refresh-токен недействителен.",
    )

    if stored is None or stored.revoked_at is not None:
        raise invalid
    if as_aware(stored.expires_at) <= datetime.now(UTC):
        raise invalid

    user = await session.get(User, stored.user_id)
    if user is None:
        raise invalid

    # Ротация: старый токен гасим, выдаём новую пару.
    # Перехваченный refresh перестаёт работать после первого же использования владельцем.
    stored.revoked_at = utc_now()
    tokens = await _issue_tokens(session, user)
    await session.commit()

    return tokens


@router.post("/auth/logout", status_code=status.HTTP_204_NO_CONTENT)
async def logout(user: CurrentUser, session: SessionDep) -> Response:
    tokens = await session.scalars(
        select(RefreshToken).where(
            RefreshToken.user_id == user.id,
            RefreshToken.revoked_at.is_(None),
        )
    )
    now = utc_now()
    for token in tokens:
        token.revoked_at = now
    await session.commit()

    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.get("/me", response_model=UserOut)
async def me(user: CurrentUser) -> UserOut:
    return UserOut.model_validate(user)
