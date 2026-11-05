SELECT date_part('year', b."createdAt")::int AS year, count(*) FROM "BoothUnit" b GROUP BY 1 ORDER BY 1
