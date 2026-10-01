-- Sales-owned HubSpot form reporting; additive and safe to apply repeatedly.
-- Apply only to a verified non-production database until production approval:
-- npx prisma db execute --file scripts/sales-marketing.sql --schema prisma/schema.prisma
CREATE TABLE IF NOT EXISTS "HubSpotMarketingSync" (
  id TEXT PRIMARY KEY DEFAULT 'default' CHECK (id = 'default'),
  "portalId" TEXT,
  "timeZone" TEXT,
  status TEXT NOT NULL DEFAULT 'IDLE' CHECK (status IN ('IDLE','RUNNING','COMPLETE','FAILED')),
  phase TEXT NOT NULL DEFAULT 'ACCOUNT' CHECK (phase IN ('ACCOUNT','FORMS','SUBMISSIONS')),
  "runId" TEXT,
  "runStartedAt" TIMESTAMP(3),
  "inventoryAfter" TEXT,
  "inventoryArchived" BOOLEAN NOT NULL DEFAULT false,
  "lastSuccessAt" TIMESTAMP(3),
  "lastError" TEXT,
  "leaseToken" TEXT,
  "leaseExpiresAt" TIMESTAMP(3),
  "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS "HubSpotMarketingForm" (
  id TEXT PRIMARY KEY,
  "portalId" TEXT NOT NULL,
  name TEXT NOT NULL,
  family TEXT CHECK (family IN ('SPEC_SHEET','CONTACT')),
  "countryCode" TEXT,
  archived BOOLEAN NOT NULL DEFAULT false,
  "seenRunId" TEXT NOT NULL,
  "cursorRunId" TEXT,
  "submissionAfter" TEXT,
  "completedRunId" TEXT,
  "lastSyncedAt" TIMESTAMP(3),
  "mappingUpdatedById" TEXT,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS "HubSpotMarketingForm_family_countryCode_idx" ON "HubSpotMarketingForm" (family,"countryCode");

-- No submitted field values or contact identifiers are retained.
CREATE TABLE IF NOT EXISTS "HubSpotMarketingSubmission" (
  "formId" TEXT NOT NULL REFERENCES "HubSpotMarketingForm"(id) ON DELETE CASCADE ON UPDATE CASCADE,
  "submissionId" TEXT NOT NULL,
  "submittedAt" TIMESTAMP(3) NOT NULL,
  "seenRunId" TEXT NOT NULL,
  PRIMARY KEY ("formId","submissionId")
);
CREATE INDEX IF NOT EXISTS "HubSpotMarketingSubmission_submittedAt_idx" ON "HubSpotMarketingSubmission" ("submittedAt");
