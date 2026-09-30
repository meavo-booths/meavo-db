-- Delivery Only visit type for assembly.meavo.app (Event Type dropdown).
-- Apply: npx prisma db execute --file scripts/add-assembly-delivery-only-event-type.sql --schema prisma/schema.prisma
-- Idempotent — safe to re-run. Additive: existing rows and values are untouched.
-- Appended last, which matches the order in prisma/schema.prisma.
--
-- Do NOT apply to the shared production database before Sales (and any other app
-- that reads "Assembly"."eventType") runs a @meavo/db client that knows this value:
-- an older generated client throws when it reads a row holding an unknown enum value.

ALTER TYPE "AssemblyEventType" ADD VALUE IF NOT EXISTS 'DELIVERY_ONLY';
