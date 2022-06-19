#!/bin/bash

# Function to change network settings
network_setup() {
address=""

#Dialog menus
exit=0
while [ -z $address ] && [ $exit -eq 0 ]; do
	address=$(dialog --inputbox "Network address with mask (xxx.xxx.xxx.xxx/xx format)" 0 0 "" 2>&1 >/dev/tty)
	if [ $? -eq 1 ]; then
		exit=1
	fi
	if [[ $address =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\/([0-9]|[1-2][0-9]|3[0-2])$ ]]; then
		for i in {1..4}; do
			if [ $(echo "$address" |  cut -d. -f$i) -gt 255 ]; then
				dialog --title "Warning" --msgbox "Entered IP is not valid!" 0 0
				address=""
			fi
		done
		if [ ! -z $address ]; then
			gateway=$(dialog --inputbox "Network gateway" 0 0 "$(echo "$address" | cut -d. -f1,2,3)" 2>&1 >/dev/tty)
			if [ $? -eq 1 ]; then
				exit=1
			fi
		fi
	else
		if [ $exit -eq 0 ]; then
			dialog --title "Warning" --msgbox "Entered IP is not valid!" 0 0
		fi
		address=""
	fi
done

if [ $exit -eq 0 ]; then 
	device=$(nmcli dev status | grep ethernet | awk '{ print $1 }')
	confaddress=$(nmcli --field ipv4.addresses connection show "Wired connection 1")
	if [ -z $confaddress ]; then
		nmcli con add type ethernet con-name "Wired connection 1" ifname $device ip4 $address gw4 $gateway &>/dev/null
	else
		nmcli con mod "Wired connection 1" ipv4.addresses $address &>/dev/null
		nmcli con mod "Wired connection 1" ipv4.gateway $gateway &>/dev/null
	fi

	#Power up interface
	nmcli networking off &>/dev/null
	nmcli networking on &>/dev/null
fi
}

# Function to change hostname & DNS
dns_setup() {
address=$(nmcli --field ipv4.addresses connection show "Wired connection 1" | awk '{ print $2 }' | cut -d"/" -f1)
exit=0
if [ ! -z $address ]; then
	hostname=$(dialog --inputbox "FQDN hostname" 0 0 "" 2>&1 >/dev/tty)
	if [ $? -eq 1 ]; then
		exit=1
	else
		grep -v $hostname /etc/hosts >/tmp/hosts
		cat /tmp/hosts > /etc/hosts
		rm /tmp/hosts
		hostnamectl set-hostname $hostname 
		domain=$(echo $hostname | cut -d. -f2,3)
	fi
	while [ -z $DNSs ] && [ $exit -eq 0 ]; do
		DNSs=$(dialog --inputbox "DNS(s), one or two separated by comma" 0 0 "" 2>&1 >/dev/tty)
		if [ $? -eq 1 ]; then
			exit=1
		fi

		if [[ $DNSs =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]] || \
			[[ $DNSs =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\,[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
				DNS1=$(echo $DNSs | cut -d, -f1)
				DNS2=$(echo $DNSs | grep "," | cut -d, -f2 | tr -d ' ')
		else
			dialog --title "Warning" --msgbox "Entered DNS(s) are not valid!" 0 0
			DNSs=""
		fi
	done
	if [ $exit -eq 0 ]; then
		if [ ! -z $DNS2 ]; then
			nmcli con mod "Wired connection 1" ipv4.dns "$DNS1 $DNS2" &>/dev/null
		else
			nmcli con mod "Wired connection 1" ipv4.dns "$DNS1" >/dev/null
		fi
		if [ ! -z $domain ]; then
			nmcli con mod "Wired connection 1" ipv4.dns-search "$domain" &>/dev/null
			echo "
#Added by secure repo config
$address $hostname $(echo $hostname | cut -d. -f1)" >>/etc/hosts
		else
			echo "
#Added by secure repo config
$address $hostname" >>/etc/hosts
		fi
	fi
else
	dialog --title "Warning" --msgbox "Please configure network first" 0 0
fi
}  

# Function to change date & time
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
	if [[ ! $nowtime =~ ^([0-1][0-9]|[2[0-3])\:([0-5][0-9])\:([0-5][0-9])$ ]]; then
		dialog --title "Warning" --msgbox "Entered time is not valid!" 0 0
		nowtime=""
	else
		date -s "$nowdate $nowtime"
	fi
done

if [ $exit -eq 0 ]; then
	ntpserver=$(dialog --inputbox "Enter NTP server (Optional)" 0 0 "" 2>&1 >/dev/tty)
	if [ $? -eq 0 ] && [ ! -z $ntpserver ]; then
		echo "NTP=$ntpserver" >>/etc/systemd/timesyncd.conf
		systemctl enable systemd-timesyncd
		systemctl restart systemd-timesyncd
	fi
fi
}
	

# Function to clear screen and draw menu
show_menu() {
#Text definitions for menu
menu=(dialog --menu "Server first setup" 0 0 0 )
options=(1 "Network setup" 
2 "Hostname and DNS setup"
3 "Time and zone setup"
4 "Change keyboard layout"
5 "Repository disk setup"
6 "Security and services setup"
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
	1)
		network_setup	
	;;

	2)
		dns_setup
	;;
	3)
		dpkg-reconfigure tzdata
		time_setup
	;;
	4)
		dpkg-reconfigure keyboard-configuration
	;;
	5)
		/usr/local/bin/disk_setup.sh	
        ;;
	6)
		/usr/local/bin/access_setup.sh
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
