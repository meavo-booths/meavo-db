-- Days excluded from clock stats (events retained).
-- Apply: npx prisma db execute --file scripts/add-clock-excluded-days.sql --schema prisma/schema.prisma

CREATE TABLE IF NOT EXISTS "clock_excluded_days" (
  "id" TEXT NOT NULL,
  "date" TEXT NOT NULL,
  "reason" TEXT,
  "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "clock_excluded_days_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX IF NOT EXISTS "clock_excluded_days_date_key" ON "clock_excluded_days"("date");
