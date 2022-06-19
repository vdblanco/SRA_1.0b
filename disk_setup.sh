#!/bin/bash

# Function for rescan scsi buses
rescan_buses() {
echo -e "\e[1;97;44m"
clear
echo "Searching for new devices"
for host in $(ls /sys/class/scsi_host/);
 do
	echo "$host"
	echo "- - -" >/sys/class/scsi_host/$host/scan
done
echo -e "\e[0m"
clear
}

# Function for obtain valid devices - Not mounted disks, not swap, not extended partitions and not used as LVM volume
# Only whole disks without partitioning if it is not mounted any partition
search_devices() {
device=""
devices=""
for device in $(grep -v -e major -e '^$' -e sr /proc/partitions | grep -v "dm-" | awk '{ print $4 }');
 do
	mounted=$(mount | grep $device)
	if [ -z "$mounted" ]; then
		swap=$(grep $device /proc/swaps)
		if [ -z "$swap" ]; then
			if [ $(grep $device /proc/partitions | head -n1 | awk '{ print $3 }') -gt 1 ]; then
				aslvm=$(pvs | grep $device)
				if [ -z "$aslvm" ]; then
					if [ -z  $(echo $device | egrep "[0-9]$") ]; then
						devices="$devices $device     Disk"
					else
						devices="$devices $device     Partition"
					fi
				fi
			fi
		fi
	fi
done
}

# Function to format selected device
format_device() {
echo "Creating LVM volume on $devicesel....."
pvcreate -ff /dev/$devicesel
vgcreate vg-repo /dev/$devicesel
lvcreate -l $1%FREE -n backup vg-repo
sleep 1
echo "Formating as XFS volume....." 
mkfs.xfs -b size=4096 -m reflink=1,crc=1 /dev/vg-repo/backup
}

# Function to format selected device as encrypted
format_crypt_device() {
clear
echo "Creating LVM volume on $devicesel....."
pvcreate -ff /dev/$devicesel
vgcreate vg-repo /dev/$devicesel
lvcreate -l $1%FREE -n crypt vg-repo
cryptsetup luksFormat --type luks2 -q /dev/vg-repo/crypt
cryptsetup luksOpen /dev/vg-repo/crypt backup
sleep 1
echo "Formating as XFS volume....."
mkfs.xfs -b size=4096 -m reflink=1,crc=1 /dev/mapper/backup
}

# Function to mount device and set up permissions
mount_device() {
mkdir -p /backup/repository
echo "Mounting device....."
mount /dev/vg-repo/backup /backup/repository
echo "Changing permissions...."
if [ ! $(id -u userrepo 2>/dev/null) ]; then
	useradd userrepo
fi
chown -R userrepo:users /backup/repository
chmod 700 /backup/repository
echo "/dev/vg-repo/backup	/backup/repository	xfs    defaults	 1       1" >>/etc/fstab
}

# Function to mount device and set up permissions on a encrypted device
mount_crypt_device() {
mkdir -p /backup/repository
echo "Mounting device....."
mount /dev/mapper/backup /backup/repository
echo "Changing permissions...."
if [ ! $(id -u userrepo 2>/dev/null) ]; then
        useradd userrepo
fi
chown -R userrepo:users /backup/repository
chmod 700 /backup/repository
echo "/dev/mapper/backup       /backup/repository      xfs    defaults  1       1" >>/etc/fstab 
echo "backup       /dev/vg-repo/crypt      none" >>/etc/crypttab
}  

# Function to clear screen and draw menu
show_menu() {
#Text definitions for menu
menu=(dialog --menu "Backup disk setup" 0 0 0 )
options=(1 "Search for new devices" 
2 "Select device for repository"
3 "Device partitioning"
4 "Format and mount device as repository"
5 "Format and mount device as encrypted repository"
6 "Format and mount device as repository with periodic snapshots"
7 "Format and mount device as encrypted repository with periodic snapshots"
0 "Exit from menu")

#Create menu
options=$("${menu[@]}" "${options[@]}" 2>&1 >/dev/tty)
if [ $? -eq 1 ]; then
	exit 0
fi
clear

for option in $options
do
	case $option in
	1)
		rescan_buses
	;;

	2)
		echo -e "\e[1;97;44m"
		clear
		search_devices
		if [ -z $devices ]; then
			dialog --title "Warning" --msgbox "No valid devices found, please add & rescan first." 0 0
		else
			devicesel=$(dialog --menu "Select disk or partition" 0 0 0 $devices 2>&1 >/dev/tty)
		fi
		echo -e "\e[0m"
		clear
	;;

	3)
                mounted=$(mount | grep /backup/repository)
                if [ -z "$mounted" ]; then
			echo -e "\e[1;97;44m"
			clear
			parted /dev/$devicesel
			echo -e "\e[0m"
			clear
		else
                        dialog --title "ERROR" --msgbox "Disk repository is already mounted. For security reasons you can't edit disks." 0 0
		fi
	;;
	4)
	        mounted=$(mount | grep /backup/repository)
        	if [ -z "$mounted" ]; then
			if [ -z $devicesel ]; then
				dialog --title "Warning" --msgbox "Please, select a device first." 0 0
			else
				dialog --title "Warning" --yesno "This action will destroy all data in $devicesel. Do you want really use $devicesel as repository?" 0 0 2>&1 >/dev/tty
				if [ $? -eq 0 ]; then
					echo -e "\e[1;97;44m"
					clear
					format_device 100
					sleep 1
					mount_device
					devicesel=""
					sleep 2
					echo -e "\e[0m"
					clear
				fi
			fi
		else
			dialog --title "ERROR" --msgbox "Disk repository is already mounted. For security reasons this action only can be done once." 0 0
		fi
		
	;;
	5)
                mounted=$(mount | grep /backup/repository)
                if [ -z "$mounted" ]; then
                        if [ -z $devicesel ]; then
                                dialog --title "Warning" --msgbox "Please, select a device first." 0 0
                        else
                                dialog --title "Warning" --yesno "This action will destroy all data in $devicesel. Do you want really use $devicesel as repository?" 0 0 2>&1 >/dev/tty
                                if [ $? -eq 0 ]; then
					echo -e "\e[1;97;44m"
					clear
                                        format_crypt_device 100
                                        sleep 1
                                        mount_crypt_device
                                        devicesel=""
                                        sleep 2
					echo -e "\e[0m"
					clear
                                fi
                        fi
                else
                        dialog --title "ERROR" --msgbox "Disk repository is already mounted. For security reasons this action only can be done once." 0 0
                fi

        ;;
	6)
	        mounted=$(mount | grep /backup/repository)
        	if [ -z "$mounted" ]; then
			if [ -z $devicesel ]; then
				dialog --title "Warning" --msgbox "Please, select a device first." 0 0
			else
				dialog --title "Warning" --yesno "This action will destroy all data in $devicesel. Do you want really use $devicesel as repository?" 0 0 2>&1 >/dev/tty
				if [ $? -eq 0 ]; then
					echo -e "\e[1;97;44m"
					clear
					format_device 80
					sleep 1
					mount_device
					devicesel=""
					sleep 2
					echo -e "\e[0m"
					clear
		                        exectime=$(dialog --inputbox "Enter hour for daily snaps execution" 0 0 "HH:MM" 2>&1 >/dev/tty)
				        if [[ ! $exectime =~ ^([0-1][1-9]|[2[0-3])\:([0-5][0-9])$ ]]; then
       						dialog --title "Warning" --msgbox "Entered time is not valid!" 0 0
						exectime=""
				        else
						exechour=$(echo $exectime | cut -d":" -f1)
						execmin=$(echo $exectime | cut -d":" -f2)
						echo "$execmin	$exechour	*	*	*	/usr/local/bin/mk_snap.sh" >>/var/spool/cron/crontabs/root 	
						systemctl restart cron
					fi
				fi
			fi
		else
			dialog --title "ERROR" --msgbox "Disk repository is already mounted. For security reasons this action only can be done once." 0 0
		fi
		
	;;
	7)
	        mounted=$(mount | grep /backup/repository)
        	if [ -z "$mounted" ]; then
			if [ -z $devicesel ]; then
				dialog --title "Warning" --msgbox "Please, select a device first." 0 0
			else
				dialog --title "Warning" --yesno "This action will destroy all data in $devicesel. Do you want really use $devicesel as repository?" 0 0 2>&1 >/dev/tty
				if [ $? -eq 0 ]; then
					echo -e "\e[1;97;44m"
					clear
					format_crypt_device 80
					sleep 1
					mount_crypt_device
					devicesel=""
					sleep 2
					echo -e "\e[0m"
					clear
		                        exectime=$(dialog --inputbox "Enter hour for daily snaps execution" 0 0 "HH:MM" 2>&1 >/dev/tty)
				        if [[ ! $exectime =~ ^([0-1][1-9]|[2[0-3])\:([0-5][0-9])$ ]]; then
       						dialog --title "Warning" --msgbox "Entered time is not valid!" 0 0
						exectime=""
				        else
						exechour=$(echo $exectime | cut -d":" -f1)
						execmin=$(echo $exectime | cut -d":" -f2)
						echo "$execmin	$exechour	*	*	*	/usr/local/bin/mk_snap.sh" >>/var/spool/cron/crontabs/root 	
					fi
				fi
			fi
		else
			dialog --title "ERROR" --msgbox "Disk repository is already mounted. For security reasons this action only can be done once." 0 0
		fi
		
	;;

	0)
		exit
	;;
	*)
	;;
	esac
done
}

# Main loop, to return to menu after an option
while [ true ];
do
	show_menu
done
