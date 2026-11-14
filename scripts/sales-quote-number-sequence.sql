-- Sales: "SalesQuoteNumberSeq" numbers Sales quotes. Every new quote takes
-- nextval('"SalesQuoteNumberSeq"') (meavo-sales src/lib/quote-number.ts) and stores it as
-- Deal.quoteNumber: MQ-00001, MQ-00002, ... A variation adds a letter (MQ-00123A) and
-- takes no number. It is the only standalone sequence in the shared database, and Prisma
-- cannot declare one. Until 0.112.0 only the Sales repository created it (prisma/seed.ts
-- and the old prisma/sql/sales_tool.sql); from this script on meavo-db owns it.
--
-- Additive, transactional and idempotent. Where the sequence exists (production and
-- staging) the script does nothing at all: no setval, no RESTART, no ALTER SEQUENCE, so
-- the next quote number is untouched. Where it is missing the script creates it exactly as
-- production has it (bigint, from 1 by 1, no cycle) and, only then, moves the new
-- sequence past the highest MQ- number "Deal" already holds, so a recreated sequence can
-- never hand out a quote number that is already taken (Deal.quoteNumber is unique).
-- Apply: scripts/apply-sql.sh staging scripts/sales-quote-number-sequence.sql --env-file <staging env>

BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';

DO $$
DECLARE
  highest BIGINT;
BEGIN
  -- Exists: leave the sequence and its value alone.
  IF to_regclass('public."SalesQuoteNumberSeq"') IS NOT NULL THEN
    RETURN;
  END IF;

  CREATE SEQUENCE "SalesQuoteNumberSeq"
    AS BIGINT START WITH 1 INCREMENT BY 1 MINVALUE 1 NO MAXVALUE CACHE 1 NO CYCLE;

  -- Just created, in this transaction: continue after the quote numbers already issued.
  IF to_regclass('public."Deal"') IS NOT NULL THEN
    SELECT max(substring("quoteNumber" FROM '^MQ-([0-9]{1,15})[A-Za-z]?$')::BIGINT)
      INTO highest
      FROM "Deal";
    IF highest IS NOT NULL THEN
      PERFORM setval('"SalesQuoteNumberSeq"', highest, true);
    END IF;
  END IF;
END $$;

COMMIT;
