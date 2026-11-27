-- Due date of a deal's Xero invoices, kept by the sales app: set when Sales
-- creates the invoice and refreshed by its Xero payment sync. The Assembly app
-- reads them to fill the Delivery Tracker's "Due date" column. Additive and
-- idempotent; existing deals start with NULL and are filled by the sync.
-- Apply: scripts/apply-sql.sh staging scripts/sales-xero-invoice-due-dates.sql --env-file <staging env>

BEGIN;

ALTER TABLE "Deal"
  ADD COLUMN IF NOT EXISTS "xeroInvoiceDueDate" DATE,
  ADD COLUMN IF NOT EXISTS "xeroFinalInvoiceDueDate" DATE;

COMMIT;
