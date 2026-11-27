-- Factory floor & planning (owner: factory): drop the booth and batch option pieces that were
-- never used. Booth special requirements live on FactoryPlanningBooth (feltColour,
-- optionCodes, workshopNote) with the catalogue in FactoryBoothOption, which stays.
--   - FactoryProductionBoothUnitOption: options per production slot. Slots are colour-line
--     slots, not real booths, and are deleted when quantities shrink; never written.
--   - FactoryProductionBoothUnit."notes": never written or read.
--   - FactoryBoothProductionOption and FactoryBatchProductionOption, with the columns that
--     point at them: FactoryPlanningBooth."boothProductionOptionId" and
--     FactoryPlanningBatch."batchProductionOptionId".
-- All were empty in the November audit (docs/database-audit-2026-11.md §2.3) and on staging
-- on 27 November 2026. The guard below aborts, changing nothing, if any of them holds data.
-- Apps on a meavo-db version older than this one select the dropped columns by default:
-- apply only after every app that reads FactoryProductionBoothUnit, FactoryPlanningBooth or
-- FactoryPlanningBatch runs on this version (Factory and Inventory).
-- Idempotent: the foreign-key columns go before the tables they point at, all IF EXISTS.
-- Apply: scripts/apply-sql.sh staging scripts/drop-unused-factory-option-tables.sql --env-file <staging env>

BEGIN;

DO $$
DECLARE
  n bigint;
BEGIN
  IF to_regclass('"FactoryProductionBoothUnitOption"') IS NOT NULL THEN
    EXECUTE 'SELECT count(*) FROM "FactoryProductionBoothUnitOption"' INTO n;
    IF n > 0 THEN RAISE EXCEPTION 'FactoryProductionBoothUnitOption has % rows', n; END IF;
  END IF;
  IF to_regclass('"FactoryBoothProductionOption"') IS NOT NULL THEN
    EXECUTE 'SELECT count(*) FROM "FactoryBoothProductionOption"' INTO n;
    IF n > 0 THEN RAISE EXCEPTION 'FactoryBoothProductionOption has % rows', n; END IF;
  END IF;
  IF to_regclass('"FactoryBatchProductionOption"') IS NOT NULL THEN
    EXECUTE 'SELECT count(*) FROM "FactoryBatchProductionOption"' INTO n;
    IF n > 0 THEN RAISE EXCEPTION 'FactoryBatchProductionOption has % rows', n; END IF;
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = current_schema()
             AND table_name = 'FactoryProductionBoothUnit' AND column_name = 'notes') THEN
    EXECUTE 'SELECT count(*) FROM "FactoryProductionBoothUnit" WHERE "notes" IS NOT NULL' INTO n;
    IF n > 0 THEN RAISE EXCEPTION 'FactoryProductionBoothUnit.notes is set on % rows', n; END IF;
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = current_schema()
             AND table_name = 'FactoryPlanningBooth' AND column_name = 'boothProductionOptionId') THEN
    EXECUTE 'SELECT count(*) FROM "FactoryPlanningBooth" WHERE "boothProductionOptionId" IS NOT NULL' INTO n;
    IF n > 0 THEN RAISE EXCEPTION 'FactoryPlanningBooth.boothProductionOptionId is set on % rows', n; END IF;
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = current_schema()
             AND table_name = 'FactoryPlanningBatch' AND column_name = 'batchProductionOptionId') THEN
    EXECUTE 'SELECT count(*) FROM "FactoryPlanningBatch" WHERE "batchProductionOptionId" IS NOT NULL' INTO n;
    IF n > 0 THEN RAISE EXCEPTION 'FactoryPlanningBatch.batchProductionOptionId is set on % rows', n; END IF;
  END IF;
END $$;

-- Dropping a column also drops its foreign key.
ALTER TABLE "FactoryPlanningBooth" DROP COLUMN IF EXISTS "boothProductionOptionId";
ALTER TABLE "FactoryPlanningBatch" DROP COLUMN IF EXISTS "batchProductionOptionId";
ALTER TABLE "FactoryProductionBoothUnit" DROP COLUMN IF EXISTS "notes";

DROP TABLE IF EXISTS "FactoryProductionBoothUnitOption";
DROP TABLE IF EXISTS "FactoryBoothProductionOption";
DROP TABLE IF EXISTS "FactoryBatchProductionOption";

COMMIT;
