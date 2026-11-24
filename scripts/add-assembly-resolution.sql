-- Assembly: AssemblyResolution records each time staff resolve a job's issue, close the job
-- by hand, or reopen it: who, when, the reason and note, and what Issue and Closure were
-- before (so Reopen can put them back). New enum and new table only. Additive,
-- transactional and idempotent; touches no existing data.
-- Apply: scripts/apply-sql.sh staging scripts/add-assembly-resolution.sql --env-file <staging env>
-- Production: from the approved release tag through scripts/apply-sql.sh production.

BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';

DO $$ BEGIN
  CREATE TYPE "AssemblyResolutionKind" AS ENUM ('RESOLVE_ISSUE', 'CLOSE', 'REOPEN');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE TABLE IF NOT EXISTS "AssemblyResolution" (
  "id"              TEXT NOT NULL,
  "assemblyId"      TEXT NOT NULL,
  "kind"            "AssemblyResolutionKind" NOT NULL,
  "reason"          TEXT NOT NULL,
  "note"            TEXT NOT NULL DEFAULT '',
  "previousIssue"   "AssemblyIssue" NOT NULL,
  "previousClosure" BOOLEAN NOT NULL,
  "userId"          TEXT,
  "userName"        TEXT NOT NULL DEFAULT '',
  "linkedJobId"     TEXT,
  "linkedRpNum"     TEXT,
  "createdAt"       TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "AssemblyResolution_pkey" PRIMARY KEY ("id")
);

CREATE INDEX IF NOT EXISTS "AssemblyResolution_assemblyId_createdAt_idx"
  ON "AssemblyResolution"("assemblyId", "createdAt");

DO $$ BEGIN
  ALTER TABLE "AssemblyResolution"
    ADD CONSTRAINT "AssemblyResolution_assemblyId_fkey"
    FOREIGN KEY ("assemblyId") REFERENCES "Assembly"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

COMMIT;
