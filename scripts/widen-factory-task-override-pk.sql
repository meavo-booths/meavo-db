-- Factory schedule task override key (follow-up to cross-app data review 2026-11, release 1):
-- transactional, idempotent; widens one primary key, removes no rows or columns.
-- Apply ONLY after reviewing the target/schema and following RELEASE_POLICY.md.
-- Apply: scripts/apply-sql.sh <staging|production> scripts/widen-factory-task-override-pk.sql --env-file <file> [--tag vX.Y.Z]
--    or: npx prisma db execute --file scripts/widen-factory-task-override-pk.sql --schema prisma/schema.prisma
-- Required existing objects: FactoryScheduleTaskOverride.
--
-- The primary key of FactoryScheduleTaskOverride becomes
-- (batchId, elementId, processStep, assignedStationId), so one panel job can sit on
-- several ASM stations at once, each with its own sortOrder. The Factory app widened
-- the key on production with its own SQL (now
-- apps/web/prisma/patches/meavo-db-factory-shared-task-overrides.md in Meavo-Factory).
-- Production had the four-column key on 6 November 2026 (pg_constraint read through
-- _shared/tools/prod-read.mjs; 63 rows over 54 jobs), so there this script changes
-- nothing. Staging and databases built from the schema before this change have the
-- three-column key; it is swapped in one ALTER TABLE. Rows unique on three columns
-- stay unique on four and assignedStationId is already NOT NULL, so the swap cannot
-- fail on existing data. Nothing happens when assignedStationId is already part of
-- the primary key, whatever the key is called.
-- Run twice against an isolated, disposable PostgreSQL DB before environment release.
-- No production application is authorized by this file.
BEGIN;

DO $$ BEGIN
  IF EXISTS (
    SELECT 1
    FROM pg_constraint c
    JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = ANY (c.conkey)
    WHERE c.conrelid = '"FactoryScheduleTaskOverride"'::regclass
      AND c.contype = 'p'
      AND a.attname = 'assignedStationId'
  ) THEN
    RETURN;
  END IF;

  ALTER TABLE "FactoryScheduleTaskOverride"
    DROP CONSTRAINT IF EXISTS "FactoryScheduleTaskOverride_pkey",
    ADD CONSTRAINT "FactoryScheduleTaskOverride_pkey"
      PRIMARY KEY ("batchId", "elementId", "processStep", "assignedStationId");
END $$;

COMMIT;
