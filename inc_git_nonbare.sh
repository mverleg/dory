#!/bin/bash

source inc_utils.sh

function get_bare_git_repos ()
{
	#
	# Get all bare git repositories in directory $1 (only direct descendants).
	#
	# $1 is the directory and $2 can optionally be the ssh server
	# $3 can be the maximum depth, which defaults to -1 (unlimited)
	# Sets $repos
	#
	depth_arg=""
	if [ -n "$1" ]; then repos_dir="$1"; fi
	if [ -n "$2" ]; then server="$2"; fi
	if [ "$2" == "." ]; then server=""; fi
	if [ -n "$3" ]; then if [ "$3" -ge "0" ]; then _depth=$3 depth_arg="-maxdepth $((_depth+1))"; fi; fi
	if [ -z "$repos_dir" ]; then log_failure "no directory given to get_git_repos to check for repos"; return 1; fi
	if ! which git 1> /dev/null ; then log_failure "git not installed! aborting"; return 1; fi
	if [ -n "$server" ]
	then
		repos=$(ssh "$server" find "$repos_dir" $depth_arg -type d -name 'objects')
	else
		repos=$(find "$repos_dir" $depth_arg -type d -name 'objects')
		server="local"
	fi
	_repos="$(make_path_relative "$repos" "$repos_dir" | sed 's/\(.*\)\/objects/\1/')"
	repos="${_repos%x}"  # to keep newlines
	printf "$repos"
}

function pull_clone_one_repo ()
{
    #
    # Get one repository up-to-date by pull or clone. Repeated step in pull_clone_repos.
    #
    # Arguments:
    #   $1 repo name
    #   $2 source parent target directory for the repo
    #   $3 optionally the source server
    # Silently assumes logging functions are defined.
    #
	if [ -n "$1" ]; then repo="$1"; fi
	if [ -n "$2" ]; then repos_dir="$2"; fi
	if [ -n "$3" ]; then server="$3"; fi
	echo "pwd = $(pwd) | repo = $repo"  # todo tmp
    if [ -e "$repo" ]
    then
        if [ -e "$repo/.git" ]
        then
            printf '%s exists; pulling\n' "$repo"
            cd "$repo"
            git pull || { log_failure "git pull failed for $repo" ; return 1; }
            log_info "pulled $repo (now $(du -h -d 0 . | cut -f 1))"
            cd ..;
        else
            log_failure "$repo exists but is not a git directory! skipping\n"
            return 1
        fi
    else
        printf '%s new; cloning\n' "$repo"
        if [ -z "$server" ]
        then
            git clone "$repos_dir/$repo" || {
                log_failure "local git clone failed for $repo" ; return 1; }
            log_info "cloned $repo (now $(du -h -d 0 $repo | cut -f 1))"
        else
            git clone "$server:$repos_dir/$repo" || {
                log_failure "remote git clone failed for $repo" ; return 1; }
            log_info "cloned $repo from $server (now $(du -h -d 0 $repo | cut -f 1))"
        fi
    fi
    return 0
}

function pull_clone_repos ()
{
	#
	# Get all repositories up-to-date with the server's latest version
	#   on the main or current branch, assuming no merge conflicts.
	#
	# Should be called from the directory where backups are to be stored.
	# Arguments: $1 should be the list of repos, $2 the directory they are stored and $3 optionally the server
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
		pull_clone_one_repo "$repo" "$repos_dir" "$server"
	done
}

function remote_find_and_clone ()
{
	#
	# Combination of get_bare_git_repos and pull_clone_repos that runs on a remote server
	#   (so it clones bare repos on that server tot non-bare ones)
	#
	# Arguments: $1 host, $2 source dir, $3 target dir
	# Silently assumes logging functions are defined.
	#
	if [ -n "$1" ]; then server="$1"; fi
	if [ "$1" == "." ]; then server=""; fi
	if [ -n "$2" ]; then source_root="$2"; fi
	if [ -n "$3" ]; then target_root="$3"; fi
	if [ -z "$1" ]; then log_failure "provide a remote machine for remote_find_and_clone"; return; fi
	if [ -z "$2" ]; then log_failure "provide a (remote) source directory for remote_find_and_clone"; return; fi
	if [ -z "$3" ]; then log_failure "provide a (remote) target directory for remote_find_and_clone"; return; fi
	code="$(typeset -f pull_clone_one_repo make_path_relative dummy_logs)"
	repos="$(get_bare_git_repos $source_root $server -1)"
	printf "repos found: $(echo $repos)\n"
	printf "pulling/cloning from $server:$source_root to $server:$target_root\n"
	total=0 #; for repo in $repos; do ((total+=1)); done
	success=0
	for repo_pth in $repos
	do
	    repo_name="$(basename ${repo_pth%.git})"
	    source_dir="${source_root}/$(dirname $repo_pth)"
	    target_dir="${target_root}/$(dirname $repo_pth)"
	    echo "repo_pth = $repo_pth | source_root = $source_root | target_root = $target_root | target_dir = $target_dir"  # todo
		# pull_clone_one_repo "$repo" "$repos_dir" "$server"
		ssh "$server" "$code; dummy_logs; mkdir -p \"$target_dir\"; cd \"$target_dir\"; pull_clone_one_repo \"$repo_name\" \"$source_dir\" \"\"" \
		    1> /tmp/remote_dump.out 2> /tmp/remote_dump.err
        if grep failed "/tmp/remote_dump.err" 1> /dev/null
        then
			log_failure "remote pullclone errors for $repo_pth: $(cat /tmp/remote_dump.err)"
		else
			printf "remote pullclone output & errors for $repo_pth:\n$(cat /tmp/remote_dump.out)\n$(cat /tmp/remote_dump.err)\n"
			((success+=1))
		fi
		((total+=1))
	done
	if [ "$success" -lt "$total" ]; then
		log_failure "git pullclone summary: only $success / $total completed without errors (stderr)"
	else
		log_success "git pullclone summary: all $success / $total completed without errors (stderr)"
	fi
}


