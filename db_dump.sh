#!/bin/bash

# 
# Make a dump of database tables
# 

function get_mysql_databases ()
{
	# 
	# Get all mysql databases except default administrative ones.
	# Make sure ~/.my.conf is set to something like
	#   [client]
	#   user = backup
	#   password = abc123
	# Sets $mysql_databases
	# 
	mysql_databases=""
	if [ ! $(which mysql) ]; then printf "mysql not found\n"; return; fi
	if [ -n "$(echo 'exit' | mysql 2>&1)" ]; then printf "failed to connect to mysql server; make sure you have ~/.my.conf set up correctly\n"; return; fi
	mysql_databases="$(echo "show databases;" | mysql | grep -v -e '_schema$' | grep -Ev 'Database|extra_options|mysql')"
	printf "found MySQL tables: %s\n" "$(echo $mysql_databases)"
}

function get_postgres_databases ()
{
	# 
	# Get all postgres databases except default administrative ones.
	# Make sure ~/.pgpass is set to something like
	#   # hostname:port:database:username:password
	#   *:*:*:backup:abc123
	# Sets $postgres_databases
	# 
	postgres_databases=""
	if [ ! $(which psql) ]; then printf "mysql not found\n"; return; fi
	if [ -n "$(echo "\q" | psql postgres 2>&1)" ]; then printf "failed to connect to postgres server; make sure you have ~/.pgpass set up correctly\n"; return; fi
	postgres_databases="$(psql postgres -l | head -n -2 | tail -n +4 | cut -d '|' -f 1 | grep -v template | grep -v postgres)"
	printf "found postgres tables: %s\n" "$(echo $postgres_databases)"
}

function do_mysql_dump()
{
	# 
	# Dump a mysql database to an .sql file.
	# Config file & tests are assumed to have been checked by get_mysql_databases.
	# Argument: $1 (arg) or $dbname (var)
	# Sets $dumppath
	# 
	if [ -n "$1" ]; then dbname="$1"; fi
	if [ -z "$dbname" ]; then printf "dbname variable not set, needed by do_mysql_dump\n"; return; fi
	dumppath="my.$dbname.sql"
	mysqldump --databases "$db" | head -n -1 > "$dumppath"
	if [ ! -s "$dumppath" ]
	then
		printf "failed to create dump for MySQL database %s at %s\n" "$dbname" "$dumppath"
		exit 1
	fi
	printf "succesfully dumped MySQL database %s to %s\n" "$dbname" "$dumppath"
}

function do_postgres_dump()
{
	# 
	# Dump a postgres database to an .sql file.
	# Config file & tests are assumed to have been checked by get_postgres_databases.
	# Argument: $1 (arg) or $dbname (var)
	# Sets $dumppath
	# 
	if [ -n "$1" ]; then dbname="$1"; fi
	if [ -z "$dbname" ]; then printf "dbname variable not set, needed by do_postgres_dump\n"; return; fi
	dumppath="pg.$dbname.sql"
	pg_dump "$db" -f "$dumppath"
	if [ ! -s "$dumppath" ]
	then
		printf "failed to create dump for postgres database %s at %s\n" "$dbname" "$dumppath"
		exit 1
	fi
	printf "succesfully dumped postgres database %s to %s\n" "$dbname" "$dumppath"
}

function handle_raw_db_dump ()
{
	# 
	# Handle a newly dumped .sql file:
	# 1. gzip them (without timestamps)
	# 2. compare to the last one
	# 3. delete if it's identical
	# Argument: $1 (arg) or $filepath (var)
	# Input should not contain a timestamp, but output will.
	# 
	if [ -n "$1" ]; then filepath="$1"; fi
	if [ -z "$filepath" ]; then printf "filepath variable not set, needed by handle_raw_db_dump\n"; return; fi
	timestamp=$(date +"%Y-%m-%d-%H-%M")
	basename=${filepath%.*}
	newname="$basename.$timestamp.sql.gz"
	printf "new compressed file %s... " "$newname"
	last=$(find . -maxdepth 1 -type f -name "$basename.*.sql.gz" -printf '%Ts\t%p\n' | sort -nr | cut -f2 | head -n 1)
	gzip -n < "$filepath" > "$newname"
	printf "created!\n"
	if [ -e "$last" ]
	then
		printf "  comparing to previous dump %s... " "$last"
		if [ "${newname##*/}" = "${last##*/}" ]
		then
			printf "same file\n"
		
		elif cmp --silent "$newname" "$last"
		then
			printf "identical! not storing new dump\n"
			rm -f "$newname" "unchanged.$newname"
			ln -s "$last" "unchanged.$newname"
		else
			printf "different! keeping new dump\n"
		fi
	else
		printf "this seems to be the first dump\n"
	fi
	rm -f "$filepath"
}

function dump_all_mysql ()
{
	# 
	# Using the above functions, dump all MySQL databases that have changed.
	# 
	get_mysql_databases
	for db in $mysql_databases
	do
		do_mysql_dump "$db"
		handle_raw_db_dump "$dumppath"
	done
	printf "MySQL done\n"
}

function dump_all_postgres ()
{
	# 
	# Using the above functions, dump all postgres databases that have changed.
	# 
	get_postgres_databases
	for db in $postgres_databases
	do
		do_postgres_dump "$db"
		handle_raw_db_dump "$dumppath"
	done
	printf "postgres done\n"
}

function dump_all_dbs ()
{
	# 
	# Dump all MySQL and postgres databases.
	# 
	dump_all_mysql
	dump_all_postgres
}

dump_all_postgres

function make_db_dumps ()
{
	timestamp=$(date +"%Y-%m-%d-%H-%M")
	
	if [ $(which mysql) ]
	then
		printf "MySQL: found at %s\n" $(which mysql)
		databases=
		echo "found databases: $databases"
	else
		printf "MySQL: not found; skip\n"
	fi
	if [ $(which psql) ]
	then
		printf "postgres: found at %s\n" $(which psql)
	else
		printf "postgres: not found; skip\n"
	fi
	exit 0
	
	for db in $mysql_databases
	do
		fname="${db}_$timestamp.db.sql"
		echo "$db -> $fname"
	
		# find previous backups
		last=$(find . -maxdepth 1 -type f -name "${db}_*.sql" -printf '%Ts\t%p\n' | sort -nr | cut -f2 | head -n 1)
	
		# dump the sql to a file, but strip the timestamp, so that it will be equal of no data changed
		echo mysqldump --user=$user --password=$password --database $db | head -n -1 > "$fname"
		
		if [ -e "$last" ]
		then
			echo "compare $fname to $last"
			if cmp --silent "$fname" "$last"
			then
				rm -f "$fname"
				touch "${db}_$timestamp.db.unchanged"
			fi
		fi
	done
}


#echo $(psql postgres -l | head -n -2 | tail -n +4 | cut -d '|' -f 1 | grep -v template | grep -v postgres)

# pg_dump aqua -f /tmp/tmp
