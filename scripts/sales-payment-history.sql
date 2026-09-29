-- Owner: Sales. Additive, transactional and idempotent; existing rows unchanged.
-- Apply: npx prisma db execute --file scripts/sales-payment-history.sql --schema prisma/schema.prisma
-- Verify the isolated database target first. Production requires release approval.
-- Rollback: revert consumer app; retain the ledger and its history.
BEGIN;
SET LOCAL lock_timeout = '5s';
CREATE TABLE IF NOT EXISTS "SalesPayment" (
  id TEXT PRIMARY KEY,
  "dealId" TEXT REFERENCES "Deal"(id) ON DELETE SET NULL ON UPDATE CASCADE,
  source TEXT NOT NULL CHECK (source IN ('XERO','MANUAL','OA')),
  "invoiceKey" TEXT NOT NULL,
  "xeroPaymentId" TEXT,
  "xeroInvoiceId" TEXT,
  "receivedOn" DATE,
  amount DECIMAL(18,6) NOT NULL CHECK (amount >= 0),
  currency TEXT NOT NULL CHECK (currency ~ '^[A-Z]{3}$'),
  "amountEur" DECIMAL(18,2) CHECK ("amountEur" >= 0),
  reference TEXT NOT NULL DEFAULT '',
  "recordedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "voidedAt" TIMESTAMP(3),
  "recordedById" TEXT,
  CHECK (("receivedOn" IS NULL) = ("amountEur" IS NULL)),
  CHECK ((source = 'XERO') = ("xeroPaymentId" IS NOT NULL)),
  CHECK (source <> 'XERO' OR ("xeroInvoiceId" IS NOT NULL AND "receivedOn" IS NOT NULL)),
  CHECK ("receivedOn" IS NOT NULL OR id = 'opening:' || "dealId")
);
CREATE UNIQUE INDEX IF NOT EXISTS "SalesPayment_xeroPaymentId_key" ON "SalesPayment"("xeroPaymentId");
CREATE INDEX IF NOT EXISTS "SalesPayment_receivedOn_voidedAt_idx" ON "SalesPayment"("receivedOn","voidedAt");
CREATE INDEX IF NOT EXISTS "SalesPayment_dealId_idx" ON "SalesPayment"("dealId");
CREATE INDEX IF NOT EXISTS "SalesPayment_xeroInvoiceId_idx" ON "SalesPayment"("xeroInvoiceId");
CREATE TABLE IF NOT EXISTS "SalesPaymentWindow" (
  id TEXT PRIMARY KEY, "fromDate" DATE NOT NULL, "toDate" DATE NOT NULL,
  "syncedAt" TIMESTAMP(3) NOT NULL, CHECK ("toDate">"fromDate")
);
CREATE TABLE IF NOT EXISTS "SalesPaymentSync" (
  id TEXT PRIMARY KEY DEFAULT 'xero' CHECK (id='xero'),
  "leaseToken" TEXT, "leaseExpiresAt" TIMESTAMP(3),
  "lastSuccessAt" TIMESTAMP(3), "lastError" TEXT,
  CHECK (("leaseToken" IS NULL) = ("leaseExpiresAt" IS NULL))
);
COMMIT;
