-- Clock kiosk heartbeat table — additive only.
-- Apply: npx prisma db execute --file scripts/add-clock-devices.sql --schema prisma/schema.prisma

CREATE TABLE IF NOT EXISTS "clock_devices" (
  "id" TEXT NOT NULL,
  "station_id" TEXT NOT NULL,
  "last_seen_at" TIMESTAMP(3) NOT NULL,
  "firmware_version" TEXT,
  "uptime_sec" INTEGER,
  "wifi_rssi" INTEGER,
  "queue_unsynced" INTEGER,
  "rfid_ok" BOOLEAN NOT NULL DEFAULT true,
  "last_event" TEXT,
  "last_error" TEXT,
  "boot_count" INTEGER,
  "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updated_at" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "clock_devices_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX IF NOT EXISTS "clock_devices_station_id_key" ON "clock_devices"("station_id");
