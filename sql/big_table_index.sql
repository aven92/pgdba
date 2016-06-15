WITH big_relation AS (
	SELECT
		nspname AS schemaname,
		relname as relationname,
		pg_size_pretty(pg_total_relation_size(c.oid)) as totalsize
	FROM
		pg_class c
	LEFT JOIN
		pg_namespace n
	ON (n.oid = c.relnamespace)
	WHERE
		nspname NOT IN ('pg_catalog', 'information_schema')
		AND c.relkind <> 'i' 
		AND nspname !~ '^pg_toast'
	ORDER BY pg_total_relation_size(c.oid) DESC
), 
big_table AS (
	SELECT
		nspname AS schemaname,
		relname AS tablename,
		pg_size_pretty(pg_table_size(c.oid)) as tablesize
	FROM
		pg_class c
	LEFT JOIN
		pg_namespace n
	ON (n.oid = c.relnamespace)
	WHERE
		nspname NOT IN ('pg_catalog', 'information_schema')
		AND c.relkind <> 'i' 
		AND nspname !~ '^pg_toast'
	ORDER BY pg_total_relation_size(c.oid) DESC
), 
big_index AS (
	SELECT
		schemaname,
		tablename,
		indexname,
		pg_size_pretty(pg_table_size((schemaname||'.'||indexname)::text)) AS indexsize
	FROM
		pg_indexes
	WHERE
		schemaname NOT IN ('pg_catalog', 'information_schema')
		AND schemaname !~ '^pg_toast'
	ORDER BY pg_table_size((schemaname||'.'||indexname)::text) DESC
)
SELECT *
FROM big_table
limit 10;
