# LibNode Deployer

Docker Compose оркестрация для всего стека LibNode: backend API, reader frontend, translator admin/worker.

## Что внутри

- `docker-compose.yml` — canonical production-like стек.
- `docker-compose.dev.yml` — override для локальной разработки (Swagger включён, Basic Auth выключен, rate limiting выключен, `AllowedHosts=*`).
- `docker-compose.verify.yml` — disposable overlay с собственными PostgreSQL/Redis для проверки миграций и регрессионных тестов.
- `VERIFY.md` — полная матрица верификации и пошаговые команды.

## Быстрый старт (production-like)

> Предполагается, что у вас уже есть внешние PostgreSQL и Redis, а `.env` файл заполнен.

```bash
cd /home/qustust/projects/libnodeProject/libnode-deployer

# 1. Проверить конфигурацию (без вывода expanded config)
docker compose --env-file .env config --quiet

# 2. Пересобрать все образы
docker compose --env-file .env build --parallel

# 3. Запустить стек
#    translator-init сделает Prisma migrate + seed и остановится
#    api поднимется после того, как init отработает
#    translator-web и translator-worker тоже зависят от init
docker compose --env-file .env up -d

# 4. Проверить сервисы
curl -sS http://localhost:5000/api/books?limit=1
curl -sS http://localhost:3001/          # Nuxt frontend
curl -sS http://localhost:3005/health    # translator web

# 5. Смотреть логи
docker compose --env-file .env logs -f api
docker compose --env-file .env logs -f web
docker compose --env-file .env logs -f translator-worker

# 6. Остановить
docker compose --env-file .env down
```

## Быстрый старт (локальная разработка)

```bash
cd /home/qustust/projects/libnodeProject/libnode-deployer

# Используем dev override: Swagger включён, Basic Auth выключен, AllowedHosts=*
docker compose --env-file .env.example -f docker-compose.yml -f docker-compose.dev.yml up -d

# Остановить
docker compose --env-file .env.example -f docker-compose.yml -f docker-compose.dev.yml down
```

## Настройка `.env` для продакшена

Скопируйте `.env.example` в `.env` и заполните реальные значения:

```bash
cp .env.example .env
# отредактируйте .env
```

Ключевые переменные:

| Переменная | Описание | Пример |
|------------|----------|--------|
| `DB_CONNECTION_STRING` | PostgreSQL для backend API | `Host=postgres;Port=5432;Database=libnode;Username=libnode;Password=...` |
| `JWT_SIGNING_KEY` | Секрет подписи JWT (минимум 32 символа) | `...` |
| `TRANSLATOR_API_KEY` | API key для публикации переводов | `...` |
| `CORS_ORIGIN` | Origin фронтенда | `https://libnode.qustust.ru` |
| `API_BASE_URL` | URL API для браузера | `https://libnode.qustust.ru` |
| `AllowedHosts` | Домен, который принимает backend | `libnode.qustust.ru` |
| `ForwardedHeaders__Enabled` | `true` за reverse proxy | `true` |
| `TRANSLATOR_DATABASE_URL` | PostgreSQL для translator | `postgresql://...` |
| `TRANSLATOR_REDIS_URL` | Redis для translator | `redis://...` |
| `TRANSLATOR_OPENAI_API_KEY` | API key LLM | `...` |
| `TRANSLATOR_BASIC_AUTH_USERNAME` | Админ translator | не `admin` и не `placeholder-*` |
| `TRANSLATOR_BASIC_AUTH_PASSWORD` | Пароль админа translator | сильный пароль |
| `TRANSLATOR_CSRF_SECRET` | Секрет CSRF | высокая энтропия |

### Важно: `AllowedHosts`

Если сайт открыт по `https://libnode.qustust.ru/`, а `AllowedHosts` оставлено по умолчанию `libnode-api`, Kestrel вернёт:

```
400 Bad Request - Invalid Hostname
```

Решение: в `.env` установите:

```bash
AllowedHosts=libnode.qustust.ru
```

Несколько хостов через точку с запятой:

```bash
AllowedHosts=libnode.qustust.ru;www.libnode.qustust.ru
```

## Reverse proxy

Для публичного домена рекомендуется Nginx/Traefik/Caddy перед Compose. Минимальная конфигурация Nginx:

```nginx
server {
    listen 443 ssl;
    server_name libnode.qustust.ru;

    # SSL certificates

    location / {
        proxy_pass http://127.0.0.1:3001;  # Nuxt frontend
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-Host $host;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }

    location /api/ {
        proxy_pass http://127.0.0.1:5000;  # ASP.NET backend
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-Host $host;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }

    location /reader/ {
        proxy_pass http://127.0.0.1:5000;
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-Host $host;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
}
```

Translator admin лучше вынести на отдельный порт/домен (`https://translator.libnode.qustust.ru`, проксируется на `127.0.0.1:3005`).

### Nginx Proxy Manager (NPM)

В NPM по умолчанию заголовок `Host` может заменяться на upstream-имя или IP. Если backend возвращает `400 Bad Request - Invalid Hostname`, хотя в `.env` уже прописан `AllowedHosts=libnode.qustust.ru`, значит до API доходит не тот `Host`.

**Главное:** не проксируйте `/api/*` через frontend-контейнер (`web:3000`). Nuxt при проксировании во внутреннюю Docker-сеть (`api:8080`) меняет `Host` на `api:8080`, и Kestrel отказывает. Правильно: NPM сам маршрутизирует `/api/*` напрямую на backend (`api:5000`).

Проверка локально (должно вернуть 200):

```bash
curl -H "Host: libnode.qustust.ru" http://localhost:5000/api/books?limit=1
```

Если сработало, а через NPM нет — проблема в маршрутизации. Настройка NPM:

1. Создайте Proxy Host для `libnode.qustust.ru`.
2. **Forward Hostname / IP** — IP хоста, где крутится Docker (например, `100.126.73.77`).
3. **Forward Port** — `3001` (frontend).
4. Вкладка **Advanced** → добавьте custom locations:

```nginx
location /api/ {
    proxy_pass http://100.126.73.77:5000;
    proxy_set_header Host $host;
    proxy_set_header X-Forwarded-Host $host;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Real-IP $remote_addr;
}

location /reader/ {
    proxy_pass http://100.126.73.77:5000;
    proxy_set_header Host $host;
    proxy_set_header X-Forwarded-Host $host;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Real-IP $remote_addr;
}

# Для /assets/ и остальных путей — остаётся на frontend (NPM сделает сам по Forward IP/Port)
```

5. Если NPM и backend в одной Docker-сети, можно использовать `http://api:8080` вместо `100.126.73.77:5000`. Но в типичном случае NPM находится вне сети `libnode-deployer`, поэтому используйте IP хоста и опубликованные порты (`5000`, `3001`, `3005`).

6. Сохраните и проверьте:

```bash
curl -sS https://libnode.qustust.ru/api/books?limit=1
```

Должен вернуть JSON, а не `400 Bad Request - Invalid Hostname`.

### Альтернатива: отдельный API-домен

Если не хотите возиться с custom locations в NPM, создайте отдельный поддомен:

- `api.libnode.qustust.ru` → `100.126.73.77:5000`
- `libnode.qustust.ru` → `100.126.73.77:3001`

В `libnode-deployer/.env`:

```bash
API_BASE_URL=https://api.libnode.qustust.ru
CORS_ORIGIN=https://libnode.qustust.ru
AllowedHosts=api.libnode.qustust.ru
```

Тогда браузер будет ходить на API напрямую, минуя frontend-прокси, и проблемы с `Host` не будет.

## Проверка перед релизом

Полная матрица верификации описана в `VERIFY.md`. Кратко:

```bash
# Валидация конфигурации
docker compose --env-file .env.example config --quiet

# Disposable overlay: миграции, тесты, translator smoke
# (требуется .env.verify с реальными placeholder-заменами)
docker compose -p libnode_verify --env-file .env.verify -f docker-compose.yml -f docker-compose.verify.yml config --quiet
docker compose -p libnode_verify --env-file .env.verify -f docker-compose.yml -f docker-compose.verify.yml run --rm api-migrate
docker compose -p libnode_verify --env-file .env.verify -f docker-compose.yml -f docker-compose.verify.yml run --rm api-tests
docker compose -p libnode_verify --env-file .env.verify -f docker-compose.yml -f docker-compose.verify.yml run --rm translator-init
docker compose -p libnode_verify --env-file .env.verify -f docker-compose.yml -f docker-compose.verify.yml up -d translator-web translator-worker
curl -sS http://localhost:13005/health
# cleanup
docker compose -p libnode_verify --env-file .env.verify -f docker-compose.yml -f docker-compose.verify.yml down -v --remove-orphans
```

## Сервисы и порты

| Сервис | Внутренний порт | Хост порт по умолчанию | Роль |
|--------|----------------|------------------------|------|
| `api` | `8080` | `5000` | ASP.NET Core reader API |
| `web` | `3000` | `3001` | Nuxt 3 SSR frontend |
| `translator-init` | — | — | One-off Prisma migrate + seed |
| `translator-web` | `3005` | `3005` | Express admin/API |
| `translator-worker` | — | — | BullMQ workers |

## Секреты

- Никогда не коммитьте `.env`, `.env.verify`, `.env.local`, Playwright storage state, browser profiles, логи.
- `docker compose config` может раскрыть секреты — используйте `config --quiet` и не копируйте полный вывод в чаты/документы.
- Подробности о secret-safe работе см. в `AI_INSTRUCTIONS.md`.
