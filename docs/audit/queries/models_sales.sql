SELECT "boothFamily", count(*) AS products, string_agg(name || ' [' || coalesce(version,'') || ']', ', ' ORDER BY name) AS names FROM "Product" WHERE kind = 'BOOTH' GROUP BY 1 ORDER BY 1
