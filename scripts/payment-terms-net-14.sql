-- Add NET_14 to the PaymentTerms enum for the sales app — safe to run on production.
-- Apply: npx prisma db execute --file scripts/payment-terms-net-14.sql --schema prisma/schema.prisma

ALTER TYPE "PaymentTerms" ADD VALUE IF NOT EXISTS 'NET_14';
