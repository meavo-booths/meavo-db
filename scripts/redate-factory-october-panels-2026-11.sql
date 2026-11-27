-- Data fix, no schema change: move the October 2026 panels that were entered on 4 November
-- back to October, so the Factory month credits count them in the month they were made.
-- Apply: scripts/apply-sql.sh <staging|production> scripts/redate-factory-october-panels-2026-11.sql ...
--
-- On 4 November 2026 between 12:15 and 14:04 (Sofia), final-assembly panels of four October
-- batches were written by a non-kiosk path (a График correction "admin-adjust:" or a packing
-- sheet sync "sheet-progress:" / "sheet:"). Boyan checked them on 27 November 2026: they were
-- made in October. The Factory TV counts records by "recordedAt", so they inflate November.
--
--   AB190  47 panels (all ASM-2 and ASM-3 panels; 13 more were tapped in October)
--   AB191  48 panels (all ASM-1, ASM-2 and ASM-3 panels; 12 more were tapped in October)
--   AB193  32 panels (Дъно, Гръб)
--   AB194  21 panels (Гръб, 1 Врата)
--
-- AB195's 16 columns from the same session were November work and are not touched.
--
-- Each matching record's "recordedAt" moves back exactly 5 days, to Friday 30 October 2026 at
-- the same Sofia time (both dates are EET, UTC+2). "createdAt" keeps 4 November as the audit
-- trail. Nothing else changes. AB190 and AB191 have no other final-assembly record in
-- November, so both batches then count as finished in October. The counts were read on the
-- staging copy on 27 November 2026 (148 panels, 30.68 credits); 0.128.1 expected 30/30/32/20
-- because the ASM-2 entries were missing from the event history it was based on.
--
-- Guard: per batch, the panels found in the 4 November window must equal the numbers above;
-- any other number aborts the whole transaction. A batch with nothing left in the window is
-- skipped, so the script is a no-op on a second run and on databases without these rows
-- (staging copies, the CI replay).

BEGIN;

DO $$
DECLARE
  b record;
  found_rows int;
  found_panels int;
  moved int;
BEGIN
  FOR b IN
    SELECT * FROM (VALUES
      ('AB190', 47),
      ('AB191', 48),
      ('AB193', 32),
      ('AB194', 21)
    ) AS t(code, panels)
  LOOP
    SELECT count(*), coalesce(sum(e."qtyGood"), 0)
      INTO found_rows, found_panels
      FROM "FactoryProductionEvent" e
      JOIN "FactoryProductionBatch" pb ON pb."id" = e."batchId"
      JOIN "FactoryStation" s ON s."id" = e."stationId"
     WHERE pb."batchCode" = b.code
       AND e."processStep" IN ('single', 'assembly')
       AND s."code" <> 'ASM-4'
       AND (e."clientEventId" LIKE 'admin-adjust:%'
            OR e."clientEventId" LIKE 'sheet-progress:%'
            OR e."clientEventId" LIKE 'sheet:%')
       -- 4 Nov 2026 12:00-14:30 Sofia (recordedAt is stored in UTC).
       AND e."recordedAt" >= TIMESTAMP '2026-11-04 10:00:00'
       AND e."recordedAt" <  TIMESTAMP '2026-11-04 12:30:00';

    IF found_rows = 0 THEN
      RAISE NOTICE '% nothing in the 4 November window (already moved, or not on this database)', b.code;
      CONTINUE;
    END IF;
    IF found_panels <> b.panels THEN
      RAISE EXCEPTION '% has % panels in % records in the 4 November window, expected %; nothing changed',
        b.code, found_panels, found_rows, b.panels;
    END IF;

    UPDATE "FactoryProductionEvent" e
       SET "recordedAt" = e."recordedAt" - INTERVAL '5 days'
      FROM "FactoryProductionBatch" pb, "FactoryStation" s
     WHERE pb."id" = e."batchId"
       AND s."id" = e."stationId"
       AND pb."batchCode" = b.code
       AND e."processStep" IN ('single', 'assembly')
       AND s."code" <> 'ASM-4'
       AND (e."clientEventId" LIKE 'admin-adjust:%'
            OR e."clientEventId" LIKE 'sheet-progress:%'
            OR e."clientEventId" LIKE 'sheet:%')
       AND e."recordedAt" >= TIMESTAMP '2026-11-04 10:00:00'
       AND e."recordedAt" <  TIMESTAMP '2026-11-04 12:30:00';
    GET DIAGNOSTICS moved = ROW_COUNT;
    IF moved <> found_rows THEN
      RAISE EXCEPTION '% moved % records, expected %; nothing changed', b.code, moved, found_rows;
    END IF;
    RAISE NOTICE '% moved % records (% panels) to 30 October', b.code, moved, found_panels;
  END LOOP;
END $$;

COMMIT;
