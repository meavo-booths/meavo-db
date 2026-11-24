-- Showrooms (owner: showroom, showroom.meavo.app): the partner locations where MEAVO
-- booths are on display ("Showroom"), the booths at each ("ShowroomBooth"), the
-- recurring Customer Service check-ups ("ShowroomCheck"), visits booked on the public
-- booking page ("ShowroomBooking"), who at MEAVO is notified about a showroom
-- ("ShowroomNotifyUser") and the app's settings ("ShowroomSetting"). Replaces the
-- "Showroom Check-Up" and "Showroom Repository" Google Sheets and Calendly.
-- Additive and idempotent: six new enums and six new tables. No existing table
-- changes, so older clients are unaffected.
-- Apply: scripts/apply-sql.sh staging scripts/add-showroom-checkups.sql --env-file <staging env>

BEGIN;

DO $$ BEGIN
  CREATE TYPE "ShowroomCheckFormat" AS ENUM ('EMAIL', 'DIRECT');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE TYPE "ShowroomCheckStatus" AS ENUM ('AWAITING_REPLY', 'COMPLETED');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE TYPE "ShowroomIssueStatus" AS ENUM ('PENDING', 'RESOLVED');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE TYPE "ShowroomBookingMode" AS ENUM ('INSTANT', 'REQUEST');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE TYPE "ShowroomStatus" AS ENUM ('ALL_GOOD', 'CHECK_NOTES', 'TEMPORARILY_CLOSED', 'PERMANENTLY_CLOSED');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE TYPE "ShowroomBookingStatus" AS ENUM ('REQUESTED', 'CONFIRMED', 'DECLINED', 'CANCELLED');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE TABLE IF NOT EXISTS "Showroom" (
    "id" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "country" TEXT NOT NULL,
    "city" TEXT NOT NULL,
    "tier" INTEGER NOT NULL,
    "checkFrequencyMonths" INTEGER,
    "modelsOnDisplay" TEXT NOT NULL DEFAULT '',
    "responsible" TEXT NOT NULL DEFAULT '',
    "driveFolderUrl" TEXT NOT NULL DEFAULT '',
    "notes" TEXT NOT NULL DEFAULT '',
    "address" TEXT NOT NULL DEFAULT '',
    "buildingType" TEXT NOT NULL DEFAULT '',
    "contactName" TEXT NOT NULL DEFAULT '',
    "contactJobTitle" TEXT NOT NULL DEFAULT '',
    "contactEmail" TEXT NOT NULL DEFAULT '',
    "contactPhone" TEXT NOT NULL DEFAULT '',
    "appointmentContactName" TEXT NOT NULL DEFAULT '',
    "appointmentContactJobTitle" TEXT NOT NULL DEFAULT '',
    "appointmentContactEmail" TEXT NOT NULL DEFAULT '',
    "appointmentContactPhone" TEXT NOT NULL DEFAULT '',
    "notifyShowroomEmails" TEXT[] DEFAULT ARRAY[]::TEXT[],
    "googleMapsUrl" TEXT NOT NULL DEFAULT '',
    "contractNotes" TEXT NOT NULL DEFAULT '',
    "contractStartOn" DATE,
    "contractEndOn" DATE,
    "contractOpenEnded" BOOLEAN NOT NULL DEFAULT false,
    "boothsPassToPartner" BOOLEAN,
    "appointmentNeeded" BOOLEAN,
    "showOnWebsite" BOOLEAN NOT NULL DEFAULT false,
    "description" TEXT NOT NULL DEFAULT '',
    "descriptionEn" TEXT NOT NULL DEFAULT '',
    "bookingDescription" TEXT NOT NULL DEFAULT '',
    "bookingDescriptionEn" TEXT NOT NULL DEFAULT '',
    "directions" TEXT NOT NULL DEFAULT '',
    "directionsEn" TEXT NOT NULL DEFAULT '',
    "arrivalInstructions" TEXT NOT NULL DEFAULT '',
    "arrivalInstructionsEn" TEXT NOT NULL DEFAULT '',
    "openingHours" TEXT NOT NULL DEFAULT '',
    "calendlyUrl" TEXT NOT NULL DEFAULT '',
    "bookingSlug" TEXT,
    "language" TEXT NOT NULL DEFAULT 'en',
    "bookingEnabled" BOOLEAN NOT NULL DEFAULT false,
    "timeZone" TEXT NOT NULL DEFAULT 'Europe/London',
    "bookingHours" TEXT NOT NULL DEFAULT '',
    "bookingMode" "ShowroomBookingMode" NOT NULL DEFAULT 'REQUEST',
    "bookingLeadDays" INTEGER NOT NULL DEFAULT 1,
    "reviewUrl" TEXT NOT NULL DEFAULT '',
    "websiteUrl" TEXT NOT NULL DEFAULT '',
    "actionToBeTaken" TEXT NOT NULL DEFAULT '',
    "status" "ShowroomStatus" NOT NULL DEFAULT 'ALL_GOOD',
    "statusNote" TEXT NOT NULL DEFAULT '',
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,
    CONSTRAINT "Showroom_pkey" PRIMARY KEY ("id")
);

CREATE TABLE IF NOT EXISTS "ShowroomCheck" (
    "id" TEXT NOT NULL,
    "showroomId" TEXT NOT NULL,
    "checkedOn" DATE NOT NULL,
    "format" "ShowroomCheckFormat",
    "status" "ShowroomCheckStatus" NOT NULL DEFAULT 'COMPLETED',
    "contactPerson" TEXT NOT NULL DEFAULT '',
    "responsible" TEXT NOT NULL DEFAULT '',
    "issuesFound" BOOLEAN,
    "issueStatus" "ShowroomIssueStatus",
    "issueResolvedOn" DATE,
    "notes" TEXT NOT NULL DEFAULT '',
    "evidenceInDrive" BOOLEAN,
    "checklist" JSONB,
    "recordedById" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,
    CONSTRAINT "ShowroomCheck_pkey" PRIMARY KEY ("id")
);

CREATE TABLE IF NOT EXISTS "ShowroomBooking" (
    "id" TEXT NOT NULL,
    "showroomId" TEXT NOT NULL,
    "startsAt" TIMESTAMP(3) NOT NULL,
    "endsAt" TIMESTAMP(3) NOT NULL,
    "status" "ShowroomBookingStatus" NOT NULL,
    "slotKey" TEXT,
    "token" TEXT NOT NULL,
    "visitorName" TEXT NOT NULL,
    "visitorEmail" TEXT NOT NULL,
    "visitorPhone" TEXT NOT NULL DEFAULT '',
    "visitorCompany" TEXT NOT NULL DEFAULT '',
    "message" TEXT NOT NULL DEFAULT '',
    "language" TEXT NOT NULL DEFAULT 'en',
    "decidedById" TEXT,
    "decidedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,
    CONSTRAINT "ShowroomBooking_pkey" PRIMARY KEY ("id")
);

CREATE TABLE IF NOT EXISTS "ShowroomSetting" (
    "key" TEXT NOT NULL,
    "value" JSONB NOT NULL,
    "updatedById" TEXT,
    "updatedAt" TIMESTAMP(3) NOT NULL,
    CONSTRAINT "ShowroomSetting_pkey" PRIMARY KEY ("key")
);

CREATE TABLE IF NOT EXISTS "ShowroomBooth" (
    "id" TEXT NOT NULL,
    "showroomId" TEXT NOT NULL,
    "model" TEXT NOT NULL,
    "boothId" TEXT NOT NULL DEFAULT '',
    "version" TEXT NOT NULL DEFAULT '',
    "installedOn" DATE,
    "conditionRating" INTEGER,
    "note" TEXT NOT NULL DEFAULT '',
    "position" INTEGER NOT NULL DEFAULT 0,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,
    CONSTRAINT "ShowroomBooth_pkey" PRIMARY KEY ("id")
);

CREATE TABLE IF NOT EXISTS "ShowroomNotifyUser" (
    "showroomId" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "ShowroomNotifyUser_pkey" PRIMARY KEY ("showroomId","userId")
);

CREATE UNIQUE INDEX IF NOT EXISTS "Showroom_bookingSlug_key" ON "Showroom"("bookingSlug");

CREATE INDEX IF NOT EXISTS "Showroom_status_country_city_idx" ON "Showroom"("status", "country", "city");

CREATE INDEX IF NOT EXISTS "ShowroomCheck_showroomId_checkedOn_idx" ON "ShowroomCheck"("showroomId", "checkedOn");

CREATE INDEX IF NOT EXISTS "ShowroomCheck_issueStatus_idx" ON "ShowroomCheck"("issueStatus");

CREATE INDEX IF NOT EXISTS "ShowroomCheck_recordedById_idx" ON "ShowroomCheck"("recordedById");

CREATE UNIQUE INDEX IF NOT EXISTS "ShowroomBooking_slotKey_key" ON "ShowroomBooking"("slotKey");

CREATE UNIQUE INDEX IF NOT EXISTS "ShowroomBooking_token_key" ON "ShowroomBooking"("token");

CREATE INDEX IF NOT EXISTS "ShowroomBooking_showroomId_startsAt_idx" ON "ShowroomBooking"("showroomId", "startsAt");

CREATE INDEX IF NOT EXISTS "ShowroomBooking_status_startsAt_idx" ON "ShowroomBooking"("status", "startsAt");

CREATE INDEX IF NOT EXISTS "ShowroomBooking_visitorEmail_createdAt_idx" ON "ShowroomBooking"("visitorEmail", "createdAt");

CREATE INDEX IF NOT EXISTS "ShowroomBooking_decidedById_idx" ON "ShowroomBooking"("decidedById");

CREATE INDEX IF NOT EXISTS "ShowroomSetting_updatedById_idx" ON "ShowroomSetting"("updatedById");

CREATE INDEX IF NOT EXISTS "ShowroomBooth_showroomId_position_idx" ON "ShowroomBooth"("showroomId", "position");

CREATE INDEX IF NOT EXISTS "ShowroomNotifyUser_userId_idx" ON "ShowroomNotifyUser"("userId");

DO $$ BEGIN
  ALTER TABLE "ShowroomCheck"
      ADD CONSTRAINT "ShowroomCheck_showroomId_fkey" FOREIGN KEY ("showroomId") REFERENCES "Showroom"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE "ShowroomCheck"
      ADD CONSTRAINT "ShowroomCheck_recordedById_fkey" FOREIGN KEY ("recordedById") REFERENCES "User"("id") ON DELETE SET NULL ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE "ShowroomBooking"
      ADD CONSTRAINT "ShowroomBooking_showroomId_fkey" FOREIGN KEY ("showroomId") REFERENCES "Showroom"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE "ShowroomBooking"
      ADD CONSTRAINT "ShowroomBooking_decidedById_fkey" FOREIGN KEY ("decidedById") REFERENCES "User"("id") ON DELETE SET NULL ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE "ShowroomSetting"
      ADD CONSTRAINT "ShowroomSetting_updatedById_fkey" FOREIGN KEY ("updatedById") REFERENCES "User"("id") ON DELETE SET NULL ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE "ShowroomBooth"
      ADD CONSTRAINT "ShowroomBooth_showroomId_fkey" FOREIGN KEY ("showroomId") REFERENCES "Showroom"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE "ShowroomNotifyUser"
      ADD CONSTRAINT "ShowroomNotifyUser_showroomId_fkey" FOREIGN KEY ("showroomId") REFERENCES "Showroom"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE "ShowroomNotifyUser"
      ADD CONSTRAINT "ShowroomNotifyUser_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

COMMIT;
