-- Idempotent DDL: unknown planning colours become provisional factory colours, and MRP
-- holds an element's colour-specific deduction until that colour has BOM lines.
-- Apply with: scripts/apply-sql.sh <staging|production> scripts/add-provisional-colours.sql
-- Safe to run twice. Additive only; older consumers ignore the new columns.

BEGIN;

ALTER TABLE "FactoryColor"
  ADD COLUMN IF NOT EXISTS "provisional" BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS "provisionalSince" TIMESTAMP(3);

ALTER TABLE "MrpBatchUnitElement"
  ADD COLUMN IF NOT EXISTS "colourDeductionPending" BOOLEAN NOT NULL DEFAULT false;

COMMIT;
