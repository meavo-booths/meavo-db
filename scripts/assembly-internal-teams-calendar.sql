-- Assembly internal teams (members ticked on events) and Google Calendar mirror fields.
-- Additive only. Idempotent. Seeds the LAT team.
-- Apply: scripts/apply-sql.sh staging scripts/assembly-internal-teams-calendar.sql --env-file <staging env>
--        scripts/apply-sql.sh production scripts/assembly-internal-teams-calendar.sql --env-file <prod env> --tag vX.Y.Z

CREATE TABLE IF NOT EXISTS "AssemblyTeam" (
  "id" TEXT NOT NULL,
  "name" TEXT NOT NULL,
  "isActive" BOOLEAN NOT NULL DEFAULT true,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

  CONSTRAINT "AssemblyTeam_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX IF NOT EXISTS "AssemblyTeam_name_key" ON "AssemblyTeam"("name");

CREATE TABLE IF NOT EXISTS "AssemblyTeamMember" (
  "id" TEXT NOT NULL,
  "teamId" TEXT NOT NULL,
  "name" TEXT NOT NULL,
  "email" TEXT NOT NULL,
  "phone" TEXT NOT NULL DEFAULT '',
  "isActive" BOOLEAN NOT NULL DEFAULT true,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

  CONSTRAINT "AssemblyTeamMember_pkey" PRIMARY KEY ("id")
);

CREATE INDEX IF NOT EXISTS "AssemblyTeamMember_teamId_idx" ON "AssemblyTeamMember"("teamId");

DO $$ BEGIN
  ALTER TABLE "AssemblyTeamMember"
    ADD CONSTRAINT "AssemblyTeamMember_teamId_fkey"
    FOREIGN KEY ("teamId") REFERENCES "AssemblyTeam"("id")
    ON DELETE RESTRICT ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE TABLE IF NOT EXISTS "AssemblyTeamAssignment" (
  "assemblyId" TEXT NOT NULL,
  "memberId" TEXT NOT NULL,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

  CONSTRAINT "AssemblyTeamAssignment_pkey" PRIMARY KEY ("assemblyId", "memberId")
);

CREATE INDEX IF NOT EXISTS "AssemblyTeamAssignment_memberId_idx" ON "AssemblyTeamAssignment"("memberId");

DO $$ BEGIN
  ALTER TABLE "AssemblyTeamAssignment"
    ADD CONSTRAINT "AssemblyTeamAssignment_assemblyId_fkey"
    FOREIGN KEY ("assemblyId") REFERENCES "Assembly"("id")
    ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE "AssemblyTeamAssignment"
    ADD CONSTRAINT "AssemblyTeamAssignment_memberId_fkey"
    FOREIGN KEY ("memberId") REFERENCES "AssemblyTeamMember"("id")
    ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

ALTER TABLE "Assembly" ADD COLUMN IF NOT EXISTS "googleCalendarEventId" TEXT;
ALTER TABLE "Assembly" ADD COLUMN IF NOT EXISTS "googleCalendarSyncedAt" TIMESTAMP(3);
ALTER TABLE "Assembly" ADD COLUMN IF NOT EXISTS "googleCalendarSyncError" TEXT;

INSERT INTO "AssemblyTeam" ("id", "name", "updatedAt")
VALUES ('seed-assembly-team-lat', 'LAT', CURRENT_TIMESTAMP)
ON CONFLICT ("name") DO NOTHING;
