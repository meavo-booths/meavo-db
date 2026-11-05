SELECT "modelCode", count(*) AS booths, count(*) FILTER (WHERE "modelCode" IS NULL) AS no_model FROM "FactoryPlanningBooth" GROUP BY 1 ORDER BY 2 DESC
