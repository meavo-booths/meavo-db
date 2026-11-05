SELECT pg_database_size(current_database()) AS database_bytes, (SELECT sum(pg_total_relation_size(relid)) FROM pg_stat_user_tables) AS user_tables_bytes, version() AS pg_version
