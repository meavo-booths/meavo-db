-- HubSpot deal link on Deal plus the mirrored closed-lost reason options for
-- the sales app — additive only, safe to run on production.
-- Apply: npx prisma db execute --file scripts/hubspot-deal-link.sql --schema prisma/schema.prisma

ALTER TABLE "Deal"
  ADD COLUMN IF NOT EXISTS "hubspotDealId" TEXT;

ALTER TABLE "Deal"
  ADD COLUMN IF NOT EXISTS "hubspotDealName" TEXT;

ALTER TABLE "Deal"
  ADD COLUMN IF NOT EXISTS "hubspotFileId" TEXT;

ALTER TABLE "Deal"
  ADD COLUMN IF NOT EXISTS "hubspotNoteId" TEXT;

ALTER TABLE "Deal"
  ADD COLUMN IF NOT EXISTS "hubspotSyncedAt" TIMESTAMP(3);

ALTER TABLE "Deal"
  ADD COLUMN IF NOT EXISTS "hubspotSyncError" TEXT;

ALTER TABLE "Deal"
  ADD COLUMN IF NOT EXISTS "hubspotAmountSyncedAt" TIMESTAMP(3);

CREATE INDEX IF NOT EXISTS "Deal_hubspotDealId_idx" ON "Deal"("hubspotDealId");

-- Lost reason moves to HubSpot's option list. The LostReason enum column stays
-- in place for legacy readers and historical reporting.
ALTER TABLE "Deal"
  ADD COLUMN IF NOT EXISTS "lostReasonCode" TEXT;

ALTER TABLE "Deal"
  ADD COLUMN IF NOT EXISTS "lostReasonLabel" TEXT;

CREATE TABLE IF NOT EXISTS "HubSpotLostReason" (
  "id"           TEXT NOT NULL,
  "value"        TEXT NOT NULL,
  "label"        TEXT NOT NULL,
  "displayOrder" INTEGER NOT NULL DEFAULT 0,
  "archived"     BOOLEAN NOT NULL DEFAULT false,
  "syncedAt"     TIMESTAMP(3) NOT NULL,
  "createdAt"    TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt"    TIMESTAMP(3) NOT NULL,
  CONSTRAINT "HubSpotLostReason_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX IF NOT EXISTS "HubSpotLostReason_value_key" ON "HubSpotLostReason"("value");

CREATE INDEX IF NOT EXISTS "HubSpotLostReason_archived_displayOrder_idx"
  ON "HubSpotLostReason"("archived", "displayOrder");
