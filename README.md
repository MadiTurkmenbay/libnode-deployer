# LibNode Deployer

Docker Compose оркестрация для всего стека LibNode: backend API, reader frontend, translator admin/worker.

## Что внутри

- `docker-compose.yml` — canonical production-like стек.
- `docker-compose.dev.yml` — override для локальной разработки (Swagger включён, Basic Auth выключен, rate limiting выключен, `AllowedHosts=*`).
- `docker-compose.verify.yml` — disposable overlay с собственными PostgreSQL/Redis для проверки миграций и регрессионных тестов.
- `VERIFY.md` — полная матрица верификации и пошаговые команды.

## Быстрый старт (production-like)

> Предполагается, что у вас уже есть внешние PostgreSQL и Redis, а `.env` файл заполнен. Все операции делаются через `Makefile` — это основной интерфейс управления стеком.

```bash
cd /home/qustust/projects/libnodeProject/libnode-deployer

# 1. Проверить конфигурацию (без вывода expanded config)
make verify

# 2. Перезапустить стек с пересборкой образов
#    api-migrate автоматически применит EF Core миграции
#    translator-init сделает Prisma migrate + seed и остановится
#    api поднимется только после успешного api-migrate
make restart

# 3. Проверить сервисы
curl -sS http://localhost:3001/api/books?limit=1  # через Nuxt BFF
curl -sS http://localhost:3001/          # Nuxt frontend
curl -sS http://localhost:3005/health    # translator web

# 4. Смотреть логи
make logs ARGS='-f api'
make logs ARGS='-f web'
make logs ARGS='-f translator-worker'

# 5. Остановить
make down
```

> **Почему `make restart`?** После любого изменения в `libnode/`, `libnode-frontend/` или `libnode-translator/` нужно пересобрать Docker-образы и перезапустить контейнеры. `make restart` делает это одной командой: `down` → `build --parallel` → `up -d` с автоматическими миграциями.

## Быстрый старт (локальная разработка)

```bash
cd /home/qustust/projects/libnodeProject/libnode-deployer

# Используем dev override: Swagger включён, Basic Auth выключен, AllowedHosts=*
docker compose --env-file .env.example -f docker-compose.yml -f docker-compose.dev.yml up -d

# Остановить
docker compose --env-file .env.example -f docker-compose.yml -f docker-compose.dev.yml down
```

Для dev-окружения пока нет `make`-target'ов с `docker-compose.dev.yml`, поэтому используйте прямой `docker compose` как выше.

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
| `AllowedHosts` | Внешний backend-домен; `api` добавляется compose автоматически | `libnode.qustust.ru` |
| `ForwardedHeaders__Enabled` | `true` за reverse proxy | `true` |
| `TRANSLATOR_DATABASE_URL` | PostgreSQL для translator | `postgresql://...` |
| `TRANSLATOR_REDIS_URL` | Redis для translator | `redis://...` |
| `TRANSLATOR_OPENAI_API_KEY` | API key LLM | `...` |
| `TRANSLATOR_BASIC_AUTH_USERNAME` | Админ translator | не `admin` и не `placeholder-*` |
| `TRANSLATOR_BASIC_AUTH_PASSWORD` | Пароль админа translator | сильный пароль |
| `TRANSLATOR_CSRF_SECRET` | Секрет CSRF | высокая энтропия |

### Важно: `AllowedHosts`

Если backend открыт напрямую по публичному домену, этот домен должен быть в `AllowedHosts`; иначе Kestrel вернёт `400 Bad Request - Invalid Hostname` для прямых backend-запросов.

В `.env` установите только внешний backend hostname. Внутреннее Docker-имя `api` compose добавляет автоматически:

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
        proxy_pass http://127.0.0.1:3001;  # Nuxt frontend + same-origin /api BFF
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-Host $host;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
}
```

Translator admin лучше вынести на отдельный порт/домен (`https://translator.libnode.qustust.ru`, проксируется на `127.0.0.1:3005`).

### Nginx Proxy Manager (NPM)

Текущая auth-схема использует Nuxt BFF: browser ходит на same-origin `/api/*`, Nuxt читает HttpOnly cookie `auth_token` и сервером добавляет `Authorization` к backend. Поэтому `/api/*` должен попадать в `web:3000`, а не напрямую в backend. Иначе login/register/profile update обойдут cookie-слой и могут вернуть JWT в browser response.

Проверка backend напрямую остаётся полезной только как сервисная диагностика:

```bash
curl -H "Host: libnode.qustust.ru" http://localhost:5000/api/books?limit=1
```

Настройка NPM:

1. Создайте Proxy Host для `libnode.qustust.ru`.
2. **Forward Hostname / IP** — IP хоста, где крутится Docker (например, `100.126.73.77`).
3. **Forward Port** — `3001` (frontend).
4. Не добавляйте custom location для `/api/`; этот путь должен обслуживать Nuxt BFF.
5. Сохраните и проверьте:

```bash
curl -sS https://libnode.qustust.ru/api/books?limit=1
```

Должен вернуть JSON через frontend BFF.

### Альтернатива: отдельный API-домен

Отдельный API-домен можно использовать для сервисной диагностики или внешних non-browser клиентов, но не как browser-facing endpoint для основного frontend auth-flow:

- `api.libnode.qustust.ru` → `100.126.73.77:5000`
- `libnode.qustust.ru` → `100.126.73.77:3001`

В `libnode-deployer/.env`:

```bash
CORS_ORIGIN=https://libnode.qustust.ru
AllowedHosts=api.libnode.qustust.ru
```

Основной frontend всё равно должен отправлять browser `/api/*` на Nuxt BFF, чтобы HttpOnly cookie contract сохранялся.

## Проверка перед релизом

Полная матрица верификации описана в `VERIFY.md`. Кратко:

```bash
# Валидация конфигурации
docker compose --env-file .env.example config --quiet

# Disposable overlay: миграции, тесты, translator smoke
docker compose -p libnode_verify --env-file .env.verify.example -f docker-compose.yml -f docker-compose.verify.yml config --quiet
docker compose -p libnode_verify --env-file .env.verify.example -f docker-compose.yml -f docker-compose.verify.yml run --rm api-migrate
docker compose -p libnode_verify --env-file .env.verify.example -f docker-compose.yml -f docker-compose.verify.yml run --rm api-tests
docker compose -p libnode_verify --env-file .env.verify.example -f docker-compose.yml -f docker-compose.verify.yml run --rm translator-init
docker compose -p libnode_verify --env-file .env.verify.example -f docker-compose.yml -f docker-compose.verify.yml up -d translator-web translator-worker
curl -sS http://localhost:13005/health
# cleanup
docker compose -p libnode_verify --env-file .env.verify.example -f docker-compose.yml -f docker-compose.verify.yml down -v --remove-orphans
```

## Изолированные translator queue-тесты

```bash
make verify-translator-queue
make test-translator-queue
make test-translator-queue QUEUE_TEST_MODE=offline
make test-translator-queue QUEUE_TEST_MODE=checks
make test-translator-queue QUEUE_TEST_MODE=failure-check
```

Это отдельный opt-in профиль `translator-queue-tests` существующего verify overlay, не запуск живого стека. Каждая команда генерирует новый непереопределяемый Compose project `libnode-translator-queue-*` и использует только `.env.verify.example`, игнорируя production `COMPOSE`/`ENV_FILE`/`VERIFY_ENV_FILE` и shell endpoint overrides. `integration` и `failure-check` запускают только disposable PostgreSQL/Redis и `translator-tests` из tools image; `offline` — обычный `npm test`, `checks` — type/lint без зависимостей. Runtime/Vite flow не меняется, пакеты не добавляются. Тестовый контейнер без published ports, bind mounts или live env file подключён только к internal network.

`TEST_DATABASE_URL`/`TEST_REDIS_URL`, `TEST_TRANSLATOR_QUEUE=1`, `NODE_ENV=test` проверяются до миграции/подключения: только тестовые service DNS/порты/БД, без production fallback, query/fragment и Redis credentials. Prisma миграции идут внутри tools container, `DATABASE_URL` задаётся только в проверенном CLI child. Cleanup по EXIT/INT/TERM удаляет только собственный project и проверяет отсутствие containers/networks/volumes; expected exit 42 в `failure-check` считается успехом только вместе с доказанной очисткой.

Проверяются реальные production services/repositories/BullMQ/Prisma и registered-worker final failure (около 35 секунд реальных retry waits), не live LLM/browser/source/admin HTTP или production migration. Pause — **глобальный** для всех проектов: active работа может завершиться, pending других проектов ждёт, их DB status/history сохраняются. Resume любого проекта снимает общую паузу. Полная матрица, ограничения и повторный запуск — в `VERIFY.md`. Test-only изменения не требуют рестарта live stack; runtime fix потребовал бы отдельного согласованного `make restart`.

## Изолированные browser-проверки reader

```bash
make verify-reader-e2e
make test-reader-e2e READER_E2E_MODE=checks
make test-reader-e2e READER_E2E_MODE=backend-unit
make test-reader-e2e
make test-reader-e2e READER_E2E_MODE=failure-check
```

Реальные API/Nuxt/Chromium и временная PostgreSQL в новом `libnode-reader-e2e-*` project. Только example-конфигурация, без рабочих данных, published ports, внешних вызовов или запуска translator. `checks` — offline Vitest и guards, `backend-unit` — focused collection tests, `failure-check` — намеренный exit 42 после создания тестовой книги. На каждом выходе удаляются только собственные ресурсы и проверяются нулевые остатки. Требуются Docker Compose/Buildx с `additional_contexts` и `dockerfile_inline`. Полная матрица и границы проверки — в `VERIFY.md`; live restart этим target не выполняется.

## Сервисы и порты

| Сервис | Внутренний порт | Хост порт по умолчанию | Роль |
|--------|----------------|------------------------|------|
| `api` | `8080` | `5000` | ASP.NET Core reader API |
| `web` | `3000` | `3001` | Nuxt 3 SSR frontend |
| `minio` | `9000`/`9001` | `9000`/`9001` | S3-compatible storage for covers/avatars |
| `minio-init` | — | — | One-off bucket initialization |
| `translator-init` | — | — | One-off Prisma migrate + seed |
| `translator-web` | `3005` | `3005` | Express admin/API |
| `translator-worker` | — | — | BullMQ workers |

## Секреты

- Никогда не коммитьте `.env`, `.env.verify`, `.env.local`, Playwright storage state, browser profiles, логи.
- `docker compose config` может раскрыть секреты — используйте `config --quiet` и не копируйте полный вывод в чаты/документы.
- Подробности о secret-safe работе см. в `AI_INSTRUCTIONS.md`.
