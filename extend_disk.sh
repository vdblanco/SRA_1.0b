#!/bin/bash
#This script rescan repository device and adjust to the new size

# Function for rescan scsi buses
rescan_buses() {
for host in $(ls /sys/class/scsi_host/);
 do
	echo "$host"
	echo "- - -" >/sys/class/scsi_host/$host/scan
done
}

echo -e "\e[1;97;44m"
clear
rescan_buses
device=$(pvs | grep vg-repo | awk '{ print $1 }')
if [ -z  $(echo $device | egrep "[0-9]$") ]; then
	echo "Device is a whole Disk"
	echo 1 > /sys/block/$(echo $device | cut -d"/" -f3)/device/rescan
else
	disk=$(lsblk -no pkname $device | head -n1)
	echo 1 > /sys/block/$disk/device/rescan
	echo
	echo "Device is a partition. You need to resize partition before continue."
	echo "Recreate partition in parted with the new size. If the new size is not automatically detected, you need to restart appliance."
	echo
	read -p "Press enter to launch parted...."
	parted /dev/$disk
	partprobe /dev/$disk
fi
pvresize $device

# Check if snapshots are configured
crontab -l | grep mk_snap.sh >/dev/null
snapshots=$?

# LVM name depends if the volume is encrypted or not
if [ -e /dev/vg-repo/crypt ]; then
	# If encrypted, need to do with unmounted LVM
	umount /backup/repository
	cryptsetup luksClose backup
	if [ $snapshots -eq 1 ]; then
		echo "Snapshots are not configured"
		lvresize -l +100%FREE /dev/vg-repo/crypt
	else
		echo "Snapshots are configured"
		lvchange -an /dev/vg-repo/crypt
		lvresize -l +80%FREE /dev/vg-repo/crypt
		lvchange -ay /dev/vg-repo/crypt
	fi
	cryptsetup luksOpen /dev/vg-repo/crypt backup
	mount /backup/repository
else
	if [ $snapshots -eq 1 ]; then
		echo "Snapshots are not configured"
		# Hot resize
		lvresize -l +100%FREE /dev/vg-repo/backup
	else
		echo "Snapshots are configured"
		umount /backup/repository
		lvchange -an /dev/vg-repo/backup
		lvresize -l +80%FREE /dev/vg-repo/backup
		lvchange -ay /dev/vg-repo/backup
		mount /backup/repository
	fi
fi
	
xfs_growfs /backup/repository
sleep 10
echo -e "\e[0m"
clear
exit 0 
