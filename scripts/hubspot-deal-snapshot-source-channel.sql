-- HubSpotDealSnapshot.sourceChannel: the sales app's mirror of the custom
-- "Source Channel" deal property — additive only, safe to run on production.
-- Apply: npx prisma db execute --file scripts/hubspot-deal-snapshot-source-channel.sql --schema prisma/schema.prisma

ALTER TABLE "HubSpotDealSnapshot" ADD COLUMN IF NOT EXISTS "sourceChannel" TEXT;
