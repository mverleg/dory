#!/bin/bash

#
# Make a dump of database tables
#

source inc_utils.sh

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
	if [ ! $(which mysql) ]; then log_failure "mysql not found"; return 1; fi
	if [ -n "$(echo 'exit' | mysql 2>&1)" ]; then log_failure "failed to connect to mysql server; make sure you have ~/.my.conf set up correctly"; return 1; fi
	mysql_databases="$(echo "show databases;" | mysql | grep -v -e '_schema$' | grep -Ev 'Database|extra_options|mysql|phpmyadmin|sys')"
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
	if [ ! $(which psql) ]; then log_failure "mysql not found"; return 1; fi
	if [ -n "$(echo "\q" | psql postgres 2>&1)" ]; then log_failure "failed to connect to postgres server; make sure you have ~/.pgpass set up correctly"; return 1; fi
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
	if [ -z "$dbname" ]; then log_failure "dbname variable not set, needed by do_mysql_dump"; return 1; fi
	dumppath="my.$dbname.sql"
	mysqldump --databases "$db" | head -n -1 > "$dumppath"
	if [ ! -s "$dumppath" ]
	then
		log_failure "failed to create dump for MySQL database %s at %s\n" "$dbname" "$dumppath"
		return 1
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
	if [ -z "$dbname" ]; then log_failure "dbname variable not set, needed by do_postgres_dump"; return 1; fi
	dumppath="pg.$dbname.sql"
	pg_dump "$db" -f "$dumppath"
	if [ ! -s "$dumppath" ]
	then
		log_failure "failed to create dump for postgres database %s at %s\n" "$dbname" "$dumppath"
		return 1
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
	if [ -z "$filepath" ]; then log_failure "filepath variable not set, needed by handle_raw_db_dump"; return 1; fi
	timestamp=$(date +"%Y-%m-%d-%H-%M")
	basename=${filepath%.*}
	newname="$basename.$timestamp.sql.gz"
	printf "new compressed file %s... " "$newname"
	last=$(find . -maxdepth 1 -type f -name "$basename.*.sql.gz" -printf '%Ts\t%p\n' | sort -nr | cut -f2 | head -n 1)
	gzip -n < "$filepath" > "$newname"
	printf "created!\n"
	rm -f "$filepath"
	if [ -e "$last" ]
	then
		printf "  comparing to previous dump %s... " "$last"
		if [ "${newname##*/}" = "${last##*/}" ]
		then
			printf "same file\n"
			return 1

		elif cmp --silent "$newname" "$last"
		then
			printf "identical! not storing new dump\n"
			rm -f "$newname" "unchanged.$newname"
			ln -s "$last" "unchanged.$newname"
			return 1
		else
			printf "different! keeping new dump\n"
		fi
	else
		printf "this seems to be the first dump\n"
	fi
	dumpsize=$(($(stat --printf='%s' $newname)/1048576))
}

function dump_all_mysql ()
{
	#
	# Using the above functions, dump all MySQL databases that have changed.
	#
	if ! (type -t "log_success" 1> /dev/null && type -t "log_info" 1> /dev/null && type -t "log_warning" 1> /dev/null && type -t "log_failure" 1> /dev/null)
	then
		log_failure "logging functions not set; aborting"
		return 1
	fi
	get_mysql_databases || return 1
	for db in $mysql_databases
	do
		do_mysql_dump "$db" &&
		handle_raw_db_dump "$dumppath" &&
		log_info "dumped MySQL $db to $newname ($dumpsize Mb)"
	done
	log_success "MySQL done: $(echo $mysql_databases)"
}

function dump_all_postgres ()
{
	#
	# Using the above functions, dump all postgres databases that have changed.
	#
	if ! (type -t "log_success" 1> /dev/null && type -t "log_info" 1> /dev/null && type -t "log_warning" 1> /dev/null && type -t "log_failure" 1> /dev/null)
	then
		printf "logging functions not set; aborting" >&2; return 1;
	fi
	get_postgres_databases || return 1
	for db in $postgres_databases
	do
		do_postgres_dump "$db" &&
		handle_raw_db_dump "$dumppath" &&
		log_info "dumped postgres $db to $dumppath ($dumpsize Mb)"
	done
	log_success "postgres done: $(echo $postgres_databases)"
}

function dump_all_dbs ()
{
	#
	# Dump all MySQL and postgres databases.
	#
	dump_all_mysql
	dump_all_postgres
}

function remote_run_dump_func ()
{
	#
	# Remotely run dump function $1 on machine $1 with output in directory $2.
	#
	if [ -z "$1" ]; then log_failure ""; fi
	if [ -z "$2" ]; then log_failure "provide a remote machine for remote_dump_all_dbs"; fi
	if [ -z "$3" ]; then log_failure "provide a (remote) directory for remote_dump_all_dbs"; fi
	code="$(typeset -f dump_all_dbs dump_all_postgres dump_all_mysql handle_raw_db_dump do_postgres_dump do_mysql_dump get_postgres_databases get_mysql_databases dummy_logs)"
	#ssh "$1" "$code; mkdir -p \"$2\"; cd \"$2\"; pwd; dummy_logs; dump_all_dbs" 2>&1 | (
	#    read err ; if [ -n "$err" ]; then log_warning "$err"; fi ) | (
	#    read out ; if [ -n "$out" ]; then log_info    "$out"; fi )
	ssh "$2" "$code; mkdir -p \"$3\"; cd \"$3\"; dummy_logs; $1" 1> /tmp/remote_dump.out 2> /tmp/remote_dump.err
    if [ -n "$(cat /tmp/remote_dump.out)" ]; then log_info "remote dump:\n$(cat /tmp/remote_dump.out)"; fi
    if [ -n "$(cat /tmp/remote_dump.err)" ]; then log_failure "remote dump:\n$(cat /tmp/remote_dump.err)"; fi
}

function remote_dump_all_dbs ()
{
    #
    # Dump all dbs on a remote ssh machine $1 in directory $2.
    #
	remote_run_dump_func "dump_all_dbs" "$1" "$2"
}

function remote_dump_mysql ()
{
	remote_run_dump_func "dump_all_mysql" "$1" "$2"
}

function remote_dump_postgres ()
{
	remote_run_dump_func "dump_all_postgres" "$1" "$2"
}



