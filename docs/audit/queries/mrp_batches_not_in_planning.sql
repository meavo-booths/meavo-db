SELECT name, "masterSheetRowKey", status::text AS status FROM "MrpManufacturingBatch" m WHERE NOT EXISTS (SELECT 1 FROM "FactoryPlanningBatch" f WHERE f."batchCode" = m.name) ORDER BY name
