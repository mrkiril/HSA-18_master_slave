# HSA-18-master_slave
Let’s setup a PostgreSQL database

For setting up a postgreSQL database with docker, you could go to their official docker hub page, check the various versions and configurations. 

I recommend to use docker-compose since it’s easier to manage. Here is a simple docker-compose file for running it.
```
version: '3.6'
services:
projector_postgres_master:
    container_name: projector_postgres_master
    image: postgres:13
    environment:
      POSTGRES_PASSWORD: mysecretpassword
      POSTGRES_USER: master
      POSTGRES_DB: hw18_projector
      POSTGRES_PORT: 5432
    ports:
      - 127.0.0.1:54320:5432
    volumes:
      - ./postgres/db-data-slave1:/tmp/postgresslave1
      - ./postgres/db-data-slave2:/tmp/postgresslave2
      - ./postgres/db-data-master:/var/lib/postgresql/data
      - ./postgres/docker_postgres_init.sh:/docker-entrypoint-initdb.d/docker_postgres_init.sh
    networks:
      - default
```

Let’s tune it for production.
Now the container should be running and you could access it easily and start using it, 
but this is not good enough for production. 

There are some configurations and performance tweaks which needs to be applied based on your hardware ! it’s not essential, but good to have it. 

You could get all the details you need from https://pgtune.leopard.in.ua website. 

Then you need to create a `postgresql.conf` file and add those lines. You should know that these are not all the required configurations for running postgres, these are just the performance tweaks. 
Now you wonder what are the other configurations? They have answered this question in their docker hub page, first run the command below to get the sample file and then add the configurations you got from `pgtune` website into it.

`$ docker run -i --rm postgres cat /usr/share/postgresql/postgresql.conf.sample > postgres_master.conf`

Let’s setup a PostgreSQL master database !
There are couple of more configurations needed for a master database, first we need to add some lines to `postgres_master.conf` for replication.
### Replication
```
wal_level = replica
hot_standby = on
max_wal_senders = 10
max_replication_slots = 10
hot_standby_feedback = on
```


Also we need to tell postgres to let our replication user connect to that database and trust it, I assume my replication user is called `replicator` . 
There is another configuration file called `pg_hba.conf` which handles the accesses to the database. 

Let’s create a custome `pg_hba_master.conf` with these lines.
```
# TYPE  DATABASE        USER            ADDRESS                 METHOD
# "local" is for Unix domain socket connections only
local   all             all                                     trust
# IPv4 local connections:
host    all             all             127.0.0.1/32            trust
# IPv6 local connections:
host    all             all             ::1/128                 trust
# Allow replication connections from localhost, by a user with the
# replication privilege.
local   replication     all                                     trust
host    replication     all             127.0.0.1/32            trust
host    replication     all             ::1/128                 trust
host    replication     replicator      0.0.0.0/0               trust

host all all all md5
```

## Let’s Get Ready For Slave !

We are almost there for setting up a replication, there are couple of steps which we need to take.
1. **Create the replicator user on master**
    
    `$ CREATE USER replicator WITH REPLICATION ENCRYPTED PASSWORD 'my_replicator_password';`

2. **Create the physical replication slot on master**
    
    `$ SELECT * FROM pg_create_physical_replication_slot('replication_slot_slave1');`

    To see that the physical replication slot has been created successfully, 
    you could run this query 
    
    `$ SELECT * FROM pg_replication_slots;` and you should see something like this.
    ```-[ RECORD 1 ]-------+------------------------
    slot_name           | replication_slot_slave1
    plugin              | 
    slot_type           | physical
    datoid              | 
    database            | 
    temporary           | f
    active              | f
    active_pid          | 
    xmin                | 
    catalog_xmin        | 
    restart_lsn         | 
    confirmed_flush_lsn |
    ```
    You could see, since we are not running any slave for this slot, it’s not active yet.

3. We need to get a backup from our master database and restore it for the slave. 
    The best way for doing this is to usepg_basebackup command. 
    **Here is the documentation for postgres version 13.**

    If you don’t want to read all the documentation to find out which flags you should use, 
    just copy the command below and we will go through the flags in this command. Every command for each replica.
    
    `$ pg_basebackup -D /tmp/postgresslave1 -S replication_slot_slave1 -X stream -P -U replicator -Fp -R`
    
    `$ pg_basebackup -D /tmp/postgresslave2 -S replication_slot_slave2 -X stream -P -U replicator -Fp -R`
    
    After running this command, you could see there is `postgresslave1` and `postgresslave2` directory in the /tmp/ directory.


## Let’s Setup the Slave !
Now we need to setup another container for the slave, we are going to use this logg command

```
docker run --rm --name $(POSTGRES_SLAVE1) -p 127.0.0.1:54321:5432 -e POSTGRES_USER=master -e POSTGRES_PASSWORD=mysecretpassword -v "$(PWD_DIR)/postgres/db-data-slave1":$(PGDATA) --network=$(NETWORK) -d postgres:13
```
and for second replica
```
docker run --rm --name $(POSTGRES_SLAVE2) -p 127.0.0.1:54322:5432 -e POSTGRES_USER=master -e POSTGRES_PASSWORD=mysecretpassword -v "$(PWD_DIR)/postgres/db-data-slave2":$(PGDATA) --network=$(NETWORK) -d postgres:13
```
This give us probability to UP replica many times.
Let’s see what’s the final step before firing up the slave container.

### The Trick !
Since you have run the pg_basebackup inside a docker container and also asked for recovery config file, it has created a `postgresql.auto.conf` file inside the data-slave directory. 

In this file you should see something like this.
```
# Do not edit this file manually!
# It will be overwritten by the ALTER SYSTEM command.
primary_conninfo = 'user=replicator passfile=''/root/.pgpass'' channel_binding=prefer port=5432 sslmode=prefer sslcompression=0 ssl_min_protocol_version=TLSv1.2 gssencmode=prefer krbsrvname=postgres target_session_attrs=any'
primary_slot_name = 'replication_slot_proxy_slave1'
```

Now you could see the `primary_conninfo` which tells the **slave how should connect to the master**, 
but these configurations are not right. 

Let’s change the `primy_conninfo` and pass the correct information for connecting to master.
```
primary_conninfo = 'host=projector_postgres_master port=5432 user=replicator password=my_replicator_password'
primary_slot_name = 'replication_slot_slave1'
restore_command = 'cp /var/lib/postgresql/data/pg_wal/%f "%p"'
```
Look, we use `projector_postgres_master` as host name from **docker-compose.yml**

Also we need to add a restore command which tells slave how to deal with this backup, so add this line as well.
`restore_command = 'cp /var/lib/postgresql/data/pg_wal/%f "%p"'`

Now it’s finished, you could fire up the slave container as well.
You could go to slave and run the `$ SELECT * FROM pg_replication_slots;` query again.
```
-[ RECORD 1 ]-------+-----------------------------
slot_name           | replication_slot_slave1
plugin              | 
slot_type           | physical
datoid              | 
database            | 
temporary           | f
active              | t
active_pid          | 1332
xmin                | 20800
catalog_xmin        | 
restart_lsn         | 0/105AB6F8
confirmed_flush_lsn | 
wal_status          | reserved
safe_wal_size       |
```
Now you could see the slot is activated. You could also test the replication by creating a dummy table on master and check it on slave

P.S.

All this commands write in `Makefile`

### To run master node just write `make run`:
1. This run master **db**
2. Copied `postgres.conf` to /var/lib/postgres/data
3. Copied `pg_hba.conf` to /var/lib/postgres/data
4. Create `pg_basebackup` for **first** and **second** replica

### To run slave node just write `make run_slave`:
1. Copied `postgresql.auto.conf` to /var/lib/postgres/data for **First replica**
2. Copied `postgresql.auto.conf` to /var/lib/postgres/data for **Second replica**
3. This run two slave db

##Have fun!
