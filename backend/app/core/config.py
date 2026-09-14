from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Конфигурация читается из переменных окружения или .env (см. .env.example)."""

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )

    app_name: str = "FamilyTasks API"
    api_prefix: str = "/v1"
    debug: bool = False

    # SQLite годится для разработки; на VPS — PostgreSQL:
    # postgresql+asyncpg://user:password@localhost:5432/familytasks
    database_url: str = "sqlite+aiosqlite:///./familytasks.db"

    # ОБЯЗАТЕЛЬНО заменить в проде: openssl rand -hex 32
    secret_key: str = "dev-secret-change-me"
    algorithm: str = "HS256"
    access_token_expire_minutes: int = 60
    refresh_token_expire_days: int = 30

    # Мобильному клиенту CORS не нужен, но пригодится для веб-админки.
    cors_origins: list[str] = ["*"]

    # Защита /auth/login от перебора. Считаются только неудачные попытки.
    # По аккаунту — жёстко: это защита конкретного пароля от подбора.
    login_rate_limit_account_attempts: int = 5
    login_rate_limit_account_window_seconds: int = 900
    # По IP — мягче, иначе одна семья за общим NAT заблокирует сама себя.
    login_rate_limit_ip_attempts: int = 20
    login_rate_limit_ip_window_seconds: int = 300

    # Регистрация: считаются ВСЕ попытки, включая успешные — вредна как раз
    # массовая успешная. Пять аккаунтов в час с одного адреса хватает семье.
    register_rate_limit_ip_attempts: int = 5
    register_rate_limit_ip_window_seconds: int = 3600


@lru_cache
def get_settings() -> Settings:
    return Settings()


settings = get_settings()
