SELECT "boothIdText", count(*) FROM "MrpBatchUnit" WHERE substring("boothIdText" from '([0-9]{5})') IS NULL GROUP BY 1 ORDER BY 2 DESC LIMIT 15
