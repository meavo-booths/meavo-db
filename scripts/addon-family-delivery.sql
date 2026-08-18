-- Add Delivery to the add-on / service product families used by sales.
-- Apply: npx prisma db execute --file scripts/addon-family-delivery.sql --schema prisma/schema.prisma

ALTER TYPE "AddOnProductFamily" ADD VALUE IF NOT EXISTS 'DELIVERY';
