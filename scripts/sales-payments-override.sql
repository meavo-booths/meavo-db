-- Sales Payments right and removed-Xero-invoice tracking.
-- Apply: npx prisma db execute --file scripts/sales-payments-override.sql --schema prisma/schema.prisma
-- Additive, transactional and idempotent: three columns, no data changes.
--   ToolCardAccess.paymentsOverride   (NOT NULL DEFAULT false — every existing grant stays without it)
--   Deal.xeroInvoiceRemovedAt         (nullable)
--   Deal.xeroFinalInvoiceRemovedAt    (nullable)
-- Older Gateway/Sales releases name their columns, so they keep working unchanged.
-- Verify the actual isolated non-production target before testing. Production
-- application is part of the approved meavo-db release (RELEASE_POLICY.md).
-- Application rollback must retain these columns and any granted rights.

BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';

ALTER TABLE "ToolCardAccess"
  ADD COLUMN IF NOT EXISTS "paymentsOverride" BOOLEAN NOT NULL DEFAULT false;

ALTER TABLE "Deal"
  ADD COLUMN IF NOT EXISTS "xeroInvoiceRemovedAt" TIMESTAMP(3),
  ADD COLUMN IF NOT EXISTS "xeroFinalInvoiceRemovedAt" TIMESTAMP(3);

COMMIT;
