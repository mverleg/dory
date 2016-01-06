#!/bin/bash

function get_websites_statuses ()
{
    #
    # Checks the status of a list of websites and reports any problems.
    #
    # $1 or $webpages should be an array of webpages to check (not $websites, which is used internally).
    # notify_problem should be a function that communicates any problems.
	if [ -n "$1" ]
	then
		declare -a $websites=( "${!1}" );
	elif [ -n "$source_dirs" ]
	then
	    declare -a $websites=( "${webpages[@]}" );
	else
        log_failure "webpages variable not set, needed by get_websites_statuses\n"
        return
	fi

    problems=""

    for website in "${websites[@]}"
    do
        status=$(curl --location --silent --output /dev/null --connect-timeout 15 --write-out "%{http_code}" "$website")
        printf 'site "%s" status %s\n' $website $status
        if [ "$status" -ne "200" ]
        then
            problems="$problems\n$website\t$status"
        fi
    done

    if [ -n "$problems" ]
    then
        notify_problem "there were problems!$problems"
        return 1
    fi
    return 0
}


