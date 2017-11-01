#!/bin/bash -xv

dos2unix /root/install/sap-app-pas-install-single-hosts.sh

chmod 500 /root/install/*

#SUSE bug that causes long login times
#stop dbus daemon
pkill dbus
#mv the dbus socket to a temp name
mv /var/run/dbus/system_bus_socket /var/run/dbus/system_bus_socket.bak

if [ ! -s /root/install/sap-app-pas-install-single-hosts.sh ]
then
	echo "Download of /root/install/sap-app-pas-install-single-hosts.sh file not successfull"
	echo "exiting..."
	mv /var/run/dbus/system_bus_socket.bak /var/run/dbus/system_bus_socket 
	 /root/install/signalFinalStatus.sh 1 "Download-script not found...check: /root/install/sap-app-pas-install-single-hosts.sh"
	echo 1
	exit 1
else
	if [[ "$REGION" == "ap-south-1" -o "$REGION" == "ap-southeast-1"  -o "$REGION" == "ap-northeast-2"  -o "$REGION" == "us-west-2"  -o "$REGION" == "us-east-1" ]]	
	then
		sleep 30
		cd /root/install
		bash -x /root/install/sap-app-pas-install-single-hosts.sh | tee -a /root/install/sap-app-pas-install-single-hosts-out.log
		if [ $? -ne 0 ] 
		then
	 		/root/install/signalFinalStatus.sh 1 "Install-script did not execute correctly...check: /var/log directories for error message"
			echo 1
			exit 1
		else
			mv /var/run/dbus/system_bus_socket.bak /var/run/dbus/system_bus_socket 
			echo 0
			exit 0
		fi
	else
		#temporary CFN init testing...just quickly post success and exit
		/root/install/signalFinalStatus.sh 0 "Download-script found...exiting from PAS download script without installing"
		exit
	fi
fi

