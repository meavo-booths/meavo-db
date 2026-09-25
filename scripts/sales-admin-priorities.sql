-- Tool-scoped Sales Admin role and durable generated recommendation history.
-- Apply: npx prisma db execute --file scripts/sales-admin-priorities.sql --schema prisma/schema.prisma
-- Prerequisite: scripts/sales-daily-priorities.sql has been applied.
-- Transactional and idempotent. Existing access becomes MEMBER; nobody is promoted.
-- Verify the actual isolated non-production target before testing. Production
-- application requires exact SQL/revision approval under RELEASE_POLICY.md.
-- Roll back application code only; retain role fields and historical records.

BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';

DO $$ BEGIN
  CREATE TYPE "ToolAccessRole" AS ENUM ('MEMBER', 'ADMIN');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

ALTER TABLE "ToolCardAccess"
  ADD COLUMN IF NOT EXISTS "role" "ToolAccessRole" NOT NULL DEFAULT 'MEMBER';

ALTER TABLE "SalesPriorityRecommendation"
  ADD COLUMN IF NOT EXISTS "userName" TEXT;
ALTER TABLE "SalesPriorityFeedback"
  ADD COLUMN IF NOT EXISTS "userName" TEXT;

-- Preserve recipient/actor IDs even when Gateway deletes the corresponding User.
-- These are the two historical links only: identity mappings and tool membership
-- retain their existing cascading User foreign keys.
ALTER TABLE "SalesPriorityRecommendation"
  DROP CONSTRAINT IF EXISTS "SalesPriorityRecommendation_userId_fkey";
ALTER TABLE "SalesPriorityFeedback"
  DROP CONSTRAINT IF EXISTS "SalesPriorityFeedback_userId_fkey";

-- Old versions stored a recipient ID but no display name on the REP work item.
-- Prefer the live account label while available, then the saved deal input.
-- Only fill absent names; reruns must never replace a frozen historical label.
WITH labels AS (
  SELECT w."id", COALESCE(
    (SELECT COALESCE(NULLIF(btrim(u."name"), ''), NULLIF(btrim(u."email"), ''))
      FROM "User" u WHERE u."id" = w."userId"),
    (SELECT NULLIF(btrim(s."data"->>'salesRep'), '')
      FROM "SalesOpportunitySnapshot" s
      WHERE s."runId" = w."runId" AND s."userId" = w."userId"
        AND NULLIF(btrim(s."data"->>'salesRep'), '') IS NOT NULL
      ORDER BY s."capturedAt", s."id" LIMIT 1),
    (SELECT NULLIF(btrim(d."input"->>'salesRep'), '')
      FROM "SalesPriorityWorkItem" d
      WHERE d."runId" = w."runId" AND d."userId" = w."userId" AND d."kind" = 'DEAL'
        AND NULLIF(btrim(d."input"->>'salesRep'), '') IS NOT NULL
      ORDER BY d."createdAt", d."id" LIMIT 1)
  ) AS name
  FROM "SalesPriorityWorkItem" w
  WHERE w."kind" = 'REP' AND NULLIF(btrim(w."input"->>'userName'), '') IS NULL
)
UPDATE "SalesPriorityWorkItem" w
SET "input" = jsonb_set(w."input", '{userName}', to_jsonb(labels.name), true)
FROM labels WHERE w."id" = labels."id" AND labels.name IS NOT NULL;

WITH labels AS (
  SELECT r."id", COALESCE(
    (SELECT COALESCE(NULLIF(btrim(u."name"), ''), NULLIF(btrim(u."email"), ''))
      FROM "User" u WHERE u."id" = r."userId"),
    (SELECT NULLIF(btrim(s."data"->>'salesRep'), '')
      FROM "SalesOpportunitySnapshot" s
      WHERE s."runId" = r."runId" AND s."familyId" = r."familyId" AND s."userId" = r."userId"
      LIMIT 1),
    (SELECT NULLIF(btrim(d."input"->>'salesRep'), '')
      FROM "SalesPriorityWorkItem" d
      WHERE d."runId" = r."runId" AND d."familyId" = r."familyId"
        AND d."userId" = r."userId" AND d."kind" = 'DEAL'
        AND NULLIF(btrim(d."input"->>'salesRep'), '') IS NOT NULL
      ORDER BY d."createdAt", d."id" LIMIT 1),
    (SELECT NULLIF(btrim(w."input"->>'userName'), '')
      FROM "SalesPriorityWorkItem" w
      WHERE w."runId" = r."runId" AND w."userId" = r."userId" AND w."kind" = 'REP'
        AND NULLIF(btrim(w."input"->>'userName'), '') IS NOT NULL
      ORDER BY w."createdAt", w."id" LIMIT 1)
  ) AS name
  FROM "SalesPriorityRecommendation" r WHERE NULLIF(btrim(r."userName"), '') IS NULL
)
UPDATE "SalesPriorityRecommendation" r SET "userName" = labels.name
FROM labels WHERE r."id" = labels."id" AND labels.name IS NOT NULL;

WITH labels AS (
  SELECT f."id", COALESCE(
    (SELECT COALESCE(NULLIF(btrim(u."name"), ''), NULLIF(btrim(u."email"), ''))
      FROM "User" u WHERE u."id" = f."userId"),
    (SELECT NULLIF(btrim(r."userName"), '') FROM "SalesPriorityRecommendation" r
      WHERE r."id" = f."recommendationId" AND r."userId" = f."userId")
  ) AS name
  FROM "SalesPriorityFeedback" f WHERE NULLIF(btrim(f."userName"), '') IS NULL
)
UPDATE "SalesPriorityFeedback" f SET "userName" = labels.name
FROM labels WHERE f."id" = labels."id" AND labels.name IS NOT NULL;

COMMIT;
