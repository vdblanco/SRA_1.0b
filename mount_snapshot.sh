#!/bin/bash
# Script for list existing snapshots and browse over them. During browsing, snapshot is mounted real partition instead, so we can read
# it through NFS or SMB.

exit=0
while [ $exit -eq 0 ]; do
	snaplist=$(lvs -o lv_name,lv_attr vg-repo --separator=';' --noheadings -S "lv_attr=~[^s.*]" | awk -F";" '{ printf $1 " <view> " }')
	if [ -z "$snaplist" ]; then
		dialog --title "Warning" --msgbox "No snapshots found." 0 0
		exit=1
	else
		snapsel=$(dialog --menu "Select snapshot to mount" 0 0 0 $snaplist 2>&1 >/dev/tty)
		exit=$?
	fi
	if [ $exit -eq 1 ]; then
		exit 0
	else
		if [ $(ps -fe | grep smbd | grep -v grep | wc -l) -gt 0 ]; then
			systemctl stop smbd
			samba_started=1
		else
			samba_started=0
		fi

		umount /backup/repository
		mount /dev/vg-repo/$snapsel /backup/repository
	
		if [ $samba_started -eq 1 ]; then
			systemctl start smbd
		fi

		#Directory contents visualization
		cd /backup/repository
		stat=0

		#Loop for file browser
		while [ $stat -eq 0 ]; do
			listdir=$(stat -c "%n:%F" * | cut -d" " -f1 | awk -F":" '{ print $1 "  " $2}')
			if [ -z "$listdir" ]; then
				dirsel="..  directory"
			fi
			if [[ $(pwd) == "/backup/repository" ]]; then
				dirsel=$(dialog --menu "Snapshot content" 0 0 0 $listdir 2>&1 >/dev/tty)
			else	
				dirsel=$(dialog --menu "Snapshot content" 0 0 0 .. directory $listdir 2>&1 >/dev/tty)
			fi
			stat=$?
			if [ -d $dirsel ]; then
				cd $dirsel
			else
				ficsel=$(stat -c "%n %z %sb" $dirsel)
				dialog --title "Properties" --msgbox "$ficsel" 0 0
			fi
		done

	#Umount snapshot and remount lv
	if [ $samba_started -eq 1 ]; then
		systemctl stop smbd
	fi

	cd
	umount /backup/repository
	mount /backup/repository

	if [ $samba_started -eq 1 ]; then
		systemctl start smbd
	fi
fi
done
