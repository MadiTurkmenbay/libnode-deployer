-- Emergency migration script for production database.
-- Run this if __EFMigrationsHistory is empty/missing and the database already
-- contains the schema from all migrations except AddQuotes.

-- Create migrations history table if it does not exist.
CREATE TABLE IF NOT EXISTS "__EFMigrationsHistory" (
    "MigrationId" character varying(150) NOT NULL,
    "ProductVersion" character varying(32) NOT NULL,
    CONSTRAINT "PK___EFMigrationsHistory" PRIMARY KEY ("MigrationId")
);

-- Mark all baseline migrations as applied so EF does not try to recreate them.
INSERT INTO "__EFMigrationsHistory" ("MigrationId", "ProductVersion")
VALUES
    ('20260411160957_InitialCreate', '10.0.9'),
    ('20260411195549_AddUserEntity', '10.0.9'),
    ('20260411204427_AddUserCollections', '10.0.9'),
    ('20260411222122_AddChapterLike', '10.0.9'),
    ('20260413021616_AddBookMetadata', '10.0.9'),
    ('20260413050000_AddReadingProgress', '10.0.9'),
    ('20260413171721_AddReaderIngestSlug', '10.0.9'),
    ('20260614035556_EfCore10Baseline', '10.0.9')
ON CONFLICT ("MigrationId") DO NOTHING;

-- Create the Quotes table if it does not exist.
CREATE TABLE IF NOT EXISTS "Quotes" (
    "Id" uuid NOT NULL DEFAULT gen_random_uuid(),
    "UserId" uuid NOT NULL,
    "ChapterId" uuid NOT NULL,
    "BookId" uuid NOT NULL,
    "SelectedText" text NOT NULL,
    "ContextText" character varying(5000) NULL,
    "Note" character varying(2000) NULL,
    "CreatedAt" timestamp with time zone NOT NULL DEFAULT now(),
    "UpdatedAt" timestamp with time zone NOT NULL DEFAULT now(),
    CONSTRAINT "PK_Quotes" PRIMARY KEY ("Id"),
    CONSTRAINT "FK_Quotes_Books_BookId" FOREIGN KEY ("BookId") REFERENCES "Books" ("Id") ON DELETE CASCADE,
    CONSTRAINT "FK_Quotes_Chapters_ChapterId" FOREIGN KEY ("ChapterId") REFERENCES "Chapters" ("Id") ON DELETE CASCADE,
    CONSTRAINT "FK_Quotes_Users_UserId" FOREIGN KEY ("UserId") REFERENCES "Users" ("Id") ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS "IX_Quotes_BookId_UserId" ON "Quotes" ("BookId", "UserId");
CREATE INDEX IF NOT EXISTS "IX_Quotes_ChapterId" ON "Quotes" ("ChapterId");
CREATE INDEX IF NOT EXISTS "IX_Quotes_UserId_CreatedAt" ON "Quotes" ("UserId", "CreatedAt");

-- Mark the AddQuotes migration as applied.
INSERT INTO "__EFMigrationsHistory" ("MigrationId", "ProductVersion")
VALUES ('20260614140129_AddQuotes', '10.0.9')
ON CONFLICT ("MigrationId") DO NOTHING;
