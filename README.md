BlockFile-Incremental
=====
Block-file incremental is a fast, small Ruby script created to backup and restore large block files, especially TrueCrypt containers.  
Because I did not found any simple solutions to make a comprehensible incremental backups of huge single files, I did it myself.

TrueCrypt container files are nice block files, which means if a single file in the container is changed, of course only a small part of the huge file is changed.  
By reading a file block by block and store the blocks as single files, only few changed blocks must be stored in additional backups.

For my backup strategy, I frequently make incremental backups of different huge TrueCrypt containers using this script and upload the archives to Amazon Glacier using the [glacieruploader][1] by [MoriTanosuke][2].  
If my house explodes, I can download the initial backup archive and the latest backup archive to restore my container.

What it will do
---------------
* Reads a huge file in specific sized blocks and save the content to a specific path in thousands of files which filenames represent the SHA256 checksum of its content
* A csv hash table (hashtable.csv) will be built with the start position and the checksum
* With the files and the hash table the complete file can be restored

Initial Backup
----------------
* If no initial backup is found in the target path, a new initial backup will be created automatically
* All file blocks will be written and a huge hash table (hashtable.csv) will be created

Incremental Backup
----------------
* All changed blocks since the __last__ backup will be written
* Backups have the lowest size, but EACH backup is needed to restore the newest file

Differential Backup
----------------

* All changed blocks since the __initial__ backup will be written
* Backups size will increase, the longer the initial backup is ago, but only initial backup and newest backup is needed to restore the newest file

Restore
----------------
* The newest hash table file will be read and all needed files will be searched in the backup folders inside the configured target path
* The initial backup is also necessary. If you make a restore of a incremental backup, __all__ backup folders will be needed because some, non-changed blocks will be stored in older backup folders
* Only the latest hash table file is needed. All files written in the hash table will be searched and are necessary.
* _The unpacked folders will be needed! Unpacking tar files is not implemented_

Target Path Content Example
----------------
Started backup 2013-04-25 with a container file of 48 GB, this is the content of the folder defined in target-path. Packing was disabled.  
_The used command was always the same! The first folder was an initial backup and initial backups are only created if needed._

Backup Date | Directory  | Files | Size
--------- | ------------- | ------------- | -----------
2013-04-25 | 20130425T003013 | 9832 Elements | 48 GB 
2013-10-18 | 20131018T111037  | 458 Elements | 2,2 GB
2013-11-30 | 20131130T185938  | 479 Elements | 2,3 GB
2014-01-16 | 20140116T080317  | 507 Elements | 2,5 GB
2014-05-23 | 20140523T083851  | 554 Elements | 2,7 GB


Configuration File
----------------
A YAML configuration file is needed to backup or restore data.
```
container: 'huge-file.tc'    | file path to the file to backup
 mode: 'differential'        | backup mode (differential or incremental)
 target-path: 'backup_100m'  | folder (from working directory) where backups are searched and created
 block-size: 5               | block size in megabytes
 truecrypt:
   enabled: true             | enables TrueCrypt features
   binary: 'truecrypt -t'    | binary command to use
   unmount: true             | try to unmount a TrueCrypt container before start backup
 packing:
   enabled: true             | enables packup features
   format: 'tar'             | archive format
```

### Block Size ###
With a bigger block size, less blocked files will be created and a smaller hash table will be built.  
But even if a small bit in a block is changed, a file sized in the defined size will be created in the backup.  
_The bigger the block size, the faster is your backup and the bigger are your incremental or differential backups!_  
__Notice:__ Changing the block-size between initial backup and later backups is not supported or tested.

### Packing ###
Initial backup of a ~ 52 GB file resulted in 9832 single files in the target path's backup folder.  
Packing this to a tar archive is useful if you want to transport your backup.  
__Notice:__ Don't be confused from the configuration possibility. Tar is the only format supported. :-)

Requirements
----------------
All I know, Ruby 2.0.0 is required.

Warnings
----------------
* The hash table file (hashtable.csv) is the place, where all block hashes and it's exact byte position in the file is stored!  
  Killing your hash table kills your backup.
* It's great for me and it works with huge TrueCrypt containers. I could backup and restore containers (> 50 GB) without problems after many (differential) backups.  
  But also no one did a security audit or long term tests. Only _one_ wrong written bit or one missing block file would destroy the whole backup, so I cannot recommend a corporate use and guarantee for a long term solution without the possibility of bugs or data loss. 

Usage Examples
-----
Make a backup based on the given config file

`blockfile_incremental.rb backup config.yml`

Make a restore based on the given config file.
The restored file will be the configured source file, but if it already exists, wont be overwritten.

`blockfile_incremental.rb restore config.yml`

Make a restore based on the given config file and save restored file to the given path

`blockfile_incremental.rb restore config.yml /tmp/restorefile.dat`

Questions
-----
If you find a bug, if you have other issues or wishes or if you have questions or problems feel free to contact me.  
Also feel free to fork this project and make it even better.

License
-----
This project is distributed under [GNU GPL v3][3].

[1]: https://github.com/MoriTanosuke/glacieruploader
[2]: https://github.com/MoriTanosuke
[3]: http://www.gnu.org/licenses/gpl-3.0.html