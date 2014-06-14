DELETE FROM planet_osm_ways AS w WHERE 0 = (SELECT COUNT(1) FROM planet_osm_nodes AS n WHERE n.id = ANY(w.nodes));
DELETE FROM planet_osm_rels AS r WHERE
  0=(SELECT COUNT(1) FROM planet_osm_nodes AS n WHERE n.id = ANY(r.parts))
AND
  0=(SELECT COUNT(1) FROM planet_osm_ways AS w WHERE w.id = ANY(r.parts));
REINDEX TABLE planet_osm_ways;
REINDEX TABLE planet_osm_rels;
VACUUM FULL;
