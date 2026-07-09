-- Add task-only external assignee scope (MEMBER = board member owner, EXTERNAL = task-only access).

DO $$ BEGIN
  CREATE TYPE "TaskAssigneeScope" AS ENUM ('MEMBER', 'EXTERNAL');
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

ALTER TABLE "TaskAssignee"
  ADD COLUMN IF NOT EXISTS "scope" "TaskAssigneeScope" NOT NULL DEFAULT 'MEMBER';

CREATE INDEX IF NOT EXISTS "TaskAssignee_userId_scope_idx" ON "TaskAssignee"("userId", "scope");
