FROM postgres

COPY ./migrations/sqls/20250831024502-init-up.sql /docker-entrypoint-initdb.d/