-- Booth model catalogue (cross-app data review 2026-11, release 1, script 1 of 4):
-- additive, transactional, idempotent.
-- Apply ONLY after reviewing the target/schema and following RELEASE_POLICY.md.
-- Apply: scripts/apply-sql.sh <staging|production> scripts/add-booth-family-catalog.sql --env-file <file> [--tag vX.Y.Z]
--    or: npx prisma db execute --file scripts/add-booth-family-catalog.sql --schema prisma/schema.prisma
-- Required existing objects: BoothProductFamily, FactoryBoothModel, MrpBoothModel, ResourceBoothModel.
-- Order: this script, then add-production-batch-master.sql, add-booth-identity-links.sql,
-- add-factory-floor-tables.sql.
--
-- Creates BoothFamily with the eight families. Seed rows are insert-only
-- (ON CONFLICT DO NOTHING), so names edited later are never overwritten.
-- Links FactoryBoothModel by factoryCode (SW -> WS) and MrpBoothModel by
-- lower(name) = lower(mrpName or name) or an alias; "Custom Batch" stays null.
-- Copies ResourceBoothModel.boothModel into the shared enum column family.
-- Every backfill fills NULLs only, so a rerun never changes a link set by hand.
-- ProductFamilyInfo.displayName is not touched: production already holds the
-- canonical names, and Sales reads BoothFamily in its own release.
-- Run twice against an isolated, disposable PostgreSQL DB before environment release.
-- No production application is authorized by this file.
BEGIN;

-- CreateTable
CREATE TABLE IF NOT EXISTS "BoothFamily" (
    "code" TEXT NOT NULL,
    "family" "BoothProductFamily" NOT NULL,
    "name" TEXT NOT NULL,
    "nameBg" TEXT NOT NULL,
    "line" TEXT NOT NULL,
    "factoryCode" TEXT NOT NULL,
    "mrpName" TEXT NOT NULL,
    "aliases" TEXT[] DEFAULT ARRAY[]::TEXT[],
    "sortOrder" INTEGER NOT NULL DEFAULT 0,
    "isActive" BOOLEAN NOT NULL DEFAULT true,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "BoothFamily_pkey" PRIMARY KEY ("code")
);

CREATE UNIQUE INDEX IF NOT EXISTS "BoothFamily_family_key" ON "BoothFamily"("family");
CREATE UNIQUE INDEX IF NOT EXISTS "BoothFamily_factoryCode_key" ON "BoothFamily"("factoryCode");
CREATE UNIQUE INDEX IF NOT EXISTS "BoothFamily_mrpName_key" ON "BoothFamily"("mrpName");

-- Seed: code = serial prefix; nameBg = today's Factory label (FactoryBoothModel.nameBg);
-- aliases = lower-case spellings used by Factory (model-map.ts), MRP/RP
-- (rp-deductions.ts), Inventory (factory.ts, format.ts) and the sheets.
INSERT INTO "BoothFamily"
  ("code", "family", "name", "nameBg", "line", "factoryCode", "mrpName", "aliases", "sortOrder", "updatedAt")
VALUES
  ('SO', 'SOHO',        'Soho',        'Soho',        'Classic', 'SO', 'Soho',        ARRAY['so'],                                         10, CURRENT_TIMESTAMP),
  ('WS', 'WORKSTATION', 'Workstation', 'Workstation', 'Classic', 'SW', 'Workstation', ARRAY['ws', 'sw'],                                   20, CURRENT_TIMESTAMP),
  ('C2', 'CAMDEN_2',    'Camden 2',    'Camden 2',    'Classic', 'C2', 'Camden 2',    ARRAY['c2'],                                         30, CURRENT_TIMESTAMP),
  ('C4', 'CAMDEN_4',    'Camden 4',    'Camden 4',    'Classic', 'C4', 'Camden 4',    ARRAY['c4', 'camden 7'],                             40, CURRENT_TIMESTAMP),
  ('H1', 'HAVEN_ONE',   'Haven One',   'Haven One',   'Haven',   'H1', 'Haven One',   ARRAY['h1', 'h.o', 'haven 1', 'meavo one'],          50, CURRENT_TIMESTAMP),
  ('HF', 'HAVEN_FOCUS', 'Haven Focus', 'Haven Focus', 'Haven',   'HF', 'Haven Focus', ARRAY['hf', 'h.f', 'meavo focus'],                   60, CURRENT_TIMESTAMP),
  ('H2', 'HAVEN_2',     'Haven Two',   'Haven Two',   'Haven',   'H2', 'Haven Two',   ARRAY['h2', 'h.2', 'haven 2', 'meavo two'],          70, CURRENT_TIMESTAMP),
  ('H4', 'HAVEN_4',     'Haven Four',  'Haven Four',  'Haven',   'H4', 'Haven Four',  ARRAY['h4', 'h.4', 'haven 4', 'meavo four', 'have four'], 80, CURRENT_TIMESTAMP)
ON CONFLICT DO NOTHING;

-- AlterTable: link columns.
ALTER TABLE "FactoryBoothModel" ADD COLUMN IF NOT EXISTS "familyCode" TEXT;
ALTER TABLE "MrpBoothModel" ADD COLUMN IF NOT EXISTS "familyCode" TEXT;
ALTER TABLE "ResourceBoothModel" ADD COLUMN IF NOT EXISTS "family" "BoothProductFamily";

CREATE UNIQUE INDEX IF NOT EXISTS "FactoryBoothModel_familyCode_key" ON "FactoryBoothModel"("familyCode");
CREATE UNIQUE INDEX IF NOT EXISTS "MrpBoothModel_familyCode_key" ON "MrpBoothModel"("familyCode");

-- Backfill FactoryBoothModel by code; a family already linked elsewhere is skipped.
UPDATE "FactoryBoothModel" m
SET "familyCode" = bf."code"
FROM "BoothFamily" bf
WHERE m."familyCode" IS NULL
  AND upper(btrim(m."code")) = bf."factoryCode"
  AND NOT EXISTS (SELECT 1 FROM "FactoryBoothModel" x WHERE x."familyCode" = bf."code");

-- Backfill MrpBoothModel by name or alias. One MRP row per family: an exact
-- mrpName match wins over an alias, then the oldest row.
UPDATE "MrpBoothModel" m
SET "familyCode" = pick."familyCode"
FROM (
  SELECT DISTINCT ON (bf."code") mm."id", bf."code" AS "familyCode"
  FROM "MrpBoothModel" mm
  JOIN "BoothFamily" bf
    ON lower(btrim(mm."name")) = lower(bf."mrpName")
    OR lower(btrim(mm."name")) = lower(bf."name")
    OR lower(btrim(mm."name")) = ANY (bf."aliases")
  WHERE mm."familyCode" IS NULL
  ORDER BY bf."code", (lower(btrim(mm."name")) = lower(bf."mrpName")) DESC, mm."createdAt", mm."id"
) pick
WHERE m."id" = pick."id"
  AND NOT EXISTS (SELECT 1 FROM "MrpBoothModel" x WHERE x."familyCode" = pick."familyCode");

-- Backfill ResourceBoothModel: BoothModel and BoothProductFamily share their eight values.
UPDATE "ResourceBoothModel"
SET "family" = "boothModel"::text::"BoothProductFamily"
WHERE "family" IS NULL;

-- AddForeignKey (guarded).
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'FactoryBoothModel_familyCode_fkey' AND conrelid = '"FactoryBoothModel"'::regclass
  ) THEN
    ALTER TABLE "FactoryBoothModel" ADD CONSTRAINT "FactoryBoothModel_familyCode_fkey"
      FOREIGN KEY ("familyCode") REFERENCES "BoothFamily"("code") ON DELETE SET NULL ON UPDATE CASCADE;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'MrpBoothModel_familyCode_fkey' AND conrelid = '"MrpBoothModel"'::regclass
  ) THEN
    ALTER TABLE "MrpBoothModel" ADD CONSTRAINT "MrpBoothModel_familyCode_fkey"
      FOREIGN KEY ("familyCode") REFERENCES "BoothFamily"("code") ON DELETE SET NULL ON UPDATE CASCADE;
  END IF;
END $$;

COMMIT;
