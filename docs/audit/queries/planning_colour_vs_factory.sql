SELECT pb."colorCode", count(*) AS booths, (c.code IS NOT NULL) AS in_factory_color FROM "FactoryPlanningBooth" pb LEFT JOIN "FactoryColor" c ON c.code = pb."colorCode" GROUP BY 1,3 ORDER BY 2 DESC
