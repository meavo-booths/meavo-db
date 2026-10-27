-- Optional end-of-questionnaire notes for assembly.meavo.app submissions.
-- Additive only. Idempotent.
-- Apply: scripts/apply-sql.sh staging scripts/submission-notes.sql --env-file .env.staging

ALTER TABLE "QuestionnaireSubmission"
  ADD COLUMN IF NOT EXISTS "notes" TEXT NOT NULL DEFAULT '';
