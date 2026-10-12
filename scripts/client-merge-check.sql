-- Regression checks for client-merge.sql against an ISOLATED migrated database.
-- Never run this fixture script against production. All fixtures roll back.
-- PGlite can apply the prior Prisma schema and migration without a server.

BEGIN;
SET LOCAL statement_timeout = '30s';

CREATE OR REPLACE FUNCTION pg_temp.expect_client_merge_failure(statement TEXT, expected_code TEXT)
RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE statement;
  RAISE EXCEPTION 'Statement unexpectedly succeeded: %', statement;
EXCEPTION WHEN OTHERS THEN
  IF NOT (SQLSTATE = ANY(string_to_array(expected_code, ','))) THEN
    RAISE EXCEPTION 'Expected SQLSTATE %, got %: %', expected_code, SQLSTATE, SQLERRM;
  END IF;
END $$;

DO $$
DECLARE
  prefix TEXT := 'merge-check-' || md5(random()::TEXT || clock_timestamp()::TEXT);
  source_id TEXT := prefix || '-source';
  retained_id TEXT := prefix || '-retained';
  third_id TEXT := prefix || '-third';
  child_id TEXT := prefix || '-child';
  user_id TEXT := prefix || '-user';
  deal_id TEXT := prefix || '-deal';
  contact_id TEXT := prefix || '-contact';
  label_id TEXT := prefix || '-label';
  event_id TEXT := prefix || '-event';
  receipt_id TEXT := prefix || '-receipt';
  audit_id TEXT := prefix || '-audit';
  retire_source TEXT := format('UPDATE "Client" SET "mergedIntoClientId"=%L, "mergedAt"=CURRENT_TIMESTAMP, "mergedByUserId"=%L, "parentClientId"=NULL WHERE id=%L', retained_id, user_id, source_id);
BEGIN
  INSERT INTO "User" (id, email, "updatedAt") VALUES (user_id, prefix || '@example.invalid', CURRENT_TIMESTAMP);
  INSERT INTO "Client" (id, name, "updatedAt") VALUES
    (source_id, prefix || ' source', CURRENT_TIMESTAMP),
    (retained_id, prefix || ' retained', CURRENT_TIMESTAMP),
    (third_id, prefix || ' third', CURRENT_TIMESTAMP);
  INSERT INTO "Client" (id, name, "parentClientId", "updatedAt") VALUES (child_id, prefix || ' child', source_id, CURRENT_TIMESTAMP);
  INSERT INTO "Deal" (id, "quoteNumber", "clientId", "clientName", "dealDate", "updatedAt")
    VALUES (deal_id, prefix, source_id, 'Original quote name', CURRENT_DATE, CURRENT_TIMESTAMP);
  INSERT INTO "ClientContact" (id, "clientId", name, "updatedAt") VALUES (contact_id, source_id, 'Original contact', CURRENT_TIMESTAMP);
  INSERT INTO "ClientLabel" (id, name, "normalizedName", "updatedAt") VALUES (label_id, prefix, prefix, CURRENT_TIMESTAMP);
  INSERT INTO "ClientLabelAssignment" ("clientId", "labelId") VALUES (source_id, label_id);
  -- Deleted events also have to move: receipt cleanup must retain its event/key.
  INSERT INTO "ClientEvent" (id, "clientId", title, "eventDate", "createdByName", "deletedAt", "updatedAt")
    VALUES (event_id, source_id, 'Historical dinner', CURRENT_DATE, 'Test', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP);
  INSERT INTO "ClientEventReceipt" (id, "eventId", "storageKey", "fileName", "mimeType", size, "uploadExpiresAt", "updatedAt")
    VALUES (receipt_id, event_id, 'clients/' || source_id || '/receipt.pdf', 'receipt.pdf', 'application/pdf', 8, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP);

  -- Each relationship independently blocks premature retirement.
  PERFORM pg_temp.expect_client_merge_failure(retire_source, '23514');
  UPDATE "Deal" SET "clientId"=retained_id WHERE id=deal_id;
  PERFORM pg_temp.expect_client_merge_failure(retire_source, '23514');
  UPDATE "ClientContact" SET "clientId"=retained_id WHERE id=contact_id;
  PERFORM pg_temp.expect_client_merge_failure(retire_source, '23514');
  UPDATE "ClientLabelAssignment" SET "clientId"=retained_id WHERE "clientId"=source_id AND "labelId"=label_id;
  PERFORM pg_temp.expect_client_merge_failure(retire_source, '23514');
  UPDATE "ClientEvent" SET "clientId"=retained_id WHERE id=event_id;
  PERFORM pg_temp.expect_client_merge_failure(retire_source, '23514');
  UPDATE "Client" SET "parentClientId"=retained_id WHERE id=child_id;

  INSERT INTO "ClientMergeAudit" (id, "sourceClientId", "retainedClientId", "actorUserId", "sourceSnapshot", "retainedSnapshot", resolutions, "transferredRecords")
    VALUES (audit_id, source_id, retained_id, user_id, jsonb_build_object('id',source_id), jsonb_build_object('id',retained_id), '{}'::jsonb, jsonb_build_object('events',jsonb_build_array(event_id)));
  EXECUTE retire_source;

  -- Source immutability, including no-op updates and direct attribution clearing.
  PERFORM pg_temp.expect_client_merge_failure(format('UPDATE "Client" SET notes=%L WHERE id=%L', 'changed', source_id), '23514');
  PERFORM pg_temp.expect_client_merge_failure(format('UPDATE "Client" SET "mergedIntoClientId"=NULL,"mergedAt"=NULL,"mergedByUserId"=NULL WHERE id=%L', source_id), '23514');
  PERFORM pg_temp.expect_client_merge_failure(format('UPDATE "Client" SET name=name WHERE id=%L', source_id), '23514');
  PERFORM pg_temp.expect_client_merge_failure(format('UPDATE "Client" SET "mergedByUserId"=NULL WHERE id=%L', source_id), '23514');
  PERFORM pg_temp.expect_client_merge_failure(format('DELETE FROM "Client" WHERE id=%L', source_id), '23514');
  -- PostgreSQL versions report RESTRICT as restrict_violation or foreign_key_violation.
  PERFORM pg_temp.expect_client_merge_failure(format('DELETE FROM "Client" WHERE id=%L', retained_id), '23001,23503');
  PERFORM pg_temp.expect_client_merge_failure(format('INSERT INTO "Client" (id,name,"updatedAt","mergedIntoClientId","mergedAt") VALUES (%L,%L,CURRENT_TIMESTAMP,%L,CURRENT_TIMESTAMP)',prefix||'-premerged','Premerged',retained_id),'23514');

  -- Every new attachment and every reassignment to the old source is rejected.
  PERFORM pg_temp.expect_client_merge_failure(format('INSERT INTO "Deal" (id,"quoteNumber","clientId","clientName","dealDate","updatedAt") VALUES (%L,%L,%L,%L,CURRENT_DATE,CURRENT_TIMESTAMP)',prefix||'-new-deal',prefix||'-new',source_id,'Stale quote'),'23514');
  PERFORM pg_temp.expect_client_merge_failure(format('UPDATE "Deal" SET "clientId"=%L WHERE id=%L',source_id,deal_id),'23514');
  PERFORM pg_temp.expect_client_merge_failure(format('INSERT INTO "ClientContact" (id,"clientId",name,"updatedAt") VALUES (%L,%L,%L,CURRENT_TIMESTAMP)',prefix||'-new-contact',source_id,'Stale contact'),'23514');
  PERFORM pg_temp.expect_client_merge_failure(format('UPDATE "ClientContact" SET "clientId"=%L WHERE id=%L',source_id,contact_id),'23514');
  PERFORM pg_temp.expect_client_merge_failure(format('INSERT INTO "ClientLabelAssignment" ("clientId","labelId") VALUES (%L,%L)',source_id,label_id),'23514');
  PERFORM pg_temp.expect_client_merge_failure(format('UPDATE "ClientLabelAssignment" SET "clientId"=%L WHERE "clientId"=%L AND "labelId"=%L',source_id,retained_id,label_id),'23514');
  PERFORM pg_temp.expect_client_merge_failure(format('INSERT INTO "ClientEvent" (id,"clientId",title,"eventDate","createdByName","updatedAt") VALUES (%L,%L,%L,CURRENT_DATE,%L,CURRENT_TIMESTAMP)',prefix||'-new-event',source_id,'Stale event','Test'),'23514');
  PERFORM pg_temp.expect_client_merge_failure(format('UPDATE "ClientEvent" SET "clientId"=%L WHERE id=%L',source_id,event_id),'23514');
  PERFORM pg_temp.expect_client_merge_failure(format('INSERT INTO "Client" (id,name,"parentClientId","updatedAt") VALUES (%L,%L,%L,CURRENT_TIMESTAMP)',prefix||'-new-child','Stale child',source_id),'23514');
  PERFORM pg_temp.expect_client_merge_failure(format('UPDATE "Client" SET "parentClientId"=%L WHERE id=%L',source_id,child_id),'23514');

  -- Historical quote and cleanup updates are allowed; no storage objects move.
  UPDATE "Deal" SET "clientId"="clientId", notes='Normal historical edit' WHERE id=deal_id;
  UPDATE "ClientEvent" SET "clientId"="clientId", description='Normal history edit' WHERE id=event_id;
  IF (SELECT "clientName" FROM "Deal" WHERE id=deal_id) <> 'Original quote name' THEN
    RAISE EXCEPTION 'Merge rewrote the historical quote snapshot';
  END IF;
  IF (SELECT "storageKey" FROM "ClientEventReceipt" WHERE id=receipt_id) <> 'clients/' || source_id || '/receipt.pdf' THEN
    RAISE EXCEPTION 'Merge rewrote receipt storage key';
  END IF;
  UPDATE "ClientEventReceipt" SET status='DELETE_PENDING' WHERE id=receipt_id;
  DELETE FROM "ClientEventReceipt" WHERE id=receipt_id;
  DELETE FROM "ClientEvent" WHERE id=event_id;

  -- Explicit routing is internally consistent; legacy rows follow their client.
  IF (SELECT "xeroRoutingMode"::TEXT FROM "Deal" WHERE id=deal_id) <> 'FOLLOW_CLIENT' THEN
    RAISE EXCEPTION 'Unexpected routing default';
  END IF;
  PERFORM pg_temp.expect_client_merge_failure(format('UPDATE "Deal" SET "xeroRoutingMode"=%L WHERE id=%L','FIXED',deal_id),'23514');
  PERFORM pg_temp.expect_client_merge_failure(format('UPDATE "Deal" SET "xeroRoutingContactId"=%L WHERE id=%L','contact',deal_id),'23514');
  UPDATE "Deal" SET "xeroRoutingMode"='FIXED',"xeroRoutingContactId"='original-contact',"xeroRoutingConnectionKey"='original-connection' WHERE id=deal_id;
  PERFORM pg_temp.expect_client_merge_failure(format('UPDATE "Deal" SET "xeroRoutingConnectionKey"=%L WHERE id=%L',' ',deal_id),'23514');
  PERFORM pg_temp.expect_client_merge_failure(format('UPDATE "Deal" SET "xeroRoutingMode"=%L WHERE id=%L','UNMATCHED',deal_id),'23514');
  UPDATE "Deal" SET "xeroRoutingMode"='UNMATCHED',"xeroRoutingContactId"=NULL,"xeroRoutingConnectionKey"=NULL WHERE id=deal_id;

  -- Immutable audit and source uniqueness provide durable idempotency evidence.
  PERFORM pg_temp.expect_client_merge_failure(format('UPDATE "ClientMergeAudit" SET resolutions=%L::jsonb WHERE id=%L','{"changed":true}',audit_id),'23514');
  PERFORM pg_temp.expect_client_merge_failure(format('UPDATE "ClientMergeAudit" SET "actorUserId"=NULL WHERE id=%L',audit_id),'23514');
  PERFORM pg_temp.expect_client_merge_failure(format('DELETE FROM "ClientMergeAudit" WHERE id=%L',audit_id),'23514');
  PERFORM pg_temp.expect_client_merge_failure(format('INSERT INTO "ClientMergeAudit" SELECT %L,"sourceClientId","retainedClientId","actorUserId","createdAt","sourceSnapshot","retainedSnapshot",resolutions,"transferredRecords" FROM "ClientMergeAudit" WHERE id=%L',prefix||'-duplicate',audit_id),'23505');

  -- Merging a previous survivor keeps earlier immutable aliases and audits intact.
  UPDATE "Deal" SET "clientId"=third_id WHERE id=deal_id;
  UPDATE "ClientContact" SET "clientId"=third_id WHERE id=contact_id;
  UPDATE "ClientLabelAssignment" SET "clientId"=third_id WHERE "clientId"=retained_id;
  UPDATE "Client" SET "parentClientId"=third_id WHERE id=child_id;
  INSERT INTO "ClientMergeAudit" (id,"sourceClientId","retainedClientId","actorUserId","sourceSnapshot","retainedSnapshot",resolutions,"transferredRecords")
    VALUES (prefix||'-audit2',retained_id,third_id,user_id,'{}','{}','{}','{}');
  UPDATE "Client" SET "mergedIntoClientId"=third_id,"mergedAt"=CURRENT_TIMESTAMP,"mergedByUserId"=user_id WHERE id=retained_id;
  IF (SELECT "mergedIntoClientId" FROM "Client" WHERE id=source_id) <> retained_id THEN
    RAISE EXCEPTION 'Existing alias chain was rewritten';
  END IF;
  PERFORM pg_temp.expect_client_merge_failure(format('DELETE FROM "Client" WHERE id=%L',third_id),'23001,23503');

  -- Shared identity deletion nulls its links without deleting or editing evidence.
  DELETE FROM "User" WHERE id=user_id;
  IF EXISTS (SELECT 1 FROM "Client" WHERE id IN (source_id,retained_id) AND "mergedByUserId" IS NOT NULL)
    OR EXISTS (SELECT 1 FROM "ClientMergeAudit" WHERE id IN (audit_id,prefix||'-audit2') AND "actorUserId" IS NOT NULL) THEN
    RAISE EXCEPTION 'User deletion did not preserve nullable merge attribution';
  END IF;
  IF (SELECT count(*) FROM "ClientMergeAudit" WHERE id IN (audit_id,prefix||'-audit2')) <> 2 THEN
    RAISE EXCEPTION 'Merge evidence was removed';
  END IF;
  RAISE NOTICE 'Client merge schema and guard checks passed';
END $$;

ROLLBACK;
