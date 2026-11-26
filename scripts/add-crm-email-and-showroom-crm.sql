-- Customer CRM email engine & showroom booking CRM fields (owner: showroom, showroom.meavo.app).
--   CrmEmailRule: configurable trigger & time-offset rules (shared CRM foundation for showroom
--     bookings today and future order updates, post-assembly upsells and campaigns).
--   CrmEmailJob: scheduled/sent email queue with per-message delivery, open, click, bounce
--     and reply tracking.
--   CrmEmailEvent: idempotent raw Resend webhook / reply event log.
--   ShowroomBooking: visitOutcome, visitOutcomeAt, staffNotes, rescheduledFrom, hubspotDealId,
--     hubspotDealName, hubspotLinkedAt.
--   Deal: nullable showroomBookingId link to the showroom viewing that led to a quote/deal.
-- Additive and idempotent: existing rows and older clients are unaffected.
-- Apply: scripts/apply-sql.sh staging scripts/add-crm-email-and-showroom-crm.sql --env-file <staging env>

BEGIN;

DO $$ BEGIN
  CREATE TYPE "ShowroomVisitOutcome" AS ENUM ('VISITED', 'NO_SHOW');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE TYPE "CrmEmailJobStatus" AS ENUM ('SCHEDULED', 'PROCESSING', 'SENT', 'FAILED', 'CANCELLED', 'SKIPPED');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

ALTER TABLE "Deal" ADD COLUMN IF NOT EXISTS "showroomBookingId" TEXT;

ALTER TABLE "ShowroomBooking" ADD COLUMN IF NOT EXISTS "hubspotDealId" TEXT;
ALTER TABLE "ShowroomBooking" ADD COLUMN IF NOT EXISTS "hubspotDealName" TEXT;
ALTER TABLE "ShowroomBooking" ADD COLUMN IF NOT EXISTS "hubspotLinkedAt" TIMESTAMP(3);
ALTER TABLE "ShowroomBooking" ADD COLUMN IF NOT EXISTS "rescheduledFrom" TIMESTAMP(3);
ALTER TABLE "ShowroomBooking" ADD COLUMN IF NOT EXISTS "staffNotes" TEXT NOT NULL DEFAULT '';
ALTER TABLE "ShowroomBooking" ADD COLUMN IF NOT EXISTS "visitOutcome" "ShowroomVisitOutcome";
ALTER TABLE "ShowroomBooking" ADD COLUMN IF NOT EXISTS "visitOutcomeAt" TIMESTAMP(3);

CREATE TABLE IF NOT EXISTS "CrmEmailRule" (
    "id" TEXT NOT NULL,
    "key" TEXT NOT NULL,
    "scope" TEXT NOT NULL,
    "triggerEvent" TEXT NOT NULL,
    "offsetMinutes" INTEGER NOT NULL DEFAULT 0,
    "templateKey" TEXT NOT NULL,
    "showroomId" TEXT,
    "attachCalendar" BOOLEAN NOT NULL DEFAULT false,
    "enabled" BOOLEAN NOT NULL DEFAULT true,
    "description" TEXT NOT NULL DEFAULT '',
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "CrmEmailRule_pkey" PRIMARY KEY ("id")
);

CREATE TABLE IF NOT EXISTS "CrmEmailJob" (
    "id" TEXT NOT NULL,
    "scope" TEXT NOT NULL,
    "entityType" TEXT NOT NULL,
    "entityId" TEXT NOT NULL,
    "ruleKey" TEXT NOT NULL,
    "triggerEvent" TEXT NOT NULL,
    "showroomId" TEXT,
    "showroomBookingId" TEXT,
    "idempotencyKey" TEXT NOT NULL,
    "templateKey" TEXT NOT NULL,
    "templateAlias" TEXT NOT NULL DEFAULT '',
    "language" TEXT NOT NULL DEFAULT 'en',
    "fromEmail" TEXT NOT NULL DEFAULT '',
    "replyToEmail" TEXT NOT NULL DEFAULT '',
    "toEmail" TEXT NOT NULL,
    "deliveredToEmail" TEXT NOT NULL DEFAULT '',
    "subject" TEXT NOT NULL DEFAULT '',
    "payload" JSONB NOT NULL,
    "attachCalendar" BOOLEAN NOT NULL DEFAULT false,
    "status" "CrmEmailJobStatus" NOT NULL DEFAULT 'SCHEDULED',
    "scheduledFor" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "attempts" INTEGER NOT NULL DEFAULT 0,
    "lastError" TEXT,
    "resendEmailId" TEXT,
    "rfcMessageId" TEXT,
    "sentAt" TIMESTAMP(3),
    "deliveredAt" TIMESTAMP(3),
    "firstOpenedAt" TIMESTAMP(3),
    "lastOpenedAt" TIMESTAMP(3),
    "openCount" INTEGER NOT NULL DEFAULT 0,
    "firstClickedAt" TIMESTAMP(3),
    "clickCount" INTEGER NOT NULL DEFAULT 0,
    "bouncedAt" TIMESTAMP(3),
    "complainedAt" TIMESTAMP(3),
    "repliedAt" TIMESTAMP(3),
    "replyCount" INTEGER NOT NULL DEFAULT 0,
    "lastProviderEvent" TEXT,
    "cancelledAt" TIMESTAMP(3),
    "cancelReason" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "CrmEmailJob_pkey" PRIMARY KEY ("id")
);

CREATE TABLE IF NOT EXISTS "CrmEmailEvent" (
    "id" TEXT NOT NULL,
    "providerEventId" TEXT NOT NULL,
    "provider" TEXT NOT NULL DEFAULT 'resend',
    "eventType" TEXT NOT NULL,
    "resendEmailId" TEXT,
    "jobId" TEXT,
    "recipientEmail" TEXT NOT NULL DEFAULT '',
    "occurredAt" TIMESTAMP(3) NOT NULL,
    "payload" JSONB NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "CrmEmailEvent_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX IF NOT EXISTS "CrmEmailRule_key_key" ON "CrmEmailRule"("key");
CREATE INDEX IF NOT EXISTS "CrmEmailRule_scope_triggerEvent_enabled_idx" ON "CrmEmailRule"("scope", "triggerEvent", "enabled");
CREATE INDEX IF NOT EXISTS "CrmEmailRule_showroomId_idx" ON "CrmEmailRule"("showroomId");

CREATE UNIQUE INDEX IF NOT EXISTS "CrmEmailJob_idempotencyKey_key" ON "CrmEmailJob"("idempotencyKey");
CREATE UNIQUE INDEX IF NOT EXISTS "CrmEmailJob_resendEmailId_key" ON "CrmEmailJob"("resendEmailId");
CREATE INDEX IF NOT EXISTS "CrmEmailJob_status_scheduledFor_idx" ON "CrmEmailJob"("status", "scheduledFor");
CREATE INDEX IF NOT EXISTS "CrmEmailJob_showroomId_sentAt_idx" ON "CrmEmailJob"("showroomId", "sentAt");
CREATE INDEX IF NOT EXISTS "CrmEmailJob_showroomBookingId_createdAt_idx" ON "CrmEmailJob"("showroomBookingId", "createdAt");
CREATE INDEX IF NOT EXISTS "CrmEmailJob_entityType_entityId_idx" ON "CrmEmailJob"("entityType", "entityId");
CREATE INDEX IF NOT EXISTS "CrmEmailJob_toEmail_sentAt_idx" ON "CrmEmailJob"("toEmail", "sentAt");

CREATE UNIQUE INDEX IF NOT EXISTS "CrmEmailEvent_providerEventId_key" ON "CrmEmailEvent"("providerEventId");
CREATE INDEX IF NOT EXISTS "CrmEmailEvent_resendEmailId_idx" ON "CrmEmailEvent"("resendEmailId");
CREATE INDEX IF NOT EXISTS "CrmEmailEvent_jobId_occurredAt_idx" ON "CrmEmailEvent"("jobId", "occurredAt");
CREATE INDEX IF NOT EXISTS "CrmEmailEvent_eventType_occurredAt_idx" ON "CrmEmailEvent"("eventType", "occurredAt");

CREATE INDEX IF NOT EXISTS "Deal_showroomBookingId_idx" ON "Deal"("showroomBookingId");
CREATE INDEX IF NOT EXISTS "ShowroomBooking_hubspotDealId_idx" ON "ShowroomBooking"("hubspotDealId");

DO $$ BEGIN
  ALTER TABLE "Deal" ADD CONSTRAINT "Deal_showroomBookingId_fkey"
    FOREIGN KEY ("showroomBookingId") REFERENCES "ShowroomBooking"("id") ON DELETE SET NULL ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE "CrmEmailRule" ADD CONSTRAINT "CrmEmailRule_showroomId_fkey"
    FOREIGN KEY ("showroomId") REFERENCES "Showroom"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE "CrmEmailJob" ADD CONSTRAINT "CrmEmailJob_showroomId_fkey"
    FOREIGN KEY ("showroomId") REFERENCES "Showroom"("id") ON DELETE SET NULL ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE "CrmEmailJob" ADD CONSTRAINT "CrmEmailJob_showroomBookingId_fkey"
    FOREIGN KEY ("showroomBookingId") REFERENCES "ShowroomBooking"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE "CrmEmailEvent" ADD CONSTRAINT "CrmEmailEvent_jobId_fkey"
    FOREIGN KEY ("jobId") REFERENCES "CrmEmailJob"("id") ON DELETE SET NULL ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

COMMIT;
