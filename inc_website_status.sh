#!/bin/bash

source inc_utils.sh

function get_websites_statuses ()
{
	#
	# Checks the status of a list of websites and reports any problems, unless problems were already reported today.
	#
	# $1 or $webpages should be an array of webpages to check (not $websites_, which is used internally).
	# notify_problem should be a function that communicates any problems.
	#
	if [ -n "$1" ]
	then
		declare -a websites_=( "${!1}" );
	elif [ -n "$source_dirs" ]
	then
		declare -a websites_=( "${webpages[@]}" );
	else
		log_failure "webpages variable not set, needed by get_websites_statuses\n"
		return 1
	fi

	problems=""
	do_notify=false
	mkdir -p "/tmp/website_status_locks"

	for website in "${websites_[@]}"
	do
		status=$(curl --location --silent --output /dev/null --connect-timeout 15 --write-out "%{http_code}" "$website")
		printf 'site "%s" status %s\n' $website $status
		stripname="$(echo $website | sed 's/.*\/\/\(.*\)/\1/' | sed 's/\//\_/g' | sed 's/[^a-zA-Z0-9\.\-\_]/-/g')"
		lockfile="/tmp/website_status_locks/$stripname"
		if file_age_less_than "$lockfile" 1439
		then
			if [ "$status" -eq "200" ]
			then
				# the status was okay, remove records of previous problems
				rm -f "$lockfile"
			else
				# there is a problem but there was one recently, so don't notify unless there are others
				problems="$problems\n$website\t$status"
			fi
		else
			if [ "$status" -ne "200" ]
			then
			    # there is a problem and it is the first in a while for this site, so notify and lock
			    touch "$lockfile"
			    do_notify=true
				problems="$problems\n$website\t$status"

            # ELSE: there is no problem and there wasn't one before, so do nothing
			fi
		fi
	done

	if $do_notify
	then
		notify_problem "there were problems!$problems"
		return 1
	fi
	return 0
}


