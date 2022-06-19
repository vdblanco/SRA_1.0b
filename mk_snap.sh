#!/bin/bash

# Script for daily snapshots. It will save last 5 days deleting olders.

# Get vg size and lv size. Initial setup lets 20% of space free, but we will calculate the difference, every snapshot will take 1/5 of it.
vgsize=$(/usr/sbin/vgs vg-repo -o VG_SIZE --noheadings --units g --nosuffix)

if [ ! -z $(ls /dev/vg-repo/crypt) ]; then
	lvsize=$(/usr/sbin/lvs /dev/vg-repo/crypt -o LV_SIZE --noheadings --units g --nosuffix)
	device=/dev/vg-repo/crypt
else
	lvsize=$(/usr/sbin/lvs /dev/vg-repo/backup -o LV_SIZE --noheadings --units g --nosuffix)
	device=/dev/vg-repo/backup
fi

# Create today's snapshot
size=$(echo $vgsize $lvsize | /usr/bin/awk '{ print ($1 - $2) / 6 }')
/usr/sbin/lvcreate -s -n snap_$(date '+%Y-%m-%d') -L ${size}G $device

# Delete older snapshot if there are more than 4
if [ $? -eq 0 ]; then
	if [ $(/usr/sbin/lvs -o lv_name,lv_attr vg-repo --separator=';' --noheadings -S "lv_attr=~[^s.*]" | wc -l ) -gt 4 ]; then
		snapolder=$(/usr/sbin/lvs -o lv_name,lv_attr vg-repo --separator=';' --noheadings -S "lv_attr=~[^s.*]" | head -n1 | awk -F";" '{ printf $1 }' | awk '{ printf $1 }')
		/usr/sbin/lvremove -f /dev/vg-repo/$snapolder
	fi
fi
