-- Task management tables — safe to run on production without touching other schemas.
-- Apply: npx prisma db execute --file scripts/add-task-tables.sql --schema prisma/schema.prisma

DO $$ BEGIN
  CREATE TYPE "TaskWorkspaceType" AS ENUM ('PERSONAL', 'TEAM', 'SHARED');
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE TYPE "TaskWorkspaceRole" AS ENUM ('VIEWER', 'EDITOR');
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE TYPE "TaskPriority" AS ENUM ('NONE', 'LOW', 'MEDIUM', 'HIGH', 'URGENT');
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE TYPE "TaskStatus" AS ENUM ('OPEN', 'COMPLETED', 'CANCELLED');
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE TYPE "TaskLinkedApp" AS ENUM ('SALES', 'FACTORY', 'RP', 'ASSEMBLY', 'MRP');
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

CREATE TABLE IF NOT EXISTS "TaskWorkspace" (
  "id" TEXT NOT NULL,
  "type" "TaskWorkspaceType" NOT NULL,
  "name" TEXT NOT NULL,
  "ownerId" TEXT NOT NULL,
  "teamId" TEXT,
  "color" TEXT NOT NULL DEFAULT '#EEDCDC',
  "archivedAt" TIMESTAMP(3),
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "TaskWorkspace_pkey" PRIMARY KEY ("id")
);

CREATE TABLE IF NOT EXISTS "TaskWorkspaceMember" (
  "id" TEXT NOT NULL,
  "workspaceId" TEXT NOT NULL,
  "userId" TEXT NOT NULL,
  "role" "TaskWorkspaceRole" NOT NULL DEFAULT 'VIEWER',
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "TaskWorkspaceMember_pkey" PRIMARY KEY ("id")
);

CREATE TABLE IF NOT EXISTS "TaskBoardColumn" (
  "id" TEXT NOT NULL,
  "workspaceId" TEXT NOT NULL,
  "name" TEXT NOT NULL,
  "position" INTEGER NOT NULL DEFAULT 0,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "TaskBoardColumn_pkey" PRIMARY KEY ("id")
);

CREATE TABLE IF NOT EXISTS "Task" (
  "id" TEXT NOT NULL,
  "workspaceId" TEXT NOT NULL,
  "columnId" TEXT,
  "position" INTEGER NOT NULL DEFAULT 0,
  "title" TEXT NOT NULL,
  "description" TEXT NOT NULL DEFAULT '',
  "priority" "TaskPriority" NOT NULL DEFAULT 'NONE',
  "status" "TaskStatus" NOT NULL DEFAULT 'OPEN',
  "startDate" DATE,
  "dueDate" DATE,
  "createdById" TEXT NOT NULL,
  "completedAt" TIMESTAMP(3),
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "Task_pkey" PRIMARY KEY ("id")
);

CREATE TABLE IF NOT EXISTS "TaskAssignee" (
  "id" TEXT NOT NULL,
  "taskId" TEXT NOT NULL,
  "userId" TEXT NOT NULL,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "TaskAssignee_pkey" PRIMARY KEY ("id")
);

CREATE TABLE IF NOT EXISTS "TaskExternalLink" (
  "id" TEXT NOT NULL,
  "taskId" TEXT NOT NULL,
  "linkedApp" "TaskLinkedApp" NOT NULL,
  "entityType" TEXT NOT NULL,
  "entityId" TEXT NOT NULL,
  "displayLabel" TEXT NOT NULL DEFAULT '',
  "deepLinkUrl" TEXT NOT NULL DEFAULT '',
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "TaskExternalLink_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX IF NOT EXISTS "TaskWorkspaceMember_workspaceId_userId_key" ON "TaskWorkspaceMember"("workspaceId", "userId");
CREATE INDEX IF NOT EXISTS "TaskWorkspaceMember_userId_idx" ON "TaskWorkspaceMember"("userId");
CREATE INDEX IF NOT EXISTS "TaskWorkspace_ownerId_idx" ON "TaskWorkspace"("ownerId");
CREATE INDEX IF NOT EXISTS "TaskWorkspace_teamId_idx" ON "TaskWorkspace"("teamId");
CREATE INDEX IF NOT EXISTS "TaskWorkspace_type_idx" ON "TaskWorkspace"("type");
CREATE INDEX IF NOT EXISTS "TaskBoardColumn_workspaceId_position_idx" ON "TaskBoardColumn"("workspaceId", "position");
CREATE INDEX IF NOT EXISTS "Task_workspaceId_columnId_position_idx" ON "Task"("workspaceId", "columnId", "position");
CREATE INDEX IF NOT EXISTS "Task_dueDate_idx" ON "Task"("dueDate");
CREATE INDEX IF NOT EXISTS "Task_workspaceId_status_idx" ON "Task"("workspaceId", "status");
CREATE INDEX IF NOT EXISTS "Task_createdById_idx" ON "Task"("createdById");
CREATE UNIQUE INDEX IF NOT EXISTS "TaskAssignee_taskId_userId_key" ON "TaskAssignee"("taskId", "userId");
CREATE INDEX IF NOT EXISTS "TaskAssignee_userId_idx" ON "TaskAssignee"("userId");
CREATE INDEX IF NOT EXISTS "TaskExternalLink_taskId_idx" ON "TaskExternalLink"("taskId");
CREATE INDEX IF NOT EXISTS "TaskExternalLink_linkedApp_entityType_entityId_idx" ON "TaskExternalLink"("linkedApp", "entityType", "entityId");

DO $$ BEGIN
  ALTER TABLE "TaskWorkspace" ADD CONSTRAINT "TaskWorkspace_ownerId_fkey" FOREIGN KEY ("ownerId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE "TaskWorkspace" ADD CONSTRAINT "TaskWorkspace_teamId_fkey" FOREIGN KEY ("teamId") REFERENCES "Team"("id") ON DELETE SET NULL ON UPDATE CASCADE;
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE "TaskWorkspaceMember" ADD CONSTRAINT "TaskWorkspaceMember_workspaceId_fkey" FOREIGN KEY ("workspaceId") REFERENCES "TaskWorkspace"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE "TaskWorkspaceMember" ADD CONSTRAINT "TaskWorkspaceMember_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE "TaskBoardColumn" ADD CONSTRAINT "TaskBoardColumn_workspaceId_fkey" FOREIGN KEY ("workspaceId") REFERENCES "TaskWorkspace"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE "Task" ADD CONSTRAINT "Task_workspaceId_fkey" FOREIGN KEY ("workspaceId") REFERENCES "TaskWorkspace"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE "Task" ADD CONSTRAINT "Task_columnId_fkey" FOREIGN KEY ("columnId") REFERENCES "TaskBoardColumn"("id") ON DELETE SET NULL ON UPDATE CASCADE;
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE "Task" ADD CONSTRAINT "Task_createdById_fkey" FOREIGN KEY ("createdById") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE "TaskAssignee" ADD CONSTRAINT "TaskAssignee_taskId_fkey" FOREIGN KEY ("taskId") REFERENCES "Task"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE "TaskAssignee" ADD CONSTRAINT "TaskAssignee_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE "TaskExternalLink" ADD CONSTRAINT "TaskExternalLink_taskId_fkey" FOREIGN KEY ("taskId") REFERENCES "Task"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;
