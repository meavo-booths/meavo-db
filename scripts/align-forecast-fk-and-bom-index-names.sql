-- Forecast item foreign key and BOM line index name (follow-up to the 2026-11 database audit):
-- transactional, idempotent; changes one foreign-key update rule and one index name,
-- removes no rows, columns or constraints.
-- Apply ONLY after reviewing the target/schema and following RELEASE_POLICY.md.
-- Apply: scripts/apply-sql.sh <staging|production> scripts/align-forecast-fk-and-bom-index-names.sql --env-file <file> [--tag vX.Y.Z]
--    or: npx prisma db execute --file scripts/align-forecast-fk-and-bom-index-names.sql --schema prisma/schema.prisma
-- Required existing objects: SalesOpportunityForecastItem, SalesOpportunityForecastRun,
-- MrpElementBomLine.
--
-- The schema now declares both objects the way production and the Neon staging branch
-- already have them (read on 6 November 2026), so on those databases this script
-- changes nothing:
-- 1. SalesOpportunityForecastItem_runId_fkey: ON DELETE RESTRICT, ON UPDATE NO ACTION.
--    Databases built from the schema before 0.102.1 have ON UPDATE CASCADE. Run ids are
--    never updated, so the rule has no effect on data; the constraint is swapped in one
--    ALTER TABLE only when its update rule is not NO ACTION.
-- 2. The unique index on MrpElementBomLine (recipeVersionId, boothElementId, colour,
--    market, materialId) is named MrpElementBomLine_recipeVersionId_boothElementId_colour_market_
--    (PostgreSQL's 63-character truncation of the original name). Databases built from the
--    schema before 0.102.1 call it ..._colour_mar_key (Prisma's truncation). The index is
--    renamed only when the old name exists and the new one does not; columns and
--    uniqueness do not change.
-- Run twice against an isolated, disposable PostgreSQL DB before environment release.
-- No production application is authorized by this file.
BEGIN;

DO $$ BEGIN
  IF EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conrelid = '"SalesOpportunityForecastItem"'::regclass
      AND conname = 'SalesOpportunityForecastItem_runId_fkey'
      AND confupdtype <> 'a'
  ) THEN
    ALTER TABLE "SalesOpportunityForecastItem"
      DROP CONSTRAINT "SalesOpportunityForecastItem_runId_fkey",
      ADD CONSTRAINT "SalesOpportunityForecastItem_runId_fkey"
        FOREIGN KEY ("runId") REFERENCES "SalesOpportunityForecastRun"("id")
        ON DELETE RESTRICT ON UPDATE NO ACTION;
  END IF;
END $$;

DO $$ BEGIN
  IF to_regclass('public."MrpElementBomLine_recipeVersionId_boothElementId_colour_mar_key"') IS NOT NULL
     AND to_regclass('public."MrpElementBomLine_recipeVersionId_boothElementId_colour_market_"') IS NULL THEN
    ALTER INDEX "MrpElementBomLine_recipeVersionId_boothElementId_colour_mar_key"
      RENAME TO "MrpElementBomLine_recipeVersionId_boothElementId_colour_market_";
  END IF;
END $$;

COMMIT;
