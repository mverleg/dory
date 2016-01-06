#!/bin/bash

function get_git_repos ()
{
    #
    #
    #
	if ! which git 1> /dev/null ; then log_failure "git not installed! aborting"; return 1; fi

}

get_git_repos

function bla ()
{
    dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

    # get settings from git.config.sh (outside git) if it exists
    server='gitserver'
    repos_dir='/repos'
    backup_root='/backup'

    if [ -a "$dir/git.config.sh" ]
    then
        source "$dir/git.config.sh"
    else
        printf 'please create a git.config.sh file containing settings\n'
        exit
    fi

    # preparation
    mkdir -p "$backup_root"
    cd "$backup_root"
    if [ -z "$server" ]
    then
        # local backup
        repos=$(/bin/ls "$repos_dir")
    else
        repos=$(ssh "$server" "/bin/ls $repos_dir")
    fi

    # pull or clone all the repositories found
    for repo in $repos;
    do
        if [ -e "$repo" ];
        then
            if [ -e "$repo/.git" ];
            then
                printf '%s exists; pulling\n' "$repo";
                cd "$repo";
                git pull;
                cd ..;
            else
                printf '%s exists but is not a git directory! skipping\n' "$repo" >&2;
            fi
        else
            printf '%s new; cloning\n' "$repo";
            if [ -z "$server" ];
            then
                git clone "$repos_dir/$repo";
            else
                git clone "$server:$repos_dir/$repo";
            fi;
        fi;
    done;

    # that was simple
    printf 'done!\n';
}


