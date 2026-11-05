SELECT m.name AS mrp_name, f.code AS factory_code, f."nameBg" FROM "MrpBoothModel" m FULL OUTER JOIN "FactoryBoothModel" f ON lower(f."nameBg") = lower(m.name) ORDER BY 1
