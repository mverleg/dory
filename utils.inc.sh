#!/bin/bash

function diskspace_used ()
{
    #
    # Writes the current space use in directory $1 in Mb to stdout and stores it in space_used.
    #
    if [ -z "$1" ]; then log_warning "diskspace_used called without directory to check"; return; fi
    space_used=$(df -P "$1" | tail -1 | awk '{printf $4 ; printf " / " ; print $2 ;}')
    space_used="$((space_used/1024))"
    printf "$space_used"
}

function diskspace_available ()
{
    #
    # Writes the current available space in directory $1 in Mb to stdout and stores it in space_available.
    #
    if [ -z "$1" ]; then log_warning "diskspace_available called without directory to check"; return; fi
	space_available="$(df -P $1 | tail -1 | awk '{print $4}')"
	space_available="$((space_available/1024))"
    printf "$space_available"
}

function is_low_diskspace()
{
    #
    # Check if directory $1 is low on available diskspace. Emits errors and has non-zero return status if so.
    #
    # Arguments $2 and $3 can optionally be the low and critical levels in Mb.
    #
    if [ -z "$1" ]; then log_warning "is_low_diskspace called without directory to check"; return; fi
    if [ -n "$2" ]; then low_level="$2"; else low_level="10240"; fi
    if [ -n "$3" ]; then critical_level="$3"; else critical_level="1024"; fi
    avail="$(diskspace_available $1)"
    if [ "$avail" -lt "$critical_level" ]
	then
		log_failure "free space for backups is getting critically low! less than $critical_level Mb remains: $avail Mb"
		return 2
	elif [ "$avail" -lt "$low_level" ]
	then
		log_warning "free space for backups is getting low, less than $low_level Mb remains: $avail Mb"
		return 1
	fi
	return 0
}


