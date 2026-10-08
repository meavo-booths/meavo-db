-- Sales: stable identity for HubSpot-owned Campaign labels and refresh health.
-- Apply: prisma db execute --file scripts/hubspot-campaign-sync.sql --schema prisma/schema.prisma
-- Verify the target first. Production requires separate human approval.
-- Additive and safe to repeat; existing names/assignments and older clients remain compatible.
BEGIN;
ALTER TABLE "DealLabel"
  ADD COLUMN IF NOT EXISTS "hubspotCampaignId" TEXT,
  ADD COLUMN IF NOT EXISTS "hubspotPortalId" TEXT,
  ADD COLUMN IF NOT EXISTS "hubspotArchived" BOOLEAN NOT NULL DEFAULT false;
CREATE UNIQUE INDEX IF NOT EXISTS "DealLabel_hubspotCampaignId_key" ON "DealLabel"("hubspotCampaignId");
CREATE TABLE IF NOT EXISTS "HubSpotCampaignSyncState" (
  "portalId" TEXT PRIMARY KEY,
  "lastAttemptedAt" TIMESTAMP(3) NOT NULL,
  "lastSyncedAt" TIMESTAMP(3),
  "lastError" TEXT
);
COMMIT;
