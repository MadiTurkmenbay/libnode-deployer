-- ============================================================================
-- backfill-media-keys.sql
-- ----------------------------------------------------------------------------
-- Назначение:
--   Конвертирует уже существующие АБСОЛЮТНЫЕ MinIO-URL в медиа-колонках в чистый
--   ОБЪЕКТНЫЙ КЛЮЧ (например 'https://storage.example/libnode/avatars/abc.webp'
--   -> 'avatars/abc.webp'). Это операторский скрипт, НЕ EF-миграция.
--
-- Когда запускать:
--   1) ПОСЛЕ деплоя кода, который теперь хранит КЛЮЧИ (а не абсолютные URL) и
--      собирает публичный URL на чтении из Storage:PublicUrl / MINIO_PUBLIC_URL.
--   2) Вместе с (или непосредственно перед) выставлением корректного публичного
--      MINIO_PUBLIC_URL. После бэкфилла смена домена становится config-only:
--      достаточно поменять MINIO_PUBLIC_URL и перезапустить API.
--
-- Свойства:
--   * Консервативный: трогает ТОЛЬКО строки, чьё значение похоже на URL нашего
--     бакета (содержит '/<bucket>/'). Внешние CDN-URL, относительные значения и
--     NULL остаются без изменений.
--   * Идемпотентный: повторный запуск не меняет уже сконвертированные ключи
--     (у них нет схемы http(s):// и подстроки '/<bucket>/' в начале).
--   * Обёрнут в транзакцию с превью. По умолчанию делает ROLLBACK — оператор
--     раскомментирует COMMIT после проверки превью.
--
-- Затрагиваемые колонки:
--   "Users"."AvatarUrl", "Users"."AvatarThumbUrl",
--   "Books"."CoverUrl",  "Books"."CoverThumbUrl"
-- ============================================================================

-- !!! ОПЕРАТОР: задайте имя бакета. По умолчанию 'libnode' (см. MINIO_BUCKET). !!!
-- Используется в регулярке как '/<bucket>/' — точка отсчёта, после которой идёт ключ.
\set bucket 'libnode'

-- Регулярка: срезает префикс 'scheme://host[:port]/<bucket>/' с НАЧАЛА строки,
-- оставляя только ключ объекта. Работает для http и https, с портом и без.
--   ^https?://         — схема
--   [^/]+              — host[:port]
--   /libnode/          — /<bucket>/ (подставляется из :bucket ниже)
-- Замена выполняется только если значение действительно начинается с такого
-- абсолютного URL нашего бакета (см. WHERE), иначе значение не трогаем.

BEGIN;

-- ── 1) ПРЕВЬЮ: что будет изменено (выполните и проверьте ПЕРЕД COMMIT) ──────
\echo '=== PREVIEW: Users.AvatarUrl / AvatarThumbUrl ==='
SELECT "Id",
       "AvatarUrl"       AS old_avatar,
       regexp_replace("AvatarUrl",      '^https?://[^/]+/' || :'bucket' || '/', '') AS new_avatar,
       "AvatarThumbUrl"  AS old_avatar_thumb,
       regexp_replace("AvatarThumbUrl", '^https?://[^/]+/' || :'bucket' || '/', '') AS new_avatar_thumb
FROM "Users"
WHERE ("AvatarUrl"      ~ ('^https?://[^/]+/' || :'bucket' || '/'))
   OR ("AvatarThumbUrl" ~ ('^https?://[^/]+/' || :'bucket' || '/'));

\echo '=== PREVIEW: Books.CoverUrl / CoverThumbUrl ==='
SELECT "Id",
       "CoverUrl"       AS old_cover,
       regexp_replace("CoverUrl",      '^https?://[^/]+/' || :'bucket' || '/', '') AS new_cover,
       "CoverThumbUrl"  AS old_cover_thumb,
       regexp_replace("CoverThumbUrl", '^https?://[^/]+/' || :'bucket' || '/', '') AS new_cover_thumb
FROM "Books"
WHERE ("CoverUrl"      ~ ('^https?://[^/]+/' || :'bucket' || '/'))
   OR ("CoverThumbUrl" ~ ('^https?://[^/]+/' || :'bucket' || '/'));

-- ── 2) UPDATE: конвертация абсолютных URL нашего бакета в ключи ─────────────
UPDATE "Users"
SET "AvatarUrl" = regexp_replace("AvatarUrl", '^https?://[^/]+/' || :'bucket' || '/', '')
WHERE "AvatarUrl" ~ ('^https?://[^/]+/' || :'bucket' || '/');

UPDATE "Users"
SET "AvatarThumbUrl" = regexp_replace("AvatarThumbUrl", '^https?://[^/]+/' || :'bucket' || '/', '')
WHERE "AvatarThumbUrl" ~ ('^https?://[^/]+/' || :'bucket' || '/');

UPDATE "Books"
SET "CoverUrl" = regexp_replace("CoverUrl", '^https?://[^/]+/' || :'bucket' || '/', '')
WHERE "CoverUrl" ~ ('^https?://[^/]+/' || :'bucket' || '/');

UPDATE "Books"
SET "CoverThumbUrl" = regexp_replace("CoverThumbUrl", '^https?://[^/]+/' || :'bucket' || '/', '')
WHERE "CoverThumbUrl" ~ ('^https?://[^/]+/' || :'bucket' || '/');

-- ── 3) POST-CHECK: убедитесь, что не осталось абсолютных URL нашего бакета ──
\echo '=== POST-CHECK: rows still holding absolute bucket URLs (expect 0) ==='
SELECT 'Users.AvatarUrl'      AS col, count(*) FROM "Users" WHERE "AvatarUrl"      ~ ('^https?://[^/]+/' || :'bucket' || '/')
UNION ALL
SELECT 'Users.AvatarThumbUrl' AS col, count(*) FROM "Users" WHERE "AvatarThumbUrl" ~ ('^https?://[^/]+/' || :'bucket' || '/')
UNION ALL
SELECT 'Books.CoverUrl'       AS col, count(*) FROM "Books" WHERE "CoverUrl"       ~ ('^https?://[^/]+/' || :'bucket' || '/')
UNION ALL
SELECT 'Books.CoverThumbUrl'  AS col, count(*) FROM "Books" WHERE "CoverThumbUrl"  ~ ('^https?://[^/]+/' || :'bucket' || '/');

-- ── 4) ЗАВЕРШЕНИЕ ───────────────────────────────────────────────────────────
-- По умолчанию НЕ применяем изменения. Проверьте превью/пост-чек выше, затем
-- ЛИБО оставьте ROLLBACK (ничего не меняется), ЛИБО закомментируйте ROLLBACK и
-- раскомментируйте COMMIT, чтобы зафиксировать конвертацию.
ROLLBACK;
-- COMMIT;
