#!/bin/bash

dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
if [ -a "$dir/website.config.sh" ];
then
	source "$dir/website.config.sh"
else
    log_failure 'please create a website.config.sh file containing settings'
    exit 2
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
fi


