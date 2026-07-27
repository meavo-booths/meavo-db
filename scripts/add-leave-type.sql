-- Apply: add LeaveType enum + VacationRequest.leaveType (default PAID) for hols
-- Idempotent — safe to re-run.

DO $$ BEGIN
  CREATE TYPE "LeaveType" AS ENUM ('PAID', 'SICK', 'UNPAID');
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

ALTER TABLE "VacationRequest"
  ADD COLUMN IF NOT EXISTS "leaveType" "LeaveType" NOT NULL DEFAULT 'PAID';

CREATE INDEX IF NOT EXISTS "VacationRequest_leaveType_idx"
  ON "VacationRequest"("leaveType");
