 SELECT av.nspname, av.relname, av.n_tup_ins, av.n_tup_upd, av.n_tup_del, 
    av.hot_update_ratio, av.n_live_tup, av.n_dead_tup, av.reltuples, 
    av.av_threshold, av.last_vacuum, av.last_analyze, 
    av.n_dead_tup::double precision > av.av_threshold AS av_needed, 
        CASE
            WHEN av.reltuples > 0::double precision THEN round((100.0 * av.n_dead_tup::numeric)::double precision / av.reltuples)
            ELSE 0::double precision
        END AS pct_dead
   FROM ( SELECT n.nspname, c.relname, 
            pg_stat_get_tuples_inserted(c.oid) AS n_tup_ins, 
            pg_stat_get_tuples_updated(c.oid) AS n_tup_upd, 
            pg_stat_get_tuples_deleted(c.oid) AS n_tup_del, 
                CASE
                    WHEN pg_stat_get_tuples_updated(c.oid) > 0 THEN pg_stat_get_tuples_hot_updated(c.oid)::real / pg_stat_get_tuples_updated(c.oid)::double precision
                    ELSE 0::double precision
                END AS hot_update_ratio, 
            pg_stat_get_live_tuples(c.oid) AS n_live_tup, 
            pg_stat_get_dead_tuples(c.oid) AS n_dead_tup, c.reltuples, 
            round(current_setting('autovacuum_vacuum_threshold'::text)::integer::double precision + current_setting('autovacuum_vacuum_scale_factor'::text)::numeric::double precision * c.reltuples) AS av_threshold, 
            date_trunc('minute'::text, GREATEST(pg_stat_get_last_vacuum_time(c.oid), pg_stat_get_last_autovacuum_time(c.oid))) AS last_vacuum, 
            date_trunc('minute'::text, GREATEST(pg_stat_get_last_analyze_time(c.oid), pg_stat_get_last_analyze_time(c.oid))) AS last_analyze
           FROM pg_class c
      LEFT JOIN pg_namespace n ON n.oid = c.relnamespace
     WHERE (c.relkind = ANY (ARRAY['r'::"char", 't'::"char"])) AND n.nspname !~ '^pg_toast'::text) av
  ORDER BY av.n_dead_tup::double precision > av.av_threshold DESC, av.n_dead_tup DESC;
