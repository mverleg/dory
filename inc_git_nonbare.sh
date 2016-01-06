#!/bin/bash

source inc_utils.sh

function get_bare_git_repos ()
{
	#
	# Get all bare git repositories in directory $1.
	#
	# $1 is the directory and $2 can optionally be the ssh server
	# Sets $repos
	#
	if [ -n "$1" ]; then repos_dir="$1"; fi
	if [ -n "$2" ]; then server="$2"; fi
	if [ -z "$repos_dir" ]; then log_failure "no directory given to get_git_repos to check for repos"; return 1; fi
	if ! which git 1> /dev/null ; then log_failure "git not installed! aborting"; return 1; fi
	if [ -n "$server" ]
	then
		repos=$(ssh "$server" find "$repos_dir" -type d -name 'objects')
	else
		repos=$(find "$repos_dir" -type d -name 'objects')
		server="local"
	fi
	_repos="$(make_path_relative "$repos" "$repos_dir" | sed 's/\(.*\)\/objects/\1/')"
	repos="${_repos%x}"  # to keep newlines
	printf "$repos"
}

function pull_clone_repos ()
{
    #
    # Get all repositories up-to-date with the server's latest version
    #   on the main or current branch, assuming no merge conflicts.
    #
    # Should be called from the directory where backups are to be stored.
    #
    if [ -n "$1" ]; then repos="$1"; fi
    if [ -n "$2" ]; then repos_dir="$2"; fi
    if [ -n "$3" ]; then server="$3"; fi
    if ! (type -t "log_success" 1> /dev/null && type -t "log_info" 1> /dev/null && type -t "log_warning" 1> /dev/null && type -t "log_failure" 1> /dev/null)
	then
		log_failure "logging functions not set; aborting"
		return 1
	fi
    for repo in $repos
	do
		if [ -e "$repo" ]
		then
			if [ -e "$repo/.git" ]
			then
				printf '%s exists; pulling\n' "$repo"
				cd "$repo"
				git pull || { log_failure "git pull failed for $repo" ; continue; }
				log_info "pulled $repo (now $(du -h -d 0 . | cut -f 1))"
				cd ..;
			else
				log_failure '$repo exists but is not a git directory! skipping\n'
				return 1
			fi
		else
			printf '%s new; cloning\n' "$repo"
			if [ -z "$server" ]
			then
				git clone "$repos_dir/$repo" || { log_failure "local git clone failed for $repo" ; continue; }
				log_info "cloned $repo (now $(du -h -d 0 . | cut -f 1))"
			else
				git clone "$server:$repos_dir/$repo" || { log_failure "remote git clone failed for $repo" ; continue; }
				log_info "pulled $repo from $server (now $(du -h -d 0 . | cut -f 1))"
			fi
		fi
	done
}


