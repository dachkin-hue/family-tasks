FROM python:3.12-slim

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /srv/app

# Слой с зависимостями кэшируется отдельно от кода.
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app ./app
COPY migrations ./migrations
COPY alembic.ini ./alembic.ini

# Приложение работает не от root.
RUN useradd --create-home --uid 10001 appuser && chown -R appuser:appuser /srv/app
USER appuser

EXPOSE 8000

# --workers 1: счётчик попыток входа живёт в памяти процесса, и на двух
# воркерах фактический лимит удвоился бы. Для семейного приложения одного
# воркера с запасом достаточно; если понадобится больше — сначала перенесите
# RateLimiter в Redis (см. app/core/rate_limit.py).
#
# --proxy-headers обязателен: без него все запросы выглядят как пришедшие
# с адреса nginx, и лимит по IP заблокировал бы всех сразу.
# Миграции накатываются перед стартом. Это безопасно ровно потому, что
# воркер один: два процесса стартовали бы `upgrade head` одновременно.
CMD ["sh", "-c", "alembic upgrade head && exec uvicorn app.main:app --host 0.0.0.0 --port 8000 --workers 1 --proxy-headers --forwarded-allow-ips '*'"]
