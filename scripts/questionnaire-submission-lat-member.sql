-- A LAT crew can submit one shared questionnaire per job from the assembly calendar.
-- Partner submissions keep partnerId. Crew submissions leave partnerId null and set memberId.
-- Idempotent. Safe to run twice.
BEGIN;

ALTER TABLE "QuestionnaireSubmission" ALTER COLUMN "partnerId" DROP NOT NULL;

ALTER TABLE "QuestionnaireSubmission" ADD COLUMN IF NOT EXISTS "memberId" TEXT;

DO $$
BEGIN
  ALTER TABLE "QuestionnaireSubmission"
    ADD CONSTRAINT "QuestionnaireSubmission_memberId_fkey"
    FOREIGN KEY ("memberId") REFERENCES "AssemblyTeamMember"("id")
    ON DELETE RESTRICT ON UPDATE CASCADE;
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

CREATE INDEX IF NOT EXISTS "QuestionnaireSubmission_memberId_idx"
  ON "QuestionnaireSubmission" ("memberId");

CREATE UNIQUE INDEX IF NOT EXISTS "QuestionnaireSubmission_crew_assembly_key"
  ON "QuestionnaireSubmission" ("assemblyId")
  WHERE "partnerId" IS NULL;

DO $$
BEGIN
  ALTER TABLE "QuestionnaireSubmission"
    ADD CONSTRAINT "QuestionnaireSubmission_owner_check"
    CHECK (
      ("partnerId" IS NOT NULL AND "memberId" IS NULL)
      OR ("partnerId" IS NULL AND "memberId" IS NOT NULL)
    );
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

COMMIT;
