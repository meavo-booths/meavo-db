SELECT finish::text AS finish, count(*) AS line_items, count(DISTINCT "finishDetails") AS distinct_details FROM "QuoteLineItem" GROUP BY 1 ORDER BY 2 DESC
