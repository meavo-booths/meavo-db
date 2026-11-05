SELECT stats_reset, now() AS checked_at FROM pg_stat_database WHERE datname = current_database()
