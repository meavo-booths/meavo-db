SELECT schemaname, count(*) AS tables, sum(pg_total_relation_size(relid)) AS bytes FROM pg_stat_user_tables GROUP BY 1 ORDER BY 1
