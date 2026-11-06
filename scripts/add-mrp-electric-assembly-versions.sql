-- MRP electric assembly versions: additive, transactional, idempotent DDL only.
-- Apply ONLY after reviewing the target/schema and following RELEASE_POLICY.md.
-- Apply: scripts/apply-sql.sh <staging|production> scripts/add-mrp-electric-assembly-versions.sql --env-file <file> [--tag vX.Y.Z]
--    or: npx prisma db execute --file scripts/add-mrp-electric-assembly-versions.sql --schema prisma/schema.prisma
-- Required existing objects: MrpElectricAssembly, MrpRecipeVersionElectric, User,
-- enum MrpRecipeVersionStatus.
--
-- MrpElectricAssemblyVersion and MrpRecipeVersionElectric."assemblyVersionId" are
-- declared in the schema since v0.78.0 (commit 76b8537, 18 September 2026) and exist on
-- the staging branch (created there by an MRP preview build, 0 rows), but production
-- never received them (6 November 2026 audit). This script creates them exactly as
-- staging has them (information_schema, pg_constraint and pg_indexes), including
-- DEFAULT CURRENT_TIMESTAMP on "updatedAt". On staging every statement is a no-op;
-- on production it creates an empty table and a nullable column.
-- Run twice against an isolated, disposable PostgreSQL DB before environment release.
-- No production application is authorized by this file.
BEGIN;

-- CreateTable
CREATE TABLE IF NOT EXISTS "MrpElectricAssemblyVersion" (
    "id" TEXT NOT NULL,
    "assemblyId" TEXT NOT NULL,
    "label" TEXT NOT NULL,
    "status" "MrpRecipeVersionStatus" NOT NULL DEFAULT 'ready',
    "moduleSnapshot" JSONB,
    "snapshotVersion" INTEGER NOT NULL DEFAULT 2,
    "reason" TEXT,
    "introducedOn" TIMESTAMP(3),
    "lockedAt" TIMESTAMP(3),
    "sourceVersionId" TEXT,
    "createdById" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "MrpElectricAssemblyVersion_pkey" PRIMARY KEY ("id")
);

-- Staging has DEFAULT CURRENT_TIMESTAMP on "updatedAt"; set it only where it is missing.
DO $$ BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = current_schema() AND table_name = 'MrpElectricAssemblyVersion'
      AND column_name = 'updatedAt' AND column_default IS NULL
  ) THEN
    ALTER TABLE "MrpElectricAssemblyVersion" ALTER COLUMN "updatedAt" SET DEFAULT CURRENT_TIMESTAMP;
  END IF;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS "MrpElectricAssemblyVersion_assemblyId_label_key"
  ON "MrpElectricAssemblyVersion"("assemblyId", "label");
CREATE INDEX IF NOT EXISTS "MrpElectricAssemblyVersion_assemblyId_status_idx"
  ON "MrpElectricAssemblyVersion"("assemblyId", "status");
CREATE INDEX IF NOT EXISTS "MrpElectricAssemblyVersion_introducedOn_idx"
  ON "MrpElectricAssemblyVersion"("introducedOn");

DO $$ BEGIN
  ALTER TABLE "MrpElectricAssemblyVersion" ADD CONSTRAINT "MrpElectricAssemblyVersion_assemblyId_fkey"
    FOREIGN KEY ("assemblyId") REFERENCES "MrpElectricAssembly"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE "MrpElectricAssemblyVersion" ADD CONSTRAINT "MrpElectricAssemblyVersion_sourceVersionId_fkey"
    FOREIGN KEY ("sourceVersionId") REFERENCES "MrpElectricAssemblyVersion"("id") ON DELETE SET NULL ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE "MrpElectricAssemblyVersion" ADD CONSTRAINT "MrpElectricAssemblyVersion_createdById_fkey"
    FOREIGN KEY ("createdById") REFERENCES "User"("id") ON DELETE SET NULL ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- AlterTable: link from a product recipe version's electric row
ALTER TABLE "MrpRecipeVersionElectric" ADD COLUMN IF NOT EXISTS "assemblyVersionId" TEXT;

CREATE INDEX IF NOT EXISTS "MrpRecipeVersionElectric_assemblyVersionId_idx"
  ON "MrpRecipeVersionElectric"("assemblyVersionId");

DO $$ BEGIN
  ALTER TABLE "MrpRecipeVersionElectric" ADD CONSTRAINT "MrpRecipeVersionElectric_assemblyVersionId_fkey"
    FOREIGN KEY ("assemblyVersionId") REFERENCES "MrpElectricAssemblyVersion"("id") ON DELETE SET NULL ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

COMMIT;
