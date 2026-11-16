-- Apply: scripts/apply-sql.sh staging scripts/sales-zamp-invoice-reporting.sql
-- Additive only. No legacy deals are enrolled and no tax transactions are changed.
BEGIN;
ALTER TABLE "Deal" ADD COLUMN IF NOT EXISTS "zampInvoiceReportingAt" TIMESTAMP(3);
ALTER TABLE "Deal" ADD COLUMN IF NOT EXISTS "zampInvoiceCheckedAt" TIMESTAMP(3);
CREATE TABLE IF NOT EXISTS "ZampInvoiceReport" (
  "id" TEXT NOT NULL PRIMARY KEY,
  "dealId" TEXT NOT NULL,
  "xeroInvoiceId" TEXT NOT NULL,
  "invoiceNumber" TEXT NOT NULL,
  "transactionId" TEXT NOT NULL,
  "status" TEXT NOT NULL DEFAULT 'DRAFT',
  "payload" JSONB NOT NULL,
  "syncedAt" TIMESTAMP(3),
  "removedAt" TIMESTAMP(3),
  "syncError" TEXT,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "ZampInvoiceReport_dealId_fkey" FOREIGN KEY ("dealId") REFERENCES "Deal"("id") ON DELETE RESTRICT ON UPDATE CASCADE
);
CREATE UNIQUE INDEX IF NOT EXISTS "ZampInvoiceReport_xeroInvoiceId_key" ON "ZampInvoiceReport"("xeroInvoiceId");
CREATE UNIQUE INDEX IF NOT EXISTS "ZampInvoiceReport_transactionId_key" ON "ZampInvoiceReport"("transactionId");
CREATE INDEX IF NOT EXISTS "ZampInvoiceReport_dealId_idx" ON "ZampInvoiceReport"("dealId");
COMMIT;
