SELECT
	wait.pid,
	wait.query as q,
	wait.locktype,
	granted.pid as waitfor_pid,
	granted.relation,
	granted.datname || '.' || d.nspname || '.' || c.relname as name,
	granted.transactionid,
	granted.virtualxid,
	granted.usename,
	granted.client_addr,
	granted.query
FROM
	(SELECT
		a.query,
		b.pid,
		b.relation,
		b.transactionid,
		b.page,
		b.tuple,
		b.locktype,
		b.virtualxid
	FROM
		pg_stat_activity a,
		pg_locks b
	WHERE
		a.waiting = 't'
		AND a.pid = b.pid
		AND granted = 'f'
) wait
INNER JOIN
	(SELECT
		b.pid,
		b.usename,
		b.client_addr,
		b.backend_start,
		b.query_start,
		b.waiting,
		b.query,
		b.datname,
		a.relation,
		a.transactionid,
		a.page,
		a.tuple,
		a.locktype,
		a.virtualxid
	FROM
		pg_locks a,
		pg_stat_activity b
	WHERE
		a.pid = b.pid
		AND a.granted = 't'
	) granted
ON (
	( wait.locktype = 'transactionid'
	AND granted.locktype = 'transactionid'
	AND wait.transactionid = granted.transactionid )
	OR
	( wait.locktype = 'relation'
	AND granted.locktype = 'relation'
	AND wait.relation = granted.relation
	)
	OR
	( wait.locktype = 'virtualxid'
	AND granted.locktype = 'virtualxid'
	AND wait.virtualxid = granted.virtualxid )
	OR
	( wait.locktype = 'tuple'
	AND granted.locktype = 'tuple'
	AND wait.relation = granted.relation
	AND wait.page = granted.page
	AND wait.tuple = granted.tuple )
	)
LEFT JOIN
	pg_class c
ON ( c.relfilenode = wait.relation )
LEFT JOIN
	pg_namespace d
ON ( c.relnamespace = d.oid )
