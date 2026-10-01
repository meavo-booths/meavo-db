-- Sales DealID editing: durable integration retry state and old-ID reservation.
-- Apply: from meavo-db, after verifying the database target, run
--   npx prisma db execute --file scripts/add-sales-deal-id-rename.sql
-- Test against an isolated database first. Production needs explicit approval.
-- Additive and compatible with older generated clients. No existing rows change.
-- Roll back the consuming app first; retain the columns/trigger. Previous IDs
-- remain reserved because historical Assembly/external references may use them.

BEGIN;

ALTER TABLE "Deal" ADD COLUMN IF NOT EXISTS "dealIdRenameSync" JSONB;
ALTER TABLE "Deal" ADD COLUMN IF NOT EXISTS "previousDealIds" TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[];

CREATE OR REPLACE FUNCTION sales_deal_id_reservation_guard()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
  previous_id text;
BEGIN
  -- This exact lock is shared with the Sales transactional rename service.
  -- Normal conversion/import writers participate even when their older client
  -- has never heard of dealIdRenameSync.
  PERFORM pg_advisory_xact_lock(1819242081, 1684628580);

  -- Business IDs cannot be reassigned to another record after a rename. Old
  -- assembly identities and historical external references may still use them.
  -- Keep history monotonic even for older clients that change only dealId.
  IF TG_OP = 'UPDATE' THEN
    NEW."previousDealIds" := ARRAY(
      SELECT DISTINCT value FROM unnest(
        COALESCE(NEW."previousDealIds", ARRAY[]::TEXT[]) || OLD."previousDealIds"
        || CASE WHEN OLD."dealId" IS NOT NULL AND OLD."dealId" IS DISTINCT FROM NEW."dealId"
          THEN ARRAY[OLD."dealId"] ELSE ARRAY[]::TEXT[] END
      ) AS value WHERE value IS NOT NULL AND value <> '' ORDER BY value
    );
  END IF;

  previous_id := NEW."dealIdRenameSync"->>'oldDealId';
  IF NEW."dealIdRenameSync" IS NOT NULL AND (
    jsonb_typeof(NEW."dealIdRenameSync") <> 'object'
    OR previous_id IS NULL OR btrim(previous_id) = ''
    OR NEW."dealId" IS NULL
    OR (NEW."dealIdRenameSync"->>'newDealId') IS DISTINCT FROM NEW."dealId"
  ) THEN
    RAISE EXCEPTION 'Invalid Deal ID rename synchronization state'
      USING ERRCODE = '23514', CONSTRAINT = 'Deal_dealIdRenameSync_valid';
  END IF;

  IF EXISTS (
    SELECT 1 FROM "Deal" d WHERE d.id <> NEW.id AND (
      d."dealId" = NEW."dealId"
      OR NEW."dealId" = ANY(d."previousDealIds")
      OR d."dealId" = ANY(NEW."previousDealIds")
      OR d."previousDealIds" && NEW."previousDealIds"
      OR d."dealIdRenameSync"->>'oldDealId' = NEW."dealId"
      OR (previous_id IS NOT NULL AND (
        d."dealId" = previous_id
        OR previous_id = ANY(d."previousDealIds")
        OR d."dealIdRenameSync"->>'oldDealId' = previous_id
      ))
    )
  ) THEN
    RAISE EXCEPTION 'Deal ID is already in use or awaiting synchronization'
      USING ERRCODE = '23505', CONSTRAINT = 'Deal_dealId_rename_reservation';
  END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE TRIGGER sales_deal_id_reservation_guard
  BEFORE INSERT OR UPDATE OF "dealId", "dealIdRenameSync", "previousDealIds" ON "Deal"
  FOR EACH ROW EXECUTE FUNCTION sales_deal_id_reservation_guard();

COMMIT;
