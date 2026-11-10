-- Sales: approval-required deal labels. DealLabel.requiresApproval marks a label
-- that only a Super Admin applies directly; anyone else raises a
-- DealLabelApprovalRequest, which becomes a DealLabelAssignment on approval.
-- Additive and idempotent; older clients ignore the column, enum and table.
-- The requiresApproval CHECK and the one-pending-request partial unique index are
-- intentional and are not represented in Prisma.
-- Apply: scripts/apply-sql.sh staging scripts/sales-label-approvals.sql --env-file <staging env>

BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';

ALTER TABLE "DealLabel"
  ADD COLUMN IF NOT EXISTS "requiresApproval" BOOLEAN NOT NULL DEFAULT false;

DO $$ BEGIN
  ALTER TABLE "DealLabel" ADD CONSTRAINT "DealLabel_requiresApproval_check"
    CHECK (
      NOT "requiresApproval"
      OR ("kind" = 'STANDARD' AND "normalizedName" <> 'oa invoice' AND "hubspotCampaignId" IS NULL)
    );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE TYPE "DealLabelApprovalStatus" AS ENUM ('PENDING', 'APPROVED', 'REJECTED', 'CANCELLED');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE TABLE IF NOT EXISTS "DealLabelApprovalRequest" (
  "id"                TEXT NOT NULL,
  "dealId"            TEXT NOT NULL,
  "labelId"           TEXT NOT NULL,
  "status"            "DealLabelApprovalStatus" NOT NULL DEFAULT 'PENDING',
  "requestedByUserId" TEXT NOT NULL,
  "requestedAt"       TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "decidedByUserId"   TEXT,
  "decidedAt"         TIMESTAMP(3),
  "decisionNote"      TEXT,
  CONSTRAINT "DealLabelApprovalRequest_pkey" PRIMARY KEY ("id")
);

CREATE INDEX IF NOT EXISTS "DealLabelApprovalRequest_dealId_status_idx"
  ON "DealLabelApprovalRequest"("dealId", "status");

CREATE INDEX IF NOT EXISTS "DealLabelApprovalRequest_labelId_idx"
  ON "DealLabelApprovalRequest"("labelId");

CREATE INDEX IF NOT EXISTS "DealLabelApprovalRequest_status_requestedAt_idx"
  ON "DealLabelApprovalRequest"("status", "requestedAt");

-- SQL-only: at most one open request per deal and label.
CREATE UNIQUE INDEX IF NOT EXISTS "DealLabelApprovalRequest_one_pending_key"
  ON "DealLabelApprovalRequest"("dealId", "labelId") WHERE "status" = 'PENDING';

DO $$ BEGIN
  ALTER TABLE "DealLabelApprovalRequest"
    ADD CONSTRAINT "DealLabelApprovalRequest_dealId_fkey"
    FOREIGN KEY ("dealId") REFERENCES "Deal"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE "DealLabelApprovalRequest"
    ADD CONSTRAINT "DealLabelApprovalRequest_labelId_fkey"
    FOREIGN KEY ("labelId") REFERENCES "DealLabel"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

COMMIT;
