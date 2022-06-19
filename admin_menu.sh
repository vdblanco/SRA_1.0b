#!/bin/bash

# Function for change SSH listen port
change_ssh_port() {
exit=0
while [ -z $port ] && [ $exit -eq 0 ]; do
        port=$(dialog --inputbox "SSH port" 0 0 "" 2>&1 >/dev/tty)
        if [ $? -eq 1 ]; then
                exit=1
        fi
        # Accepted ports are only 22 in the well-known ports list and >1023
        if [[ $port =~ ^[0-9]{2,5}$ ]] && ( [ $port -gt 1023 ] || [ $port -eq 22 ] ); then
                actport=$(grep Port /etc/ssh/sshd_config | grep -v Ports | cut -d" " -f2)
                sudo /usr/bin/sed -i "s/Port\ $actport/Port\ $port/g" /etc/ssh/sshd_config
                sudo /usr/bin/firewall-cmd --zone=public --add-port=$port/tcp --permanent >/dev/null
                sudo /usr/bin/firewall-cmd --zone=public --remove-port=$actport/tcp --permanent >/dev/null
                sudo /usr/bin/firewall-cmd --reload >/dev/null
                sudo /usr/bin/systemctl restart ssh >/dev/null
        else
                if [ $exit -eq 0 ]; then
                        dialog --title "Warning" --msgbox "Entered port is not valid!" 0 0
                fi
                port=""
        fi
done
port=""
}

# Function to set Date & Hour
time_setup() {
exit=0
while [ -z $nowdate ] && [ $exit -eq 0 ]; do
	nowdate=$(dialog --inputbox "Enter date in mm/dd/yyyy format" 0 0 "" 2>&1 >/dev/tty)
	if [ $? -eq 1 ]; then
		exit=1
	fi
	#To do: Next does not take in account each month number of days, every month 31 days
	if [[ ! $nowdate =~ ^(0[1-9]|1[0-2])\/(0[1-9]|[1-2][0-9]|3[0-1])\/(2[0-9]{3})$ ]]; then
		dialog --title "Warning" --msgbox "Entered date is not valid!" 0 0
		nowdate=""
	fi
done
while [ -z $nowtime ] && [ $exit -eq 0 ]; do
	nowtime=$(dialog --inputbox "Enter time in HH:MM:SS format" 0 0 "" 2>&1 >/dev/tty)
	if [ $? -eq 1 ]; then
		exit=1
	fi
	if [[ ! $nowtime =~ ^([0-1][1-9]|[2[0-3])\:([0-5][0-9])\:([0-5][0-9])$ ]]; then
		dialog --title "Warning" --msgbox "Entered time is not valid!" 0 0
		nowtime=""
	else
		sudo /usr/bin/date -s "$nowdate $nowtime"
	fi
done
}

# Function to enable emergency access during a while
emergency_access() {
if [ -f /etc/ssh/sshd_config_112 ]; then
	dialog --yesno "Enable emergency SSH port? Please confirm" 0 0 2>&1 >/dev/tty
	if [ $? -eq 0 ]; then
		#Need to know SSH configured port
		port=$(grep Port /etc/ssh/sshd_config_112 | grep -v Ports | cut -d" " -f2)
		dialog --title "Warning" --msgbox "Listen port will be opened during 5 minutes, enter to start" 0 0
		sudo /usr/sbin/sshd -f /etc/ssh/sshd_config_112
		sudo /usr/bin/firewall-cmd --zone=public --add-port=$port/tcp 
		for index in {1..300}; do
			progress=$(expr $index / 3)
			echo $progress | dialog --gauge "SSH listen on emergency port, time to finish:" 10 50 0
			sleep 1
		done	
		sudo /usr/bin/kill $(pgrep -f 'ssh.*-f')
		sudo /usr/bin/firewall-cmd --zone=public --remove-port=$port/tcp 
	fi
else
	dialog --title "Error" --msgbox "SSH emergency access is not enabled on this host!" 0 0
fi
}

# Function to clear screen and draw menu
show_menu() {
#Text definitions for menu
menu=(dialog --menu "Server administration" 0 0 0 )
options=(0 "Extend repository partition"
1 "Advanced network config"
2 "Edit /etc/hosts"
3 "Time and date change"
4 "Change admin password"
5 "View/mount Backup partition snapshots (If enabled)"
6 "Change SSH listen port"
7 "Start/stop SSH"
8 "Start/stop NFS"
9 "Start/stop SMB"
E "Temporary enable SSH emergency access (If enabled)"
U "Update packages from repository"
Q "Quit")

#Create menu
options=$("${menu[@]}" "${options[@]}" 2>&1 >/dev/tty)
if [ $? -eq 1 ]; then
	exit 0
fi

clear

for option in $options
do
	case $option in
	0)
		dialog --title "Warning" --yesno "This option requieres that the disk has been previously extended. OK to rescan disk?" 0 0
		if [ $? -eq 0 ]; then
			sudo /usr/local/bin/extend_disk.sh
		fi
	;;
	1)
		sudo /usr/bin/nmtui
	;;

	2)
		echo -e "\e[1;97;44m"	
		clear
		cp /etc/hosts /tmp/hosts
		nano /tmp/hosts
		sudo /usr/bin/sed -n "w/etc/hosts" /tmp/hosts 	
		rm -f /tmp/hosts
		echo -e "\e[0m"
		clear
	;;
	3)
		time_setup
	;;
	4)
		echo -e "\e[1;97;44m"	
		clear
		echo "Changing admin user password"
		passwd admin
		echo -e "\e[0m"
		clear
	;;
	5)
		sudo /usr/local/bin/mount_snapshot.sh
	;;
	6)
		change_ssh_port
	;;
	7)
		#Need to know SSH configured port
		port=$(grep Port /etc/ssh/sshd_config | grep -v Ports | cut -d" " -f2)
		status=$(sudo /usr/bin/systemctl status ssh | grep Active: | awk '{ print $2 }')
		if [ $status == "inactive" ]; then
			perm=$(dialog --title "Service status" --checklist "SSH service is stopped. Press OK to start it" 0 0 0 "Permanent" "*" off 2>&1 >/dev/tty)
                	if [ $? -eq 0 ]; then
				sudo /usr/bin/systemctl start ssh >/dev/null
		                sudo /usr/bin/firewall-cmd --add-port=$port/tcp >/dev/null
				if [ "$perm" == "Permanent" ]; then
					sudo /usr/bin/systemctl enable ssh 2>&1 >/dev/null
		                	sudo /usr/bin/firewall-cmd --add-port=$port/tcp --permanent >/dev/null
				fi
			fi
		else
			if [ $status == "active" ]; then
				perm=$(dialog --title "Service status" --checklist "SSH service is started. Press OK to stop it" 0 0 0 "Permanent" "*" off 2>&1 >/dev/tty)
	                        if [ $? -eq 0 ]; then
       					sudo /usr/bin/systemctl stop ssh >/dev/null
		                	sudo /usr/bin/firewall-cmd --remove-port=$port/tcp >/dev/null
					if [ "$perm" == "Permanent" ]; then
       						sudo /usr/bin/systemctl disable ssh 2>&1 >/dev/
			                	sudo /usr/bin/firewall-cmd --remove-port=$port/tcp --permanent >/dev/null
					fi
                        	fi
			else
				dialog --title "ERROR" --msgbox "SSH service is in unknown state!" 0 0
			fi
		fi
	;;
	8)
		status=$(sudo /usr/bin/systemctl status nfs-server | grep Active: | awk '{ print $2 }')
		if [ $status == "inactive" ]; then
			perm=$(dialog --title "Service status" --checklist "NFS service is stopped. Press OK to start it" 0 0 0 "Permanent" "*" off 2>&1 >/dev/tty)
			if [ $? -eq 0 ]; then
				sudo /usr/bin/systemctl start nfs-server >/dev/null
		               	sudo /usr/bin/firewall-cmd --add-service=nfs >/dev/null
				if [ "$perm" == "Permanent" ]; then
					sudo /usr/bin/systemctl enable nfs-server >/dev/null
		                	sudo /usr/bin/firewall-cmd --add-service=nfs --permanent >/dev/null
				fi
			fi
		else
			if [ $status == "active" ]; then
				perm=$(dialog --title "Service status" --checklist "NFS service is started. Press OK to stop it" 0 0 0 "Permanent" "*" off 2>&1 >/dev/tty)
	                        if [ $? -eq 0 ]; then
       					sudo /usr/bin/systemctl stop nfs-server >/dev/null
		                	sudo /usr/bin/firewall-cmd --remove-service=nfs >/dev/null
					if [ "$perm" == "Permanent" ]; then
       						sudo /usr/bin/systemctl disable nfs-server >/dev/null
		                		sudo /usr/bin/firewall-cmd --remove-service=nfs --permanent >/dev/null
					fi		
                        	fi
			else
				dialog --title "ERROR" --msgbox "NFS service is in unknown state!" 0 0
			fi
		fi
	;;
	9)
		status=$(sudo /usr/bin/systemctl status smbd | grep Active: | awk '{ print $2 }')
		if [ $status == "inactive" ]; then
			perm=$(dialog --title "Service status" --checklist "SMB service is stopped. Press OK to start it" 0 0 0 "Permanent" "*" off 2>&1 >/dev/tty)
                       if [ $? -eq 0 ]; then
				sudo /usr/bin/systemctl start smbd >/dev/null
		                sudo /usr/bin/firewall-cmd --add-service=samba >/dev/null
				if [ "$perm" == "Permanent" ]; then
					sudo /usr/bin/systemctl enable smbd >/dev/null
		                	sudo /usr/bin/firewall-cmd --add-service=samba --permanent  >/dev/null
				fi
			fi
		else
			if [ $status == "active" ]; then
				perm=$(dialog --title "Service status" --checklist "SMB service is started. Press OK to stop it" 0 0 0 "Permanent" "*" off 2>&1 >/dev/tty)
	                        if [ $? -eq 0 ]; then
       					sudo /usr/bin/systemctl stop smbd >/dev/null
			                sudo /usr/bin/firewall-cmd --remove-service=samba >/dev/null
					if [ "$perm" == "Permanent" ]; then
       						sudo /usr/bin/systemctl disable smbd >/dev/null
			                	sudo /usr/bin/firewall-cmd --remove-service=samba --permanent >/dev/null
					fi
                        	fi
			else
				dialog --title "ERROR" --msgbox "SMB service is in unknown state!" 0 0
			fi
		fi
	;;
	E)
		emergency_access
	;;
	U)
		echo -e "\e[1;97;44m"	
		clear
		aptget=$(sudo apt-get update | grep Err:)
		if [ ! -z $aptget ]; then
			sudo apt-get -y upgrade
		else
			dialog --title "Network Proxy" --yesno "Some problem detected connecting to repository, press Yes if you want to config a Network Proxy" 0 0
                        if [ $? -eq 0 ]; then
			        proxy=$(dialog --inputbox "Enter proxy in http(s)://user:password@ip_or_FQDN:port format" 0 0 "" 2>&1 >/dev/tty)

				echo "Acquire::http::Proxy \"$proxy\"\;" >/tmp/apt.conf
                		sudo /usr/bin/sed -n "w/etc/apt/apt.conf" /tmp/apt.conf
		                rm -f /tmp/apt.conf
				clear
				sudo apt-get update
				sudo apt-get -y upgrade
			else
				dialog --title "ERROR" --dialogbox "There were errors connecting to repository. Update/upgrade is not possible." 0 0
			fi
		fi
		echo -e "\e[0m"
		clear
	;;
	Q)
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
