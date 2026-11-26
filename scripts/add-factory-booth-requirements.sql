-- Idempotent DDL: per-booth special requirements for factory kiosks.
-- FactoryPlanningBooth keeps the felt colour, option codes and leftover note that
-- Factory reads from each batch's Опаковане tab; FactoryBoothOption gains the note
-- keywords and the panels whose stations must see the option.
-- Apply with: scripts/apply-sql.sh <staging|production> scripts/add-factory-booth-requirements.sql
-- Safe to run twice. Additive only; older consumers ignore the new columns.

BEGIN;

ALTER TABLE "FactoryPlanningBooth"
  ADD COLUMN IF NOT EXISTS "feltColour" TEXT,
  ADD COLUMN IF NOT EXISTS "optionCodes" TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
  ADD COLUMN IF NOT EXISTS "workshopNote" TEXT,
  ADD COLUMN IF NOT EXISTS "specSyncedAt" TIMESTAMP(3);

ALTER TABLE "FactoryBoothOption"
  ADD COLUMN IF NOT EXISTS "keywords" TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
  ADD COLUMN IF NOT EXISTS "elementCodes" TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
  ADD COLUMN IF NOT EXISTS "isActive" BOOLEAN NOT NULL DEFAULT true;

COMMIT;
