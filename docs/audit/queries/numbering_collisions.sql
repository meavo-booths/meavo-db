SELECT count(*) AS planning_ids_also_inventory_serials FROM "FactoryPlanningBooth" p JOIN "InventoryUnit" u ON u."serialNumber" = p."boothUniqueId"::int WHERE p."boothUniqueId" ~ '^[0-9]+$'
