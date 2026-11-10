-- SubmissionEdit: changes a partner makes to a submitted assembly report during
-- the 2-day edit window (answers, notes, added photos/videos). Rows are deleted
-- with their submission. Additive and idempotent.
-- Apply: scripts/apply-sql.sh staging scripts/assembly-submission-edits.sql --env-file <staging env>

BEGIN;

CREATE TABLE IF NOT EXISTS "SubmissionEdit" (
  "id"           TEXT NOT NULL,
  "submissionId" TEXT NOT NULL,
  "kind"         TEXT NOT NULL,
  "questionId"   TEXT,
  "label"        TEXT NOT NULL DEFAULT '',
  "before"       TEXT NOT NULL DEFAULT '',
  "after"        TEXT NOT NULL DEFAULT '',
  "createdAt"    TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "SubmissionEdit_pkey" PRIMARY KEY ("id")
);

CREATE INDEX IF NOT EXISTS "SubmissionEdit_submissionId_createdAt_idx"
  ON "SubmissionEdit"("submissionId", "createdAt");

DO $$ BEGIN
  ALTER TABLE "SubmissionEdit"
    ADD CONSTRAINT "SubmissionEdit_submissionId_fkey"
    FOREIGN KEY ("submissionId") REFERENCES "QuestionnaireSubmission"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

COMMIT;
