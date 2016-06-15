WITH active_query AS (
	SELECT pid, waiting,
		client_addr, application_name,
		datname, usename, state,
		now() - query_start AS runtime,
		regexp_replace(query, E'[\t\n\r ]+', ' ', 'ig') AS query
	FROM pg_stat_activity
	WHERE
		pid <> pg_backend_pid()
		AND state = 'active'
),
idle_query AS (
	SELECT pid, waiting,
		client_addr, application_name,
		datname, usename, state,
		now() - state_change AS idle_time,
		regexp_replace(query, E'[\t\n\r ]+', ' ', 'ig') AS query
	FROM pg_stat_activity
	WHERE
		pid <> pg_backend_pid()
		AND state <> 'active'
),
long_time_query AS (
	SELECT calls,
	(total_time / 1000 / 60) AS total_minutes,
	(total_time/calls) AS average_time,
	regexp_replace(query, E'[\n\r\t ]+', ' ', 'ig') AS query
	FROM pg_stat_statements
)
SELECT *
FROM active_query
ORDER BY runtime DESC
LIMIT 10;
