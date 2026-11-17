-- Dev backlog owners (owner: dev, dev.meavo.app): a default owner per app, and
-- several owners per item, each with their own priority-list order.
-- Additive and idempotent: one nullable column on "BacklogApp", one new table, and a
-- backfill that copies each item's existing single owner into the new table.
-- BacklogItem."ownerId" and "focusRank" stay, so older clients keep working.
-- Apply: scripts/apply-sql.sh staging scripts/add-dev-owners.sql --env-file <staging env>

BEGIN;

ALTER TABLE "BacklogApp" ADD COLUMN IF NOT EXISTS "ownerId" TEXT;

CREATE INDEX IF NOT EXISTS "BacklogApp_ownerId_idx" ON "BacklogApp"("ownerId");

DO $$ BEGIN
  ALTER TABLE "BacklogApp"
      ADD CONSTRAINT "BacklogApp_ownerId_fkey"
      FOREIGN KEY ("ownerId") REFERENCES "User"("id") ON DELETE SET NULL ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE TABLE IF NOT EXISTS "BacklogItemOwner" (
    "itemId" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "focusRank" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "BacklogItemOwner_pkey" PRIMARY KEY ("itemId","userId")
);

CREATE INDEX IF NOT EXISTS "BacklogItemOwner_userId_focusRank_idx"
    ON "BacklogItemOwner"("userId", "focusRank");

DO $$ BEGIN
  ALTER TABLE "BacklogItemOwner"
      ADD CONSTRAINT "BacklogItemOwner_itemId_fkey"
      FOREIGN KEY ("itemId") REFERENCES "BacklogItem"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE "BacklogItemOwner"
      ADD CONSTRAINT "BacklogItemOwner_userId_fkey"
      FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- Existing single owners become owner rows, keeping their priority-list order.
INSERT INTO "BacklogItemOwner" ("itemId", "userId", "focusRank")
SELECT "id", "ownerId", "focusRank"
FROM "BacklogItem"
WHERE "ownerId" IS NOT NULL
ON CONFLICT ("itemId", "userId") DO NOTHING;

COMMIT;
