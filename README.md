# PostgreSQL DBA maintenance work note

## pg_backup.sh

1.create dba_ops database with supueruser
```
postgres=# create database dba_ops;
postgres=# \c dba_ops
```
2.Create a function that extracts all from pg_stat_replication:
```
dba_ops=# create or replace function pg_stat_repl() returns setof pg_catalog.pg_stat_replication as $$begin return query(select * from pg_catalog.pg_stat_replication); end$$ language plpgsql security definer;
```
3.Create a view that users this function to get data in it:
```
dba_ops=# create view public.pg_stat_repl as select * from pg_stat_repl();
```
4.Grant select on this view to your unprivileged user, sat 'db_backup':
```
dba_ops=# grant select on public.pg_stat_repl to db_backup;
```
