#!/bin/bash

# get settings from pax.config.sh (outside git) if it exists
dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
if [ -a "$dir/pax.config.sh" ];
then
	source "$dir/pax.config.sh"
else
    log_failure 'please create a pax.config.sh file containing settings'
    exit 2
fi

# make sure you have rsync and pax!
which rsync > /dev/null || log_failure "rsync is not installed"
which pax > /dev/null || log_failure "pax is not installed"
{ which rsync && which pax; } > /dev/null || exit 9

# go to root dir
backup_root=${backup_root%/}
cd $backup_root || { log_failure "backup directory not found or not accessible: $backup_root"; exit 3; }
/bin/rm -rf .tmp
function space_use () { df -Ph "$backup_root" | tail -1 | awk '{printf $4 ; printf " / " ; print $2 ;}' ; }

# check available space
space_available="$(df -P $backup_root | tail -1 | awk '{print $4}')"
if [[ "$space_available" -lt "1048576" ]]
then
    log_failure "free space for backups is getting very low! less than 1GB remains: $(space_use)"
elif [[ "$space_available" -lt "5242880" ]]
then
    log_warning "free space for backups is getting low, less than 5GB remains: $(space_use)"
fi

# find previous backups
backup_count=$(( $(find $backup_root -maxdepth 1 -type d | wc -l) - 1 ))
printf 'there are %d entries in %s\n' $backup_count $backup_root
if [[ ! $backup_count -ge 1 ]];
then
    mkdir -p "$backup_root/empty"
fi
latest_backup=$(ls -d -1 */ | grep -v '^empty/*$' | tail -n 1) &&
latest_backup=${latest_backup%/} ||
    { log_failure "could not locate latest backups: $latest_backup"; exit 4; }

# find the new backup location
new_location="backup_$(date +"%y-%m-%d-%H-%M-%S")"
if [ -a "$new_location" ]
then
	log_failure "\"$new_location\" already exists; did you run the script twice in one second?"
	exit 5
fi
mkdir "$new_location" .tmp || { log_failure "could not create directories"; exit 6; }

# pax for each project
for source_dir in "${source_dirs[@]}"
do
    # hardlink the old location's files to the new one
    currentdirname="$(basename $source_dir)"
    if [ -e "$latest_backup/$currentdirname" ]
    then
        pax -rwl "$latest_backup/$currentdirname" .tmp &&
        /bin/mv ".tmp/$latest_backup/$currentdirname" "$new_location/$currentdirname" &&
        printf 'symlinked "%s" from "%s" to "%s"\n' $currentdirname $latest_backup $new_location ||
            { log_failure "could not recursively symlink directories with pax: $latest_backup/$currentdirname -> $new_location/$currentdirname"; exit 7; }
    else
        log_info "new item added to backup: $currentdirname"
    fi
done

# rsync for each project
for source_dir in "${source_dirs[@]}"
do
    # find files that are unreadable to exclude them: https://unix.stackexchange.com/questions/63410/rsync-skip-files-for-which-i-dont-have-permissions
	exclude_file=$(mktemp)
	ssh rafiki 'cd $source_dir; find . ! -readable -o -type d ! -executable 2> /dev/null | sed "s|^\./||"' > "$exclude_file"
    # sync this with the target directory, incl. delete
	source_dir=${source_dir%/} &&
	rsync -arzphH -e ssh --delete --checksum --verbose --exclude-from="$exclude_file" $source_dir $new_location &&
	printf '"%s" now contains a clone of "%s"\n\n' $new_location $source_dir ||
        { log_failure "could not sync directories: $source_dir -> $new_location"; exit 8; }
done

# create hash of the directory
cd "$backup_root/$latest_backup"
old_hash="$(find . -type f ! -name 'log' -print0 | sort -z | xargs -0 sha1sum -b | sha1sum | cut -f 1 -d ' ')"
old_size="$(du -h -d 0  --exclude=log . | cut -f 1)"
cd "$backup_root/$new_location"
new_hash="$(find . -type f ! -name 'log' -print0 | sort -z | xargs -0 sha1sum -b | sha1sum | cut -f 1 -d ' ')"
new_size="$(du -h -d 0 --exclude=log . | cut -f 1)"

# check if the directory has changed
if [[ "$old_hash" == "$new_hash" ]]
then
    /bin/rm -rf "$backup_root/$latest_backup"
    echo "/bin/rm -rf $backup_root/$latest_backup"
    log_info "ran backup for ${source_dirs[0]} and ${#source_dirs[@]} others, but found no changes (old backup replaced), hash ${new_hash:0:8}..."
else
    log_success "succesfully backed up ${source_dirs[0]} and ${#source_dirs[@]} others, size $old_size -> $new_size, hash ${new_hash:0:8}..."
fi

# log some info
printf "%s\nold   %s   %s   %s\nnew   %s   %s   %s\nspace left: %s\n\n" "$(date +'%y-%m-%d %H:%M:%S')" "$old_size" "$old_hash" "$latest_backup" "$new_size" "$new_hash" "$new_location" "$(space_use)" > "$backup_root/$new_location/log"
for source_dir in "${source_dirs[@]}"; do echo "$source_dir" >> "$backup_root/$new_location/log"; done
printf "\n"; cat "$backup_root/$new_location/log"

# remove empty dir if it exists
rm -rf "$backup_root/empty"


