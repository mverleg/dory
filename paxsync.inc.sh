#!/bin/bash

source utils.inc.sh

function find_exclude_paths ()
{
	#
	# Find unreadable files and directories, and optionally hidden directories.
	#
	# Argument: $1 or $dir_path: directory to check for files to skip.
	#   $2 or $skip_hidden_dirs: true to skip hidden directories [default true]
	# Prints the paths that are to be skipped
	#
	if [ -n "$1" ]; then dir_path="$1"; fi
	if [ -n "$2" ]; then skip_hidden_dirs="$2"; fi
	if [ -z "$skip_hidden_dirs" ]; then skip_hidden_dirs=true; fi
	# find all inaccessible files and directories
	find "$dir_path" -type d ! -executable 2> /dev/null | sed 's|^\./||'
	find "$dir_path" -type f ! -readable 2> /dev/null | sed 's|^\./||'
	if $skip_hidden_dirs
	then
		# find all the hidden directories; get both directory and directory/*
		find "$dir_path" -type d -name '.*' 2> /dev/null | sed -e 's/\(.*\)$/\1\n\1\/*/'
	fi
}

function do_pax_sync_all()
{
	#
	# Create a copy of a (remote) directory, where all files that haven't changes since the last copy are hardlinked.
	#
	# Arguments:
	#   $1 or backup_root: directory to store backups in locally
	#   $2 or $skip_hidden_dirs: do not sync directories starting with a period
	#   $3 or $source_dirs: array of targets to backup
	#   log_success, log_info, log_warning and log_failure functions should be defined
	#

	# check input
	if ! (type -t "log_success" 1> /dev/null && type -t "log_info" 1> /dev/null && type -t "log_warning" 1> /dev/null && type -t "log_failure" 1> /dev/null)
	then
		printf "logging functions not set; aborting" >&2; return;
	fi
	if [ -n "$1" ]; then backup_root="$1"; fi
	if [ -n "$2" ]; then skip_hidden_dirs="$2"; else skip_hidden_dirs=false; fi
	if [ -n "$3" ]
	then
		declare -a from_dirs=( "${!3}" );
	elif [ -n "$source_dirs" ]
	then
	    declare -a from_dirs=( "${source_dirs[@]}" );
	else
        log_failure "source_dirs variable not set, needed by pax sync\n"
        return
	fi
	if [ -z "$from_dirs" ]; then log_failure "from_dirs variable not set, needed by pax sync\n"; return; fi
	if ! which pax 1> /dev/null ;   then log_failure   "pax not installed! aborting"; return; fi
	if ! which rsync 1> /dev/null ; then log_failure "rsync not installed! aborting"; return; fi

	# go to root dir
	wd=$(pwd)
	backup_root=${backup_root%/}
	mkdir -p "$backup_root"
	cd $backup_root || { log_failure "backup directory not found or not accessible: $backup_root"; return; }
	rm -rf "$backup_root/.tmp"

	# check available space
	is_low_diskspace "$backup_root"

	# find previous backups
	backup_count=$(( $(find $backup_root -maxdepth 1 -type d | wc -l) - 1 ))
	printf 'there are %d entries in %s\n' $backup_count $backup_root
	if [[ ! $backup_count -ge 1 ]];
	then
		mkdir -p "$backup_root/empty"
	fi

	# latest_backup=$(ls -d -1 */ | grep -v '^empty/*$' | tail -n 1) &&
	latest_backup=$(ls -d -1 */ | tail -n 1) &&
	latest_backup=${latest_backup%/} ||
		{ log_failure "could not locate latest backups: $latest_backup"; return 4; }

	# find the new backup location
	new_location="backup_$(date +"%y-%m-%d-%H-%M-%S")"
	if [ -a "$new_location" ]
	then
		log_failure "\"$new_location\" already exists; did you run the script twice in one second?"
		return 5
	fi
	mkdir "$new_location" .tmp || { log_failure "could not create directories"; return 6; }

	# pax for each project
	for source_dir in "${from_dirs[@]}"
	do
		# hardlink the old location's files to the new one
		currentdirname="$(basename $source_dir)"
		if [ -e "$latest_backup/$currentdirname" ]
		then
			# pax info (can't find where I learned about it initially): http://unix.stackexchange.com/a/202435/56576
			pax -rwlpe "$latest_backup/$currentdirname" .tmp &&
			\mv ".tmp/$latest_backup/$currentdirname" "$new_location/$currentdirname" &&
			printf 'symlinked "%s" from "%s" to "%s"\n' $currentdirname $latest_backup $new_location ||
				{ log_failure "could not recursively symlink directories with pax: $latest_backup/$currentdirname -> $new_location/$currentdirname"; return 7; }
		else
			log_info "new item added to backup: $currentdirname"
		fi
	done
	rm -rf .tmp

	# rsync for each project
	for source_dir in "${from_dirs[@]}"
	do
		# set up some initial values
		source_dir=${source_dir%/}
		syncflags=""
		exclude_file=$(mktemp).ignore
		printf "__pycache__\n*.pyc\n*~\n" > "$exclude_file"  # some initial value so it's created
		if [[ $source_dir == *":"* ]]
		then
			# find excluded files for remote directory
			server_name="$(echo $source_dir | sed 's/:.*//')"
			dir_path="$(echo $source_dir | sed 's/.*\://')"
			printf 'finding unreadable files to exclude from "%s" on "%s"\n' "$dir_path" "$server_name"
			ssh "$server_name" "$(typeset -f find_exclude_paths); find_exclude_paths \"$dir_path\" $skip_hidden_dirs" >> "$exclude_file"
			syncflags="$syncflags -e ssh"
		else
			# find excluded files for local directory
			dir_path="$source_dir"
			printf 'finding unreadable files to exclude from "%s" locally\n' "$dir_path"
			find_exclude_paths "$dir_path" $skip_hidden_dirs >> "$exclude_file"
		fi
		# make paths relative or it doesn't work
		while read line
		do
			python -c "import os.path; print os.path.relpath('$line', '$dir_path') if '$line'.startswith('/') else '$line'" >> "$exclude_file.rel"

		done < "$exclude_file"
		exclude_file="$exclude_file.rel"
		printf 'excluding %d files from "%s" (see "%s")\n' "$(cat $exclude_file | wc -l)" "$dir_path" "$exclude_file"
		# sync this with the target directory, incl. delete
		printf 'copying changed files from "%s"\n' "$source_dir"
		rsync -arzphH $syncflags --delete --checksum --verbose --exclude-from="$exclude_file" $source_dir $new_location &&
		printf '"%s" now contains a clone of "%s"\n\n' $new_location $source_dir ||
			{ log_failure "could not sync directories: $source_dir -> $new_location"; return 8; }
	done
	cd "$wd"

	# create hash of the directory
	cd "$backup_root/$latest_backup"
	old_hash="$(find . -type f ! -name 'log' -print0 | sort -z | xargs -0 sha1sum -b | sha1sum | cut -f 1 -d ' ')"
	old_size="$(du -h -d 0  --exclude=log . | cut -f 1)"
	cd "$wd"
	cd "$backup_root/$new_location"
	new_hash="$(find . -type f ! -name 'log' -print0 | sort -z | xargs -0 sha1sum -b | sha1sum | cut -f 1 -d ' ')"
	new_size="$(du -h -d 0 --exclude=log . | cut -f 1)"
	cd "$wd";

	# check if the directory has changed
	if [[ "$old_hash" == "$new_hash" ]]
	then
		\rm -rf "$backup_root/$latest_backup"
		log_info "ran backup for ${from_dirs[0]} and ${#from_dirs[@]} others, but found no changes (old backup replaced), hash ${new_hash:0:8}..."
	else
		log_success "successfully backed up ${from_dirs[0]} and ${#from_dirs[@]} others, size $old_size -> $new_size, hash ${new_hash:0:8}..."
	fi

	# log some info
	logfile="$backup_root/$new_location/log"
	date +'%y-%m-%d %H:%M:%S' > "$logfile"
	printf "old   %s   %s   %s\n" "$old_size" "$old_hash" "$latest_backup" >> "$logfile"
	printf   "new   %s   %s   %s\n" "$new_size" "$new_hash" "$new_location" >> "$logfile"
	printf "space left: %s\n" "$(diskspace_used $backup_root)" >> "$logfile"

	for source_dir in "${from_dirs[@]}"
	do
		echo "$source_dir" >> "$logfile"
	done
	printf "\n"; cat "$logfile"
	printf "this is a generated logfile and not part of the backup\n\n" >> "$logfile"

	# remove empty dir if it exists
	rm -rf "$backup_root/empty"
}


