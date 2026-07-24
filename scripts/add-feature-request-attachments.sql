-- Multi-file attachments for FeatureRequest.
-- Apply: npx prisma db execute --file scripts/add-feature-request-attachments.sql --schema prisma/schema.prisma

CREATE TABLE IF NOT EXISTS "FeatureRequestAttachment" (
  "id" TEXT NOT NULL,
  "requestId" TEXT NOT NULL,
  "storageKey" TEXT NOT NULL,
  "fileName" TEXT NOT NULL,
  "mimeType" TEXT NOT NULL,
  "sortOrder" INTEGER NOT NULL DEFAULT 0,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

  CONSTRAINT "FeatureRequestAttachment_pkey" PRIMARY KEY ("id")
);

CREATE INDEX IF NOT EXISTS "FeatureRequestAttachment_requestId_idx"
  ON "FeatureRequestAttachment"("requestId");

DO $$ BEGIN
  ALTER TABLE "FeatureRequestAttachment" ADD CONSTRAINT "FeatureRequestAttachment_requestId_fkey"
    FOREIGN KEY ("requestId") REFERENCES "FeatureRequest"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

-- Migrate legacy single-attachment columns into rows (skip if already migrated / columns gone)
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'FeatureRequest' AND column_name = 'attachmentKey'
  ) THEN
    INSERT INTO "FeatureRequestAttachment" ("id", "requestId", "storageKey", "fileName", "mimeType", "sortOrder", "createdAt")
    SELECT
      md5(random()::text || clock_timestamp()::text || fr."id")::text,
      fr."id",
      fr."attachmentKey",
      COALESCE(NULLIF(fr."attachmentName", ''), 'attachment'),
      COALESCE(NULLIF(fr."attachmentMime", ''), 'application/octet-stream'),
      0,
      CURRENT_TIMESTAMP
    FROM "FeatureRequest" fr
    WHERE fr."attachmentKey" IS NOT NULL
      AND NOT EXISTS (
        SELECT 1 FROM "FeatureRequestAttachment" a
        WHERE a."requestId" = fr."id" AND a."storageKey" = fr."attachmentKey"
      );

    ALTER TABLE "FeatureRequest" DROP COLUMN IF EXISTS "attachmentKey";
    ALTER TABLE "FeatureRequest" DROP COLUMN IF EXISTS "attachmentName";
    ALTER TABLE "FeatureRequest" DROP COLUMN IF EXISTS "attachmentMime";
  END IF;
END $$;
