#!/bin/bash

function make_sql_dumps ()
{
	timestamp=$(date +"%Y-%m-%d-%H-%M")
	databases=$(echo "show databases;" | mysql --user=$user --password=$password | grep -v -e '_schema$' | grep -v Database);
	
	for db in $databases
	do
		fname="${db}_$timestamp.db.sql"
		echo "$db -> $fname"
	
		# find previous backups
		last=$(find . -maxdepth 1 -type f -name "${db}_*.sql" -printf '%Ts\t%p\n' | sort -nr | cut -f2 | head -n 1)
	
		# dump the sql to a file, but strip the timestamp, so that it will be equal of no data changed
		mysqldump --user=$user --password=$password --database $db | head -n -1 > "$fname"
		
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


