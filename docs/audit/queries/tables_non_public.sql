SELECT schemaname, relname, pg_total_relation_size(relid) AS bytes FROM pg_stat_user_tables WHERE schemaname <> 'public' ORDER BY 1,2
