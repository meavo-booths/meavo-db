-- Add six add-on product families used by sales (Ethernet, Privacy Glass,
-- Wheels, Customisation Fees, Add-on Promos, Other).
-- Apply: npx prisma db execute --file scripts/addon-families-batch.sql --schema prisma/schema.prisma

ALTER TYPE "AddOnProductFamily" ADD VALUE IF NOT EXISTS 'ETHERNET';
ALTER TYPE "AddOnProductFamily" ADD VALUE IF NOT EXISTS 'PRIVACY_GLASS';
ALTER TYPE "AddOnProductFamily" ADD VALUE IF NOT EXISTS 'WHEELS';
ALTER TYPE "AddOnProductFamily" ADD VALUE IF NOT EXISTS 'CUSTOMISATION_FEES';
ALTER TYPE "AddOnProductFamily" ADD VALUE IF NOT EXISTS 'ADDON_PROMOS';
ALTER TYPE "AddOnProductFamily" ADD VALUE IF NOT EXISTS 'OTHER';
