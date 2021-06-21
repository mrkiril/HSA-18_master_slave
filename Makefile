MAIN_SERVICE = king_size_service_18
POSTGRES_MASTER = projector_postgres_master
POSTGRES_SLAVE1 = projector_postgres_slave1
POSTGRES_SLAVE2 = projector_postgres_slave2

DB_NAME = hw18_projector
PGDATA = /var/lib/postgresql/data
POSTGRES_SLAVE_INNER_PATH1 = /tmp/postgresslave1
POSTGRES_SLAVE_INNER_PATH2 = /tmp/postgresslave2


NETWORK = hw_18_master_slave_3_default
PWD_DIR = `pwd`

ps:
	docker-compose ps

up:
	docker-compose up -d
	docker-compose ps

down:
	docker stop $(POSTGRES_SLAVE1) $(POSTGRES_SLAVE2) || true
	docker-compose down

open_dir:
	sudo chmod -R 777 ./postgres/postgresslave
	sudo chmod -R 777 ./postgres/db-data-master
	sudo chmod -R 777 ./postgres/db-data-slave1
	sudo chmod -R 777 ./postgres/db-data-slave2

clear_dir: open_dir
	sudo rm -rf ./postgres/db-data-master/*
	sudo rm -rf ./postgres/db-data-slave1/*
	sudo rm -rf ./postgres/db-data-slave2/*
	sudo rm -rf ./postgres/db-data-postgresslave/*

run: down
	make open_dir
	make clear_dir
	docker-compose build --parallel --no-cache $(POSTGRES_MASTER) > /dev/null
	docker-compose up -d > /dev/null
	make down
	make init_master
	make master_backup
	make ps

run_slave: init_slave
	docker run --rm --name $(POSTGRES_SLAVE1) -p 127.0.0.1:54321:5432 -e POSTGRES_USER=master -e POSTGRES_PASSWORD=mysecretpassword -v "$(PWD_DIR)/postgres/db-data-slave1":$(PGDATA) --network=$(NETWORK) -d postgres:13
	docker run --rm --name $(POSTGRES_SLAVE2) -p 127.0.0.1:54322:5432 -e POSTGRES_USER=master -e POSTGRES_PASSWORD=mysecretpassword -v "$(PWD_DIR)/postgres/db-data-slave2":$(PGDATA) --network=$(NETWORK) -d postgres:13

up_slave:
	docker run --rm --name $(POSTGRES_SLAVE1) -p 127.0.0.1:54321:5432 -e POSTGRES_USER=master -e POSTGRES_PASSWORD=mysecretpassword -v "$(PWD_DIR)/postgres/db-data-slave1":$(PGDATA) --network=$(NETWORK) -d postgres:13
	docker run --rm --name $(POSTGRES_SLAVE2) -p 127.0.0.1:54322:5432 -e POSTGRES_USER=master -e POSTGRES_PASSWORD=mysecretpassword -v "$(PWD_DIR)/postgres/db-data-slave2":$(PGDATA) --network=$(NETWORK) -d postgres:13


init_master: open_dir
	echo ""
	echo "# = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =" > /dev/null
	echo "# = = = = = = = = = = = = = =  I N I T   M A S T E R  = = = = = = = = = = = = = = = = = =" > /dev/null
	echo "# = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =" > /dev/null
	cp ./postgres/postgres_master.conf ./postgres/db-data-master/postgres.conf
	cp ./postgres/pg_hba_master.conf ./postgres/db-data-master/pg_hba.conf


init_slave: open_dir
	cp ./postgres/postgres_slave1.auto.conf ./postgres/db-data-slave1/postgresql.auto.conf
	cp ./postgres/postgres_slave2.auto.conf ./postgres/db-data-slave2/postgresql.auto.conf


master_backup: up
	echo "# = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =" > /dev/null
	echo "# = = = = = = = = = = = = =  M A S T E R  B A C K U P = = = = = = = = = = = = = = = = = =" > /dev/null
	echo "# = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =" > /dev/null
	docker-compose exec $(POSTGRES_MASTER) bash -c "ls $(POSTGRES_SLAVE_INNER_PATH1) && rm -rf $(POSTGRES_SLAVE_INNER_PATH1)/*"
	docker-compose exec $(POSTGRES_MASTER) bash -c "ls $(POSTGRES_SLAVE_INNER_PATH2) && rm -rf $(POSTGRES_SLAVE_INNER_PATH2)/*"
	docker-compose exec $(POSTGRES_MASTER) pg_basebackup -D $(POSTGRES_SLAVE_INNER_PATH1) -S replication_slot_slave1 -X stream -P -U replicator -Fp -R
	docker-compose exec $(POSTGRES_MASTER) pg_basebackup -D $(POSTGRES_SLAVE_INNER_PATH2) -S replication_slot_slave2 -X stream -P -U replicator -Fp -R
	#make copy_backup


rebuild:
	docker-compose build --parallel
	docker-compose up -d
	docker-compose ps

restart:
	docker-compose restart $(MAIN_SERVICE) $(POSTGRES_MASTER) $(POSTGRES_SLAVE1) $(POSTGRES_SLAVE2)
	docker-compose ps

bash:
	docker-compose exec $(MAIN_SERVICE) bash

statm:
	docker-compose exec $(MAIN_SERVICE) bash -c "printf '%(%m-%d %H:%M:%S)T    ' && cat /proc/1/statm"

pidstat:
	docker-compose exec $(MAIN_SERVICE) bash -c "pidstat -p 1 -r 10 100"

psql:
	docker-compose exec db_postgres psql -U postgres -d hw18_projector

format:
	isort .
	python3 -m black -l 100 .
	python3 -m flake8 -v
