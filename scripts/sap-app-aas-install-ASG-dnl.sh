#!/bin/bash -vx

mkdir -p /root/install

chmod 500 /root/install/*

#SUSE bug that causes long login times
#stop dbus daemon
pkill dbus
#mv the dbus socket to a temp name
mv /var/run/dbus/system_bus_socket /var/run/dbus/system_bus_socket.bak

if [ ! -s /root/install/sap-app-aas-install-ASG.sh ]
then
	echo "Download of /root/install/sap-app-aas-install-ASG.sh file not successfull"
	echo "exiting..."
	mv /var/run/dbus/system_bus_socket.bak /var/run/dbus/system_bus_socket 
	echo 1
	exit 1
else
	cd /root/install
	bash -x /root/install/sap-app-aas-install-ASG.sh | tee -a /root/install/sap-app-aas-install-ASG.sh-out.log
	if [ $? -ne 0 ] 
	then
		echo 1
		exit 1
	else
		mv /var/run/dbus/system_bus_socket.bak /var/run/dbus/system_bus_socket 
		echo 0
		exit 0
	fi
fi
