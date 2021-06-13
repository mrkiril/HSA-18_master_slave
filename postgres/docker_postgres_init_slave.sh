#!/usr/bin/env bash


psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
		CREATE TABLE books (
    code        char(5) CONSTRAINT firstkey PRIMARY KEY,
    title       text NOT NULL,
    category    text NOT NULL,
    created_date   date,
    len         smallint
);
EOSQL
echo "Table books created"
echo "Replication user created"