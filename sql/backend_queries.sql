 SELECT pg_stat_get_backend_pid(s.backendid) AS pid, 
    pg_stat_get_backend_client_addr(s.backendid) AS client_addr, 
    pg_stat_get_backend_client_port(s.backendid) AS client_port, 
    pg_stat_get_backend_start(s.backendid) AS session_start_time, 
    pg_stat_get_backend_xact_start(s.backendid) AS transaction_start_time, 
    now() - pg_stat_get_backend_xact_start(s.backendid) AS transaction_timing, 
    pg_stat_get_backend_waiting(s.backendid) AS is_waiting, 
    "left"(regexp_replace(regexp_replace(pg_stat_get_backend_activity(s.backendid), '[
 ]+'::text, ' '::text, 'ig'::text), '^ +| +$'::text, ''::text, 'ig'::text), 20480) AS query
   FROM ( SELECT pg_stat_get_backend_idset() AS backendid) s
  WHERE regexp_replace(regexp_replace(pg_stat_get_backend_activity(s.backendid), '[
 ]+'::text, ' '::text, 'ig'::text), '^ +| +$'::text, ''::text, 'ig'::text) <> ALL (ARRAY['select 1'::text, 'SELECT $1;'::text, 'BEGIN'::text, 'COMMIT'::text, 'ROLLBACK'::text, 'DISCARD ALL;'::text, 'DEALLOCATE ALL;'::text, 'SHOW TRANSACTION ISOLATION LEVEL'::text, 'SET SESSION CHARACTERISTICS AS TRANSACTION READ WRITE'::text])
  ORDER BY now() - pg_stat_get_backend_xact_start(s.backendid) DESC;
