-- Clock-In tables only — safe to run on production without touching other schemas.
-- Apply: npx prisma db execute --file scripts/add-clock-tables.sql --schema prisma/schema.prisma

DO $$ BEGIN
  CREATE TYPE "ClockPendingStatus" AS ENUM ('PENDING', 'ASSIGNED', 'EXPIRED');
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE TYPE "ClockEventType" AS ENUM ('IN', 'OUT');
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

CREATE TABLE IF NOT EXISTS "clock_workers" (
  "id" TEXT NOT NULL,
  "name" TEXT NOT NULL,
  "active" BOOLEAN NOT NULL DEFAULT true,
  "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "clock_workers_pkey" PRIMARY KEY ("id")
);

CREATE TABLE IF NOT EXISTS "clock_card_bindings" (
  "id" TEXT NOT NULL,
  "uid" TEXT NOT NULL,
  "worker_id" TEXT NOT NULL,
  "active" BOOLEAN NOT NULL DEFAULT true,
  "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "deactivated_at" TIMESTAMP(3),
  CONSTRAINT "clock_card_bindings_pkey" PRIMARY KEY ("id")
);

CREATE TABLE IF NOT EXISTS "clock_pending_uids" (
  "id" TEXT NOT NULL,
  "uid" TEXT NOT NULL,
  "station_id" TEXT NOT NULL,
  "tapped_at" TEXT NOT NULL,
  "expires_at" TIMESTAMP(3) NOT NULL,
  "status" "ClockPendingStatus" NOT NULL DEFAULT 'PENDING',
  "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "clock_pending_uids_pkey" PRIMARY KEY ("id")
);

CREATE TABLE IF NOT EXISTS "clock_unassigned_taps" (
  "id" TEXT NOT NULL,
  "uid" TEXT NOT NULL,
  "station_id" TEXT NOT NULL,
  "tapped_at" TEXT NOT NULL,
  "pending_uid_id" TEXT,
  "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "clock_unassigned_taps_pkey" PRIMARY KEY ("id")
);

CREATE TABLE IF NOT EXISTS "clock_events" (
  "id" TEXT NOT NULL,
  "uid" TEXT NOT NULL,
  "worker_id" TEXT NOT NULL,
  "station_id" TEXT NOT NULL,
  "event_type" "ClockEventType" NOT NULL,
  "tapped_at" TEXT NOT NULL,
  "idempotency_key" TEXT NOT NULL,
  "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "clock_events_pkey" PRIMARY KEY ("id")
);

CREATE TABLE IF NOT EXISTS "clock_work_settings" (
  "id" TEXT NOT NULL DEFAULT 'default',
  "shift_start" TEXT NOT NULL DEFAULT '07:30',
  "shift_end" TEXT NOT NULL DEFAULT '16:30',
  "timezone" TEXT NOT NULL DEFAULT 'Europe/Sofia',
  CONSTRAINT "clock_work_settings_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX IF NOT EXISTS "clock_events_idempotency_key_key" ON "clock_events"("idempotency_key");
CREATE INDEX IF NOT EXISTS "clock_card_bindings_uid_active_idx" ON "clock_card_bindings"("uid", "active");
CREATE INDEX IF NOT EXISTS "clock_pending_uids_status_idx" ON "clock_pending_uids"("status");
CREATE INDEX IF NOT EXISTS "clock_pending_uids_uid_idx" ON "clock_pending_uids"("uid");
CREATE INDEX IF NOT EXISTS "clock_events_tapped_at_idx" ON "clock_events"("tapped_at");
CREATE INDEX IF NOT EXISTS "clock_events_worker_id_idx" ON "clock_events"("worker_id");

DO $$ BEGIN
  ALTER TABLE "clock_card_bindings"
    ADD CONSTRAINT "clock_card_bindings_worker_id_fkey"
    FOREIGN KEY ("worker_id") REFERENCES "clock_workers"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE "clock_unassigned_taps"
    ADD CONSTRAINT "clock_unassigned_taps_pending_uid_id_fkey"
    FOREIGN KEY ("pending_uid_id") REFERENCES "clock_pending_uids"("id") ON DELETE SET NULL ON UPDATE CASCADE;
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE "clock_events"
    ADD CONSTRAINT "clock_events_worker_id_fkey"
    FOREIGN KEY ("worker_id") REFERENCES "clock_workers"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

INSERT INTO "clock_work_settings" ("id", "shift_start", "shift_end", "timezone")
VALUES ('default', '07:30', '16:30', 'Europe/Sofia')
ON CONFLICT ("id") DO NOTHING;
