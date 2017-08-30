#!/bin/bash

usage() {
  cat <<EOF
  Usage: $0 [options]
    -h print usage
    -b Bucket where scripts/templates are stored
EOF
  echo 1
  exit 1
}

while getopts ":b:" o; do
    case "${o}" in
        b)
            BUILD_BUCKET=${OPTARG}
            ;;
        *)
            usage
            ;;
    esac
done

shift $((OPTIND-1))
[[ $# -gt 0 ]] && usage;

DOWNLOADLINK="https://${BUILD_BUCKET}.s3.amazonaws.com"

wget ${DOWNLOADLINK}/scripts/sap-app-pas-install-hosts.sh --output-document=/root/install/sap-app-pas-install-hosts.sh
wget ${DOWNLOADLINK}/scripts/sap-app-pas-install-single-hosts.sh --output-document=/root/install/sap-app-pas-install-single-hosts.sh
wget ${DOWNLOADLINK}/scripts/cleanup.sh --output-document=/root/install/cleanup.sh
wget ${DOWNLOADLINK}/scripts/signal-complete.sh --output-document=/root/install/signal-complete.sh
wget ${DOWNLOADLINK}/scripts/signal-failure.sh --output-document=/root/install/signal-failure.sh
wget ${DOWNLOADLINK}/scripts/interruptq.sh --output-document=/root/install/interruptq.sh
wget ${DOWNLOADLINK}/scripts/os.sh --output-document=/root/install/os.sh
wget ${DOWNLOADLINK}/scripts/signalFinalStatus.sh --output-document=/root/install/signalFinalStatus.sh
wget ${DOWNLOADLINK}/scripts/writeconfig.sh --output-document=/root/install/writeconfig.sh
wget ${DOWNLOADLINK}/scripts/create-attach-volume.sh --output-document=/root/install/create-attach-volume.sh
wget ${DOWNLOADLINK}/scripts/configureVol.sh --output-document=/root/install/configureVol.sh
wget ${DOWNLOADLINK}/scripts/create-attach-single-volume.sh --output-document=/root/install/create-attach-single-volume.sh
dos2unix /root/install/sap-app-pas-install-hosts.sh
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
	echo 1
	exit 1
else
	sleep 60
	cd /root/install
	bash -x /root/install/sap-app-pas-install-single-hosts.sh | tee -a /root/install/sap-app-pas-install-single-hosts-out.log
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

