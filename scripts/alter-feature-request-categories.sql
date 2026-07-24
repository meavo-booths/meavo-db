-- Alter FeatureRequest categories + add Importance.
-- Apply: npx prisma db execute --file scripts/alter-feature-request-categories.sql --schema prisma/schema.prisma

-- Rename old type enum values (Postgres 10+)
DO $$ BEGIN
  ALTER TYPE "FeatureRequestType" RENAME VALUE 'SMALL_FEATURE' TO 'SMALL_NEW_FEATURE';
EXCEPTION
  WHEN undefined_object THEN NULL;
  WHEN invalid_parameter_value THEN NULL; -- already renamed
END $$;

DO $$ BEGIN
  ALTER TYPE "FeatureRequestType" RENAME VALUE 'BIG_FEATURE' TO 'BIG_NEW_FEATURE';
EXCEPTION
  WHEN undefined_object THEN NULL;
  WHEN invalid_parameter_value THEN NULL;
END $$;

-- Add CHANGE if missing
DO $$ BEGIN
  ALTER TYPE "FeatureRequestType" ADD VALUE IF NOT EXISTS 'CHANGE';
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

-- Importance enum
DO $$ BEGIN
  CREATE TYPE "FeatureRequestImportance" AS ENUM ('CRITICAL', 'IMPORTANT', 'NICE_TO_HAVE');
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

-- Importance column
DO $$ BEGIN
  ALTER TABLE "FeatureRequest"
    ADD COLUMN "importance" "FeatureRequestImportance" NOT NULL DEFAULT 'IMPORTANT';
EXCEPTION
  WHEN duplicate_column THEN NULL;
END $$;

CREATE INDEX IF NOT EXISTS "FeatureRequest_importance_idx" ON "FeatureRequest"("importance");

-- Optional description default
ALTER TABLE "FeatureRequest" ALTER COLUMN "description" SET DEFAULT '';
