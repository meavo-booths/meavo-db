-- Sales: permanent client-merge aliases, immutable audit, and preserved Xero routing.
-- Apply: npx prisma db execute --file scripts/client-merge.sql --schema prisma/schema.prisma
-- Apply only against a verified target. Production requires approval of this exact artifact.
-- This additive, transactional script is idempotent. Use it instead of db push:
-- Prisma cannot express the CHECK constraints or attachment/immutability guards.

BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';

DO $$ BEGIN
  CREATE TYPE "DealXeroRoutingMode" AS ENUM ('FOLLOW_CLIENT', 'FIXED', 'UNMATCHED');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

ALTER TABLE "Client"
  ADD COLUMN IF NOT EXISTS "mergedIntoClientId" TEXT,
  ADD COLUMN IF NOT EXISTS "mergedAt" TIMESTAMP(3),
  ADD COLUMN IF NOT EXISTS "mergedByUserId" TEXT;

ALTER TABLE "Deal"
  ADD COLUMN IF NOT EXISTS "xeroRoutingMode" "DealXeroRoutingMode" NOT NULL DEFAULT 'FOLLOW_CLIENT',
  ADD COLUMN IF NOT EXISTS "xeroRoutingContactId" TEXT,
  ADD COLUMN IF NOT EXISTS "xeroRoutingConnectionKey" TEXT;

CREATE TABLE IF NOT EXISTS "ClientMergeAudit" (
  "id" TEXT NOT NULL,
  "sourceClientId" TEXT NOT NULL,
  "retainedClientId" TEXT NOT NULL,
  "actorUserId" TEXT,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "sourceSnapshot" JSONB NOT NULL,
  "retainedSnapshot" JSONB NOT NULL,
  "resolutions" JSONB NOT NULL,
  "transferredRecords" JSONB NOT NULL,
  CONSTRAINT "ClientMergeAudit_pkey" PRIMARY KEY ("id")
);

CREATE INDEX IF NOT EXISTS "Client_mergedIntoClientId_idx" ON "Client"("mergedIntoClientId");
CREATE UNIQUE INDEX IF NOT EXISTS "ClientMergeAudit_sourceClientId_key" ON "ClientMergeAudit"("sourceClientId");
CREATE INDEX IF NOT EXISTS "ClientMergeAudit_retainedClientId_createdAt_idx" ON "ClientMergeAudit"("retainedClientId", "createdAt");

DO $$ BEGIN
  ALTER TABLE "Client" ADD CONSTRAINT "Client_mergedIntoClientId_fkey"
    FOREIGN KEY ("mergedIntoClientId") REFERENCES "Client"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE "Client" ADD CONSTRAINT "Client_mergedByUserId_fkey"
    FOREIGN KEY ("mergedByUserId") REFERENCES "User"("id") ON DELETE SET NULL ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE "ClientMergeAudit" ADD CONSTRAINT "ClientMergeAudit_sourceClientId_fkey"
    FOREIGN KEY ("sourceClientId") REFERENCES "Client"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE "ClientMergeAudit" ADD CONSTRAINT "ClientMergeAudit_retainedClientId_fkey"
    FOREIGN KEY ("retainedClientId") REFERENCES "Client"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE "ClientMergeAudit" ADD CONSTRAINT "ClientMergeAudit_actorUserId_fkey"
    FOREIGN KEY ("actorUserId") REFERENCES "User"("id") ON DELETE SET NULL ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE "Client" ADD CONSTRAINT "Client_merge_metadata_check" CHECK (
    ("mergedIntoClientId" IS NULL AND "mergedAt" IS NULL AND "mergedByUserId" IS NULL)
    OR ("mergedIntoClientId" IS NOT NULL AND "mergedAt" IS NOT NULL
      AND "mergedIntoClientId" <> "id" AND "parentClientId" IS NULL)
  );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE "ClientMergeAudit" ADD CONSTRAINT "ClientMergeAudit_distinct_clients_check"
    CHECK ("sourceClientId" <> "retainedClientId");
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE "Deal" ADD CONSTRAINT "Deal_xero_routing_check" CHECK (
    ("xeroRoutingMode" IN ('FOLLOW_CLIENT', 'UNMATCHED')
      AND "xeroRoutingContactId" IS NULL AND "xeroRoutingConnectionKey" IS NULL)
    OR ("xeroRoutingMode" = 'FIXED'
      AND "xeroRoutingContactId" IS NOT NULL AND btrim("xeroRoutingContactId") <> ''
      AND "xeroRoutingConnectionKey" IS NOT NULL AND btrim("xeroRoutingConnectionKey") <> '')
  );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- Lock the referenced client while checking it. FOR SHARE conflicts with both
-- the merge's FOR UPDATE locks and ordinary Client updates, closing the race
-- between an attachment's active check and the source's final retirement.
-- The application takes sorted per-deal advisory locks first, then sorted
-- Client row locks, then Deal/Event row locks. Triggers are the final backstop.
CREATE OR REPLACE FUNCTION sales_client_attachment_guard()
RETURNS trigger LANGUAGE plpgsql SET search_path = pg_catalog, public AS $$
DECLARE
  client_id TEXT;
  merged_into TEXT;
BEGIN
  client_id := to_jsonb(NEW) ->> TG_ARGV[0];
  IF TG_OP = 'UPDATE' THEN
    IF client_id IS NOT DISTINCT FROM (to_jsonb(OLD) ->> TG_ARGV[0]) THEN
      RETURN NEW;
    END IF;
  END IF;
  IF client_id IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT c."mergedIntoClientId" INTO merged_into
    FROM public."Client" c WHERE c."id" = client_id FOR SHARE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Client does not exist' USING ERRCODE = '23503';
  END IF;
  IF merged_into IS NOT NULL THEN
    RAISE EXCEPTION 'Cannot attach a record to a merged client' USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END $$;

CREATE OR REPLACE TRIGGER sales_deal_client_active_guard
  BEFORE INSERT OR UPDATE OF "clientId" ON "Deal"
  FOR EACH ROW EXECUTE FUNCTION sales_client_attachment_guard('clientId');
CREATE OR REPLACE TRIGGER sales_client_contact_active_guard
  BEFORE INSERT OR UPDATE OF "clientId" ON "ClientContact"
  FOR EACH ROW EXECUTE FUNCTION sales_client_attachment_guard('clientId');
CREATE OR REPLACE TRIGGER sales_client_label_active_guard
  BEFORE INSERT OR UPDATE OF "clientId" ON "ClientLabelAssignment"
  FOR EACH ROW EXECUTE FUNCTION sales_client_attachment_guard('clientId');
CREATE OR REPLACE TRIGGER sales_client_event_active_guard
  BEFORE INSERT OR UPDATE OF "clientId" ON "ClientEvent"
  FOR EACH ROW EXECUTE FUNCTION sales_client_attachment_guard('clientId');
CREATE OR REPLACE TRIGGER sales_client_parent_active_guard
  BEFORE INSERT OR UPDATE OF "parentClientId" ON "Client"
  FOR EACH ROW EXECUTE FUNCTION sales_client_attachment_guard('parentClientId');

CREATE OR REPLACE FUNCTION sales_client_merge_guard()
RETURNS trigger LANGUAGE plpgsql SET search_path = pg_catalog, public AS $$
DECLARE
  target_merged_into TEXT;
BEGIN
  IF TG_OP <> 'INSERT' AND OLD."mergedIntoClientId" IS NOT NULL THEN
    -- Deleting a shared User may null the FK, but may not rewrite evidence.
    IF TG_OP = 'UPDATE' AND pg_trigger_depth() > 1
      AND OLD."mergedByUserId" IS NOT NULL AND NEW."mergedByUserId" IS NULL
      AND (to_jsonb(NEW) - 'mergedByUserId') IS NOT DISTINCT FROM (to_jsonb(OLD) - 'mergedByUserId') THEN
      RETURN NEW;
    END IF;
    RAISE EXCEPTION 'Merged client records are immutable' USING ERRCODE = '23514';
  END IF;
  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  END IF;
  IF NEW."mergedIntoClientId" IS NULL THEN
    RETURN NEW;
  END IF;
  IF TG_OP = 'INSERT' THEN
    RAISE EXCEPTION 'A merged client must originate from an existing active client' USING ERRCODE = '23514';
  END IF;

  SELECT c."mergedIntoClientId" INTO target_merged_into
    FROM public."Client" c WHERE c."id" = NEW."mergedIntoClientId" FOR SHARE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Retained client does not exist' USING ERRCODE = '23503';
  END IF;
  IF target_merged_into IS NOT NULL THEN
    RAISE EXCEPTION 'Retained client has already been merged' USING ERRCODE = '23514';
  END IF;

  -- Retire source LAST. Prior aliases/audits can still point here; links may
  -- follow an alias chain. No live or soft-deleted child rows may be stranded.
  IF EXISTS (SELECT 1 FROM public."Deal" WHERE "clientId" = OLD."id")
    OR EXISTS (SELECT 1 FROM public."ClientContact" WHERE "clientId" = OLD."id")
    OR EXISTS (SELECT 1 FROM public."ClientLabelAssignment" WHERE "clientId" = OLD."id")
    OR EXISTS (SELECT 1 FROM public."ClientEvent" WHERE "clientId" = OLD."id")
    OR EXISTS (SELECT 1 FROM public."Client" WHERE "parentClientId" = OLD."id") THEN
    RAISE EXCEPTION 'Move every client relationship before retiring the source' USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END $$;

CREATE OR REPLACE TRIGGER sales_client_merge_guard
  BEFORE INSERT OR UPDATE OR DELETE ON "Client"
  FOR EACH ROW EXECUTE FUNCTION sales_client_merge_guard();

CREATE OR REPLACE FUNCTION sales_client_merge_audit_guard()
RETURNS trigger LANGUAGE plpgsql SET search_path = pg_catalog, public AS $$
BEGIN
  IF TG_OP = 'UPDATE' AND pg_trigger_depth() > 1
    AND OLD."actorUserId" IS NOT NULL AND NEW."actorUserId" IS NULL
    AND (to_jsonb(NEW) - 'actorUserId') IS NOT DISTINCT FROM (to_jsonb(OLD) - 'actorUserId') THEN
    RETURN NEW;
  END IF;
  RAISE EXCEPTION 'Client merge audit records are immutable' USING ERRCODE = '23514';
END $$;

CREATE OR REPLACE TRIGGER sales_client_merge_audit_guard
  BEFORE UPDATE OR DELETE ON "ClientMergeAudit"
  FOR EACH ROW EXECUTE FUNCTION sales_client_merge_audit_guard();

COMMIT;
