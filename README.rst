
Pax&rsync backups
-------------------------------

This code, although short, makes quite useful incremental backups.

* pax: used to 'copy' a directory by hardlinking all the files inside.
* rsync: used to then add all the changes to the copy

This will leave you with a complete copy of whatever you're trying to backup, for every time you use this script. Files only take significant space if they're changed (since they're just hardlinks otherwise).

It runs on a backup machine (like a raspberry pi or a server with extra space) and makes backups over ssh.

* Need your backed up data? Just go to the latest backup directory.
* Need an earlier version? Go to an earlier directory, or use diff to find where changes happened.

Other features:

* If your machine is compromised, the attacker cannot access backups.
* Lists unreadable files, then skips them gracefully.
* Easy to add logging hooks on success, failure, etc.
* Makes log entry about changes & available space.
* If a backup stops halfway, half the files are secure, and running again only only does the other half.

The code
-------------------------------

The code is short because the real work is done by a combination of established tools. This creates a lot of dependencies (bash, ssh, hardlinks, rsync, pax, possibly diff and cron...). But all of them are fairly small, and with the possible exception of pax they're all fairly standard on Ubuntu (and probably similar OSes). Pax is just `sudo apt-get install pax` (86kb).

Usage
-------------------------------

Some familiarity with bash scripting is required.

* Copy `pax.config.sh.demo` to `pax.config.sh`.
* Add what you want to backup (`source_dirs`) and where to (`backup_root`) in `pax.config.sh`.
* Optionally add some logging functionality in the same file.
* Execute `pax_backup.sh` in the same directory.

The last step makes the backup, and should most likely be made periodic (e.g. cron).

Recommended usage is to run this periodically from an secure and isolated machine (raspberry pi works well). Run this code to log into the machine(s) you want to backup and copy the changes.

An advantage of this setup is that backups happen from a seperate machine. If the target machine is compromised 1) the attacker has no access to backup credentials; many backup solutions run from the machine being backed up, so backup server access info must be stored somewhere, allowing the attacker to remove backups, and 2) the attacker cannot disable backups silently; you will be notified of the next failed backup if you set up logging.

Logging
-------------------------------

For logging, the code calls the functions defined in `pax.config.sh`. You can add any callbacks, emails, logfiles etc there. Backups only help if they're actually made, so it is recommended that you use some way to regularly check.

Git
-------------------------------

Some code is included to pull or clone a series of git reposities automatically (default branch). This could be used, in combination with the above, if you want to backup repositories, but want normal files instead of bare repositories. Otherwise you don't need it.

License etc
-------------------------------

MIT License. Just include the license and you can do pretty much what you want. But I am not to be held liable if something goes wrong.



