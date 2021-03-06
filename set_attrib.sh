#!/bin/bash
# Mantain "i" attribute in NFS & SMB repositories during files lifetime (parameter)

/usr/bin/find /backup/repository -type f -mtime +$1 -execdir chattr -i -- '{}' \;
/usr/bin/find /backup/repository -type f \( -name "*.vbk" -o -name "*.vib" -o -name "*.bkf" -o -name "*.bak*" -o -name "*.arc" \) -mtime -$1 -amin +60 -execdir chattr +i -- '{}' \;
