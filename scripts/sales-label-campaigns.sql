-- Sales: separate ordinary deal labels from marketing campaigns.
-- Apply: npx prisma db execute --file scripts/sales-label-campaigns.sql --schema prisma/schema.prisma
-- Apply before the updated Sales consumer. Older writers default to STANDARD.
-- Retains all label IDs, assignments, and global case-insensitive uniqueness.
-- The OA Invoice CHECK is intentional and is not represented in Prisma.

BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';

DO $$ BEGIN
  CREATE TYPE "DealLabelKind" AS ENUM ('STANDARD', 'CAMPAIGN');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

ALTER TABLE "DealLabel"
  ADD COLUMN IF NOT EXISTS "kind" "DealLabelKind" NOT NULL DEFAULT 'STANDARD';

CREATE INDEX IF NOT EXISTS "DealLabel_kind_name_idx"
  ON "DealLabel"("kind", "name");

DO $$ BEGIN
  ALTER TABLE "DealLabel" ADD CONSTRAINT "DealLabel_oaInvoice_kind_check"
    CHECK ("normalizedName" <> 'oa invoice' OR "kind" = 'STANDARD');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

COMMIT;
