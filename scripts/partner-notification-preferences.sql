-- Per-partner mute for assembly partner email notifications.
-- Additive only. Idempotent.
-- Apply: npx prisma db execute --file scripts/partner-notification-preferences.sql --schema prisma/schema.prisma

CREATE TABLE IF NOT EXISTS "PartnerNotificationPreference" (
  "id" TEXT NOT NULL,
  "partnerId" TEXT NOT NULL,
  "eventType" TEXT NOT NULL,
  "enabled" BOOLEAN NOT NULL DEFAULT true,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

  CONSTRAINT "PartnerNotificationPreference_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX IF NOT EXISTS "PartnerNotificationPreference_partnerId_eventType_key"
  ON "PartnerNotificationPreference"("partnerId", "eventType");

CREATE INDEX IF NOT EXISTS "PartnerNotificationPreference_eventType_idx"
  ON "PartnerNotificationPreference"("eventType");

DO $$ BEGIN
  ALTER TABLE "PartnerNotificationPreference"
    ADD CONSTRAINT "PartnerNotificationPreference_partnerId_fkey"
    FOREIGN KEY ("partnerId") REFERENCES "AssemblyPartner"("id")
    ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
