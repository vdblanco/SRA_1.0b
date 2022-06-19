#!/bin/bash

# Function for change SSH listen port
change_port() {
exit=0
while [ -z $port ] && [ $exit -eq 0 ]; do
        port=$(dialog --inputbox "SSH port" 0 0 "" 2>&1 >/dev/tty)
        if [ $? -eq 1 ]; then
                exit=1
        fi
	# Accepted ports are only 22 in the well-known ports list and >1023
        if [[ $port =~ ^[0-9]{2,5}$ ]] && ( [ $port -gt 1023 ] || [ $port -eq 22 ] ); then
		actport=$(grep Port /etc/ssh/sshd_config | grep -v Ports | cut -d" " -f2)
		sed -i "s/Port\ $actport/Port\ $port/g" /etc/ssh/sshd_config
		firewall-cmd --zone=public --add-port=$port/tcp --permanent &>/dev/null	
		firewall-cmd --zone=public --remove-port=$actport/tcp --permanent &>/dev/null
		firewall-cmd --reload &>/dev/null
		systemctl restart ssh >/dev/null
        else
                if [ $exit -eq 0 ]; then
                        dialog --title "Warning" --msgbox "Entered port is not valid!" 0 0
                fi
                port=""
        fi
done
port=""
}

# Function for restric access from an IP or network
restrict_access() {
exit=0
IPvalid=0
while [ -z $auth_host ] && [ $exit -eq 0 ]; do
	auth_host=$(dialog --inputbox "Enter authorized IP (xxx.xxx.xxx.xxx) or Network (xxx.xxx.xxx.xxx/xx) for SSH access" 0 0 "" 2>&1 >/dev/tty)
	if [ $? -eq 1 ]; then
		exit=1
	else
		isIPvalid $auth_host
	        if [ $IPvalid  -eq 1 ]; then
			dialog --title "Warning" --yesno "You are going to restrict SSH conections. Only $auth_host will be authorized. An error in this configuration will isolate $(hostname), you can access only from console " 0 0
			if [ $? -eq 0 ]; then
				port=$(grep Port /etc/ssh/sshd_config | grep -v Ports | cut -d" " -f2)
				firewall-cmd --zone=trusted --add-port=$port/tcp --permanent &>/dev/null	
				firewall-cmd --zone=trusted --add-source=$auth_host --permanent &>/dev/null
				firewall-cmd --zone=public --remove-port=$port/tcp --permanent &>/dev/null
				firewall-cmd --reload &>/dev/null
			fi
		else
			auth_host=""
			IPvalid=0
		fi
	fi
done
auth_host=""
}  


# Function for enable emergency access on desired port
emergency_access() {
exit=0
port=""
while [ -z $port ] && [ $exit -eq 0 ]; do
        port=$(dialog --inputbox "Emergency SSH port" 0 0 "11222" 2>&1 >/dev/tty)
        if [ $? -eq 1 ]; then
                exit=1
        fi
	# Accepted ports are only 22 in the well-known ports list and >1023
        if [[ $port =~ ^[0-9]{2,5}$ ]] && [ $port -gt 1023 ]; then
		echo "Port $port 
PermitRootLogin no
MaxAuthTries 3
MaxSessions 1
PubkeyAuthentication no
AcceptEnv LANG LC_*
AllowUsers userrepo
DenyUsers admin" >/etc/ssh/sshd_config_112

        else
                if [ $exit -eq 0 ]; then
                        dialog --title "Warning" --msgbox "Entered port is not valid!" 0 0
                fi
                port=""
        fi
done
port=""
}

# Function to validate an IP
isIPvalid() {
indice=1
bucle=1
if [[ $1 =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]] || [[ $1 =~ ^([0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3})\/([0-9]|[1-2][0-9]|3[0-2]) ]]; then
	while [ $bucle -eq 1 ] && [ $indice -le 4 ]; do
		if [ $(echo "$1" |  cut -d. -f$indice) -gt 255 ]; then
			dialog --title "Warning" --msgbox "Entered IP is not valid!" 0 0
			IPvalid=0
			bucle=0
		else
			IPvalid=1
			indice=$(expr $indice + 1)
		fi
	done
else
	dialog --title "Warning" --msgbox "Entered IP is not valid!" 0 0
	IPvalid=0
fi
}

# Function to get number of days for backup files immutability and write task to cron
setinmujob() {
if [ -z $(crontab -l | grep set_attrib.sh) ] && [ -z $(ps -fe | grep veeamimmureposvc | grep -v grep) ]; then
	days=$(dialog --inputbox "Number of days for backup files immutability" 0 0 "" 2>&1 >/dev/tty)
	if [ $? -eq 0 ]; then
  		if [[ $days =~ ^[1-9][0-9]{0,2}$ ]]; then
			echo "00      *       *       *       *       /usr/local/bin/set_attrib.sh $days" >>/var/spool/cron/crontabs/root
			systemctl restart cron
		fi
	fi
fi
}	

# Function to change sshd settigss when server is ready to secure it - Only login with admin user
setsshsecure() {
sed -i '/^PermitRootLogin/s/yes/no/' /etc/ssh/sshd_config
sed -i '/^DenyUsers/s/admin/userrepo/' /etc/ssh/sshd_config
sed -i '/^root:/s/\/local\/bin\/first_setup.sh/\/sbin\/nologin/' /etc/passwd
systemctl restart ssh
}

# Function to clear screen and draw menu
show_menu() {
#Text definitions for menu
menu=(dialog --menu "Security setup" 0 0 0 )
options=(1 "Change SSH port" 
2 "Restrict access (only from one host or network)"
3 "Change all user passwords"
4 "Configure host as Veeam Backup repository"
5 "Configure host as NFS repository"
6 "Configure host as SMB repository"
7 "Enable emergency access"
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
		change_port
	;;
	2)
		restrict_access
	;;
        3)
                echo -e "\e[1;97;44m"
                clear
                echo "Changing root pasword:"
                passwd root
                echo "Changing admin pasword:"
                passwd admin
                echo "Changing userrepo pasword:"
                passwd userrepo
                echo -e "\e[0m"
                clear
        ;;
	4)
		clear
		exit=0
		while [ $exit -eq 0 ]; do
			pid=$(ps -fea | grep "veeamimmureposvc" | grep -v grep)
       		 	if [ "$pid" = "" ]
		        then
                		echo -e "\e[1;97;44m"
                		clear
		                echo "Waiting for Veeam Backup Process...."
				sleep 5
        		else
				echo "Detected Veeam Backup agent"
				setsshsecure
                		echo -e "\e[0m"
                		clear
				exit=1
			fi
			
		done

	;;
	5)
		IPvalid=0
		exit=0	
		enableNFS=0
		auth_hosts_list=""
		while [ $exit -eq 0 ]; do
			auth_host=$(dialog --inputbox "Enter authorized IP(s) for NFS access(Until cancel)" 0 0 "" 2>&1 >/dev/tty)
			if [ $? -eq 1 ]; then
				exit=1 
				IPvalid=0
			else
				isIPvalid $auth_host
			fi	
			if [ $IPvalid  -eq 1 ]; then
				auth_hosts_list="$auth_hosts_list $auth_host(rw,sync,no_subtree_check,no_root_squash)"
				enableNFS=1
			fi
		done
		if [ $enableNFS -eq 1 ]; then
			echo -e "\e[1;97;44m"
	                clear
			echo "/backup/repository      $auth_hosts_list" >> /etc/exports
			systemctl enable nfs-server >/dev/null
			systemctl start nfs-server >/dev/null
			firewall-cmd --add-service=nfs --permanent &>/dev/null
			firewall-cmd --reload &>/dev/null
			setinmujob
			setsshsecure
		fi
               	echo -e "\e[0m"
                clear
	;;
	6)
		IPvalid=0
		exit=0	
		enableSMB=0
		auth_hosts_list=""
		while [ $exit -eq 0 ]; do
			auth_host=$(dialog --inputbox "Enter authorized IP(s) for SMB access(Until cancel)" 0 0 "" 2>&1 >/dev/tty)
			if [ $? -eq 1 ]; then
				exit=1 
				IPvalid=0
			else
				isIPvalid $auth_host
			fi	
			if [ $IPvalid  -eq 1 ]; then
				auth_hosts_list="$auth_hosts_list $auth_host"
				enableSMB=1
			fi
		done
		if [ $enableSMB -eq 1 ]; then
			echo -e "\e[1;97;44m"
			clear
			echo "   allow hosts = $auth_hosts_list" >> /etc/samba/smb.conf
			systemctl enable smbd >/dev/null
			systemctl start smbd >/dev/null
			firewall-cmd --add-service=samba --permanent &>/dev/null
			firewall-cmd --reload &>/dev/null
			setinmujob
			setsshsecure
		fi
                echo -e "\e[0m"
                clear

        ;;
	7)
		emergency_access
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

