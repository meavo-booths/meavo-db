-- HubSpot deal activity snapshots for the sales app: one row per linked HubSpot
-- deal, refreshed by the sales HubSpot cron — additive only, safe to run on
-- production.
-- Apply: npx prisma db execute --file scripts/hubspot-deal-snapshot.sql --schema prisma/schema.prisma

CREATE TABLE IF NOT EXISTS "HubSpotDealSnapshot" (
  "id"               TEXT NOT NULL,
  "dealName"         TEXT NOT NULL,
  "stageId"          TEXT,
  "stageLabel"       TEXT,
  "stageEnteredAt"   TIMESTAMP(3),
  "closeDate"        TIMESTAMP(3),
  "hubspotCreatedAt" TIMESTAMP(3),
  "ownerId"          TEXT,
  "ownerName"        TEXT,
  "source"           TEXT,
  "latestSource"     TEXT,
  "lastActivityAt"   TIMESTAMP(3),
  "lastActivityType" TEXT,
  "lastContactedAt"  TIMESTAMP(3),
  "lastReplyAt"      TIMESTAMP(3),
  "lastMeetingAt"    TIMESTAMP(3),
  "nextActivityAt"   TIMESTAMP(3),
  "nextStep"         TEXT,
  "contactedCount"   INTEGER,
  "activityCount"    INTEGER,
  "stageDurations"   JSONB,
  "syncedAt"         TIMESTAMP(3) NOT NULL,
  "createdAt"        TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt"        TIMESTAMP(3) NOT NULL,
  CONSTRAINT "HubSpotDealSnapshot_pkey" PRIMARY KEY ("id")
);

CREATE INDEX IF NOT EXISTS "HubSpotDealSnapshot_lastContactedAt_idx"
  ON "HubSpotDealSnapshot"("lastContactedAt");

CREATE INDEX IF NOT EXISTS "HubSpotDealSnapshot_nextActivityAt_idx"
  ON "HubSpotDealSnapshot"("nextActivityAt");
