#!/usr/bin/env bash


psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
		CREATE USER replicator WITH REPLICATION ENCRYPTED PASSWORD 'my_replicator_password';
		CREATE TABLE books (
    code        char(5) CONSTRAINT firstkey PRIMARY KEY,
    title       text NOT NULL,
    category    text NOT NULL,
    created_date   date,
    len         smallint
);
EOSQL
echo "replicator user created"
echo "Table books created"


psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
		SELECT * FROM pg_create_physical_replication_slot('replication_slot_slave1');
		SELECT * FROM pg_create_physical_replication_slot('replication_slot_slave2');
EOSQL
echo "Create replication slots created"
