-- Idempotent DDL for Factory credit quota columns.
-- Apply with: prisma db execute --file scripts/add-factory-credits.sql

ALTER TABLE "FactoryBoothModel"
  ADD COLUMN IF NOT EXISTS "credits" DECIMAL(6, 2);

ALTER TABLE "FactoryPlanningMonth"
  ADD COLUMN IF NOT EXISTS "creditTarget" DECIMAL(10, 2);

ALTER TABLE "FactoryPlanningMonth"
  ADD COLUMN IF NOT EXISTS "creditCapacity" DECIMAL(10, 2);

-- Canonical booth-model credits (HF uses 1.5; sheet J may override at import).
UPDATE "FactoryBoothModel" SET "credits" = 1.00 WHERE "code" = 'SO' AND "credits" IS NULL;
UPDATE "FactoryBoothModel" SET "credits" = 1.00 WHERE "code" = 'SW' AND "credits" IS NULL;
UPDATE "FactoryBoothModel" SET "credits" = 2.00 WHERE "code" = 'C2' AND "credits" IS NULL;
UPDATE "FactoryBoothModel" SET "credits" = 2.00 WHERE "code" = 'C4' AND "credits" IS NULL;
UPDATE "FactoryBoothModel" SET "credits" = 1.20 WHERE "code" = 'H1' AND "credits" IS NULL;
UPDATE "FactoryBoothModel" SET "credits" = 1.50 WHERE "code" = 'HF' AND "credits" IS NULL;
UPDATE "FactoryBoothModel" SET "credits" = 2.30 WHERE "code" = 'H2' AND "credits" IS NULL;
UPDATE "FactoryBoothModel" SET "credits" = 2.30 WHERE "code" = 'H4' AND "credits" IS NULL;
