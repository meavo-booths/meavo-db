-- DealSubscription: who receives deal update notifications in the sales app.
-- The sales rep is subscribed implicitly; muted = true opts them out, any
-- other row opts a colleague in. Additive and idempotent.
-- Apply: npx prisma db execute --file scripts/sales-deal-subscription.sql --schema prisma/schema.prisma

CREATE TABLE IF NOT EXISTS "DealSubscription" (
  "id"        TEXT NOT NULL,
  "dealId"    TEXT NOT NULL,
  "userId"    TEXT NOT NULL,
  "muted"     BOOLEAN NOT NULL DEFAULT false,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "DealSubscription_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX IF NOT EXISTS "DealSubscription_dealId_userId_key"
  ON "DealSubscription"("dealId", "userId");

CREATE INDEX IF NOT EXISTS "DealSubscription_userId_idx"
  ON "DealSubscription"("userId");

DO $$ BEGIN
  ALTER TABLE "DealSubscription"
    ADD CONSTRAINT "DealSubscription_dealId_fkey"
    FOREIGN KEY ("dealId") REFERENCES "Deal"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE "DealSubscription"
    ADD CONSTRAINT "DealSubscription_userId_fkey"
    FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
