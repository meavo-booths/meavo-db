-- Apply only after confirming the target and reviewing RELEASE_POLICY.md:
--   npx prisma db execute --file scripts/add-team-subgroups.sql --schema prisma/schema.prisma
-- Additive, transactional and idempotent. Existing memberships retain a NULL subgroup.
-- Import receipts contain a request hash and safe row statuses, never CSV/payroll/passwords.

BEGIN;

CREATE TABLE IF NOT EXISTS "TeamSubgroup" (
  "id" TEXT NOT NULL,
  "teamId" TEXT NOT NULL,
  "name" TEXT NOT NULL,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "TeamSubgroup_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX IF NOT EXISTS "TeamSubgroup_teamId_name_key"
  ON "TeamSubgroup"("teamId", "name");
CREATE UNIQUE INDEX IF NOT EXISTS "TeamSubgroup_id_teamId_key"
  ON "TeamSubgroup"("id", "teamId");

ALTER TABLE "TeamMember" ADD COLUMN IF NOT EXISTS "subgroupId" TEXT;
CREATE INDEX IF NOT EXISTS "TeamMember_teamId_subgroupId_idx"
  ON "TeamMember"("teamId", "subgroupId");

DO $$ BEGIN
  ALTER TABLE "TeamSubgroup" ADD CONSTRAINT "TeamSubgroup_teamId_fkey"
    FOREIGN KEY ("teamId") REFERENCES "Team"("id")
    ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE "TeamMember" ADD CONSTRAINT "TeamMember_subgroupId_teamId_fkey"
    FOREIGN KEY ("subgroupId", "teamId") REFERENCES "TeamSubgroup"("id", "teamId")
    ON DELETE RESTRICT ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE TABLE IF NOT EXISTS "GatewayUserImportReceipt" (
  "id" TEXT NOT NULL,
  "actorId" TEXT NOT NULL,
  "requestHash" TEXT NOT NULL,
  "result" JSONB NOT NULL,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "GatewayUserImportReceipt_pkey" PRIMARY KEY ("id")
);

CREATE INDEX IF NOT EXISTS "GatewayUserImportReceipt_actorId_createdAt_idx"
  ON "GatewayUserImportReceipt"("actorId", "createdAt");

DO $$ BEGIN
  ALTER TABLE "GatewayUserImportReceipt" ADD CONSTRAINT "GatewayUserImportReceipt_actorId_fkey"
    FOREIGN KEY ("actorId") REFERENCES "User"("id")
    ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

COMMIT;
