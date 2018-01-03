#!/bin/bash -x


#

#   This code was written by somckitk@amazon.com.
#   This sample code is provided on an "AS IS" BASIS,
#   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.

#

###Global Variables###
source /root/install/config.sh
TZ_LOCAL_FILE="/etc/localtime"
NTP_CONF_FILE="/etc/ntp.conf"
USR_SAP="/usr/sap"
SAPMNT="/sapmnt"
USR_SAP_DEVICE="/dev/xvdb"
FSTAB_FILE="/etc/fstab"
DHCP="/etc/sysconfig/network/dhcp"
CLOUD_CFG="/etc/cloud/cloud.cfg"
IP=$(curl http://169.254.169.254/latest/meta-data/local-ipv4/)
HOSTS_FILE="/etc/hosts"
HOSTNAME_FILE="/etc/HOSTNAME"
NETCONFIG="/etc/sysconfig/network/config"
ETC_SVCS="/etc/services"
SERVICES_FILE="/sapmnt/SWPM/services"
AUTO_MASTER="/etc/auto.master"
AUTO_DIRECT="/etc/auto.direct"
PRODUCT="NW_DI:NW740SR2.HDB.PIHA"
INI_FILE="/sapmnt/SWPM/APPX_D00_Linux_HDB.params"
SAPINST="/sapmnt/SWPM/sapinst"
SW_TARGET="/sapmnt/SWPM"
REGION=$(curl http://169.254.169.254/latest/dynamic/instance-identity/document/ | grep -i region | awk '{ print $3 }' | sed 's/"//g' | sed 's/,//g')
MASTER_HOSTS="/sapmnt/SWPM/master_etc_hosts"
#
###  Variables below need to be CUSTOMIZED for your environment  ###


#
_TEMP_NAME=$(echo $NAME | cut -c1-3)
#Do not quote the TEMP_NAME variable...doing so will preseve the "\"...which we don't want
#USE a last random number
RAND=$(expr $RANDOM % 100)
TEMP_NAME=$_TEMP_NAME\temp"$RAND"
TEMP_NAME_NR=$_TEMP_NAME\temp
NUMBER_COUNT=2

###Functions###


set_tz() {
#set correct timezone per CF parameter input

        rm "$TZ_LOCAL_FILE"

        case "$TZ_INPUT_PARAM" in
        PT)
                TZ_ZONE_FILE="/usr/share/zoneinfo/US/Pacific"
                ;;
        CT)
                TZ_ZONE_FILE="/usr/share/zoneinfo/US/Central"
                ;;
        ET)
                TZ_ZONE_FILE="/usr/share/zoneinfo/US/Eastern"
                ;;
        *)
                TZ_ZONE_FILE="/usr/share/zoneinfo/UTC"
                ;;
        esac

        ln -s "$TZ_ZONE_FILE" "$TZ_LOCAL_FILE"

        #validate correct timezone
        CURRENT_TZ=$(date +%Z | cut -c 1,3)

        if [ "$CURRENT_TZ" == "$TZ_INPUT_PARAM" -o "$CURRENT_TZ" == "UC" ]
        then
                echo 0
        else
                echo 1
        fi
}

set_oss_configs() {

    #This section is from OSS #2205917 - SAP HANA DB: Recommended OS settings for SLES 12 / SLES for SAP Applications 12
    #and OSS #2292711 - SAP HANA DB: Recommended OS settings for SLES 12 SP1 / SLES for SAP Applications 12 SP1

    zypper remove ulimit > /dev/null


    echo "###################" >> /etc/init.d/boot.local
    echo "#BEGIN: This section inserted by AWS SAP Quickstart" >> /etc/init.d/boot.local

    #Disable THP
    echo never > /sys/kernel/mm/transparent_hugepage/enabled
    echo "echo never > /sys/kernel/mm/transparent_hugepage/enabled" >> /etc/init.d/boot.local

    echo 10 > /proc/sys/vm/swappiness
    echo "echo 10 > /proc/sys/vm/swappiness" >> /etc/init.d/boot.local

    #Disable KSM
    echo 0 > /sys/kernel/mm/ksm/run
    echo "echo 0 > /sys/kernel/mm/ksm/run" >> /etc/init.d/boot.local

    #NoHZ is not set

    #Disable AutoNUMA
    echo 0 > /proc/sys/kernel/numa_balancing
    echo "echo 0 > /proc/sys/kernel/numa_balancing" >> /etc/init.d/boot.local

    #Increase max open files
    echo 1048576 > /proc/sys/fs/nr_open
    echo "echo 1048576 > /proc/sys/fs/nr_open" >> /etc/init.d/boot.local

    zypper -n install gcc

    zypper install libgcc_s1 libstdc++6

    echo "#END: This section inserted by AWS SAP HANA Quickstart" >> /etc/init.d/boot.local
    echo "###################" >> /etc/init.d/boot.local
}

set_awsdataprovider() {
#install the AWS dataprovider require for AWS support

	cd /tmp
        aws s3 cp s3://aws-data-provider/bin/aws-agent_install.sh . > /dev/null

	if [ -f /tmp/aws-agent_install.sh ]
	then
		bash /tmp/aws-agent_install.sh > /dev/null
		echo 0
	else
		echo 1
	fi
}


set_aasinifile() {
#set the vname of the database server in the INI file

	sed -i  "/hdb.create.dbacockpit.user/ c\hdb.create.dbacockpit.user = true" $INI_FILE

	#set the password from the SSM parameter store
	sed -i  "/NW_HDB_getDBInfo.systemPassword/ c\NW_HDB_getDBInfo.systemPassword = ${MP}" $INI_FILE
	sed -i  "/storageBasedCopy.hdb.systemPassword/ c\storageBasedCopy.hdb.systemPassword = ${MP}" $INI_FILE
	sed -i  "/HDB_Schema_Check_Dialogs.schemaPassword/ c\HDB_Schema_Check_Dialogs.schemaPassword = ${MP}" $INI_FILE
	sed -i  "/NW_GetMasterPassword.masterPwd/ c\NW_GetMasterPassword.masterPwd = ${MP}" $INI_FILE
     	sed -i  "/NW_HDB_getDBInfo.systemDbPassword/ c\NW_HDB_getDBInfo.systemDbPassword = ${MP}" $INI_FILE


	#set the profile directory
	sed -i  "/NW_readProfileDir.profileDir/ c\NW_readProfileDir.profileDir = /sapmnt/${SAP_SID}/profile" $INI_FILE


	#set the Schema 
	sed -i  "/HDB_Schema_Check_Dialogs.schemaName/ c\HDB_Schema_Check_Dialogs.schemaName = ${SAP_SCHEMA_NAME}" $INI_FILE

	#set the UID and GID
	sed -i  "/nwUsers.sidAdmUID/ c\nwUsers.sidAdmUID = ${SIDadmUID}" $INI_FILE
	sed -i  "/nwUsers.sapsysGID/ c\nwUsers.sapsysGID = ${SAPsysGID}" $INI_FILE

        _VAL_MP=$(grep "$MP" $INI_FILE)
	_VAL_SAP_SID=$(grep "$SAP_SID" $INI_FILE)

	if [ -n "$_VAL_MP" -a "$_VAL_SAP_SID"]
	then
		echo 0
	else
		echo 1
	fi
}

set_cleanup_aasinifile() {
#clean up the INI file after finishing the SAP install

MP="DELETED"

	sed -i  "/hdb.create.dbacockpit.user/ c\hdb.create.dbacockpit.user = true" $INI_FILE

	#set the password from the SSM parameter store
	sed -i  "/NW_HDB_getDBInfo.systemPassword/ c\NW_HDB_getDBInfo.systemPassword = ${MP}" $INI_FILE
	sed -i  "/storageBasedCopy.hdb.systemPassword/ c\storageBasedCopy.hdb.systemPassword = ${MP}" $INI_FILE
	sed -i  "/HDB_Schema_Check_Dialogs.schemaPassword/ c\HDB_Schema_Check_Dialogs.schemaPassword = ${MP}" $INI_FILE
	sed -i  "/NW_GetMasterPassword.masterPwd/ c\NW_GetMasterPassword.masterPwd = ${MP}" $INI_FILE
     	sed -i  "/NW_HDB_getDBInfo.systemDbPassword/ c\NW_HDB_getDBInfo.systemDbPassword = ${MP}" $INI_FILE

	#set the profile directory
	sed -i  "/NW_readProfileDir.profileDir/ c\NW_readProfileDir.profileDir = /sapmnt/${SAP_SID}/profile" $INI_FILE

}

set_ntp() {
#set ntp in the /etc/ntp.conf file

	cp "$NTP_CONF_FILE" "$NTP_CONF_FILE.bak"
	echo "server 0.pool.ntp.org" >> "$NTP_CONF_FILE"
	echo "server 1.pool.ntp.org" >> "$NTP_CONF_FILE"
	echo "server 2.pool.ntp.org" >> "$NTP_CONF_FILE"
	echo "server 3.pool.ntp.org" >> "$NTP_CONF_FILE"

	systemctl start ntpd
	echo "systemctl start ntpd" >> /etc/init.d/boot.local

	_COUNT_NTP=$(grep ntp "$NTP_CONF_FILE" | wc -l)

	if [ "$_COUNT_NTP" -ge 4 ]
	then
		echo 0
	else
		echo 1
	fi
}

set_install_jq () {
#install jq s/w

	cd /tmp
	wget https://github.com/stedolan/jq/releases/download/jq-1.5/jq-linux64
        mv jq-linux64 jq
        chmod 755 jq
}

set_filesystems() {
#create /usr/sap filesystem and mount /sapmnt

	#bash /root/install/create-attach-single-volume.sh "50:gp2:$USR_SAP_DEVICE:$USR_SAP" > /dev/null
	USR_SAP_VOLUME=$(lsblk | grep xvdb)

	#allocate SWAP space
	#bash /root/install/create-attach-single-volume.sh "50:gp2:/dev/xvdc:SWAP" > /dev/null

	if [ -z "$USR_SAP_VOLUME" ]
	then
		echo "Exiting, can not create $USR_SAP_DEVICE or $SAPMNT_DEVICE EBS volumes"
	        #signal the waithandler, 1=Failed
	        /root/install/signalFinalStatus.sh 1 "Exiting, can not create $USR_SAP_DEVICE or $SAPMNT_DEVICE EBS volumes"
	        set_cleanup_aasinifile
		exit 1
	else
		mkdir $USR_SAP > /dev/null 2>&1
		mkfs -t xfs $USR_SAP_DEVICE > /dev/null 2>&1
		echo "$USR_SAP_DEVICE  $USR_SAP xfs nobarrier,noatime,nodiratime,logbsize=256k 0 0" >> $FSTAB_FILE 2>&1
		mount -a > /dev/null 2>&1
		mkswap /dev/xvdc > /dev/null 2>&1
		swapon /dev/xvdc > /dev/null 2>&1
	fi

}

set_dhcp() {

	sed -i '/DHCLIENT_SET_HOSTNAME/ c\DHCLIENT_SET_HOSTNAME="no"' $DHCP

	service network restart

	_DHCP=$(grep DHCLIENT_SET_HOSTNAME $DHCP | grep no)

	if [ -n "$_DHCP" ]
	then
		echo 0
	else
		echo 1
	fi
}





set_DB_hostname() {

	#add DB hostname
	echo "$DBIP  $DBHOSTNAME" >> $HOSTS_FILE

	#add own hostname
	MY_IP=$( ip a | grep inet | grep eth0 | awk -F"/" '{ print $1 }' | awk '{ print $2 }')
	echo "${MY_IP}"    "${HOSTNAME}" >> /etc/hosts  

	#echo "$SAP_PASIP  $SAP_PAS" >> $HOSTS_FILE
	#echo "$SAP_PASIP  $SAP_PAS" >> $HOSTS_FILE
	#echo "$SAP_ASCSIP  $SAP_ASCS" >> $HOSTS_FILE
}


set_net() {
#set and preserve the hostname


	#update DNS search order with our DNS Domain name
	sed -i "/NETCONFIG_DNS_STATIC_SEARCHLIST=""/ c\NETCONFIG_DNS_STATIC_SEARCHLIST="${HOSTED_ZONE}"" $NETCONFIG

	#update the /etc/resolv.conf file
	netconfig update -f > /dev/null

	sed -i '/preserve_hostname/ c\preserve_hostname: true' $CLOUD_CFG

	#disable dhcp
	_DISABLE_DHCP=$(set_dhcp)


	if [ "$HOSTNAME" == $(hostname) ]
	then
		echo 0
	else
		echo 1
	fi
}

set_services_file() {
#update the /etc/services file with customer supplied values

	cat "$SERVICES_FILE" >> $ETC_SVCS
}

set_autofs() {
#setup NFS to mount /sapmnt from the PAS


	mkdir  $SAPMNT
        #check to see if there is already a /sapmnt entry in /etc/fstab
	_FSTAB=$(grep "$SAPMNT" /etc/fstab | wc -l )

	if [ $_FSTAB -ge 1 ]
	then
		echo 0
	else
		echo "$SAP_PAS:$SAPMNT  $SAPMNT nfs rw,soft,bg,timeo=14,intr 0 0" >> /etc/fstab 
	fi



	#PAS_EC2ID=$(aws ec2 describe-instances --region $REGION --query 'Reservations[].Instances[].[PrivateIpAddress,InstanceId]' --output text | grep "$SAP_PASIP" | awk '{ print $2 }')

        #insert the hosts file entry
	#MY_IP=$( ip a | grep inet | grep eth0 | awk -F"/" '{ print $1 }' | awk '{ print $2 }')
	#aws ssm send-command --instance-ids  $PAS_EC2ID --document-name "AWS-RunShellScript" --comment "add_host" --parameters commands="echo "${MY_IP}"    "${HOSTNAME}" >> /etc/hosts"  --region $REGION --output text


	#restart rpc.mountd on the PAS
	#aws ssm send-command --instance-ids  $PAS_EC2ID --document-name "AWS-RunShellScript" --comment "restart mountd" --parameters commands="pkill rpc.mountd; /usr/sbin/rpc.mountd" --region $REGION --output text
	

	#restart the nscd 
	#aws ssm send-command --instance-ids  $PAS_EC2ID --document-name "AWS-RunShellScript" --comment "nscd_restart" --parameters commands="service nscd restart"  --region $REGION --output text



	_DF=$(showmount -e "$SAP_PAS" | grep "$SAPMNT" | wc -l )

	#check showmount 
	if [ $_DF -eq 1 ]
	then
	        mount $SAPMNT
		echo 0
	else
		echo 1
	fi
}

set_uuidd() {
#Install the uuidd daemon per SAP Note 1391070

	zypper -n install uuidd > /dev/null 2>&1
	chkconfig uuidd on > /dev/null 2>&1
	service uuidd start > /dev/null 2>&1

        _UUIDD_RUNNING=$(ps -ef | grep uuidd | grep -v grep)

	if [ -n "$_UUIDD_RUNNING" ]
	then
		echo 0
	else
		echo 1
	fi
}

set_update_cli() {
#update the aws cli
	zypper -n install python-pip > /dev/null 2>&1

	pip install --upgrade --user awscli > /dev/null 2>&1

	_AWS_CLI=$(aws --version 2>&1)

	if [ -n "$_AWS_CLI" ]
	then
		echo 0
	else
		echo 1
	fi
}

set_ini_file () {
#set the correct SAP PARAMS file based on SAP App Server name

	HOSTNAME=$(cat /tmp/HOSTNAME)

        if [ ! -e "$INI_FILE" ]
	then
		#No template files - exit
		FNAME=$(echo $INI_FILE | awk -F"/" '{ print $4 }')
                #signal failure and do not proceed
                set_cleanup_temp_PAS
                set_cleanup_aasinifile
                #signal the waithandler, 1=Failure
                /root/install/signalFinalStatus.sh 1 "There is no INI_FILE for silent SAP Install - Failure"
		echo 1
                exit 1
	fi

	cp $INI_FILE $INI_FILE.$HOSTNAME

	sed -i  "/NW_DI_Instance.virtualHostname/ c\NW_DI_Instance.virtualHostname = ${HOSTNAME}" $INI_FILE.$HOSTNAME

	echo "$INI_FILE.$HOSTNAME" > /tmp/INI_FILE

	SID=$(grep -i "NW_GetSidNoProfiles.sid" "$SW_TARGET"/ASCS*.params | awk '{ print $NF }' | tr '[A-Z]' '[a-z]')
	SIDADM=$(echo $SID\adm)
	echo $SIDADM > /tmp/SIDADM

	if [ -n "$SIDADM" ]
	then
		echo 0
	else
		echo 1
	fi
}


set_install_ssm() {

	cd /tmp

	wget https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/latest/linux_amd64/amazon-ssm-agent.rpm > /dev/null 2>&1

	rpm -ivh /tmp/amazon-ssm-agent.rpm > /dev/null 2>&1

	echo '#!/usr/bin/sh' > /etc/init.d/ssm
	echo "service amazon-ssm-agent start" >> /etc/init.d/ssm

	chmod 755 /etc/init.d/ssm

	chkconfig ssm on > /dev/null 2>&1

	_SSM_RUNNING=$(ps -ef | grep ssm | grep -v grep)

	if [ -n "$_SSM_RUNNING" ]
	then
		echo 0
	else
		echo 1
	fi
}


set_install_cfn() {
#install the cfn helper scripts

        cd /tmp
        wget https://s3.amazonaws.com/cloudformation-examples/aws-cfn-bootstrap-latest.tar.gz
        gzip -df aws-cfn-bootstrap-latest.tar.gz
        tar -xvf aws-cfn-bootstrap-latest.tar
        ln -s /tmp/aws-cfn-bootstrap-1.4 /opt/aws
        chmod -R 755 /tmp/aws-cfn-bootstrap-1.4
}

set_configSAPWP() {
#configure the SAP workprocesses per the CF input parameter
#D = Optimize for Dialog processes, B = Optimize for Batch processes

	cd /sapmnt/"$SAP_SID"/profile 
	LOCHOST=$(hostname)
	SAP_PROF=$(ls *$LOCHOST)

	if [[ "$SAPWP" == "D" ]]
	then
		sed -i  "/wp_no_dia =/ c\rdisp\/wp_no_dia = 60" $SAP_PROF
		sed -i  "/wp_no_btc =/ c\rdisp\/wp_no_btc = 1" $SAP_PROF
	elif [[ "$SAPWP" == "B" ]]
	then
		sed -i  "/wp_no_dia =/ c\rdisp\/wp_no_dia = 1" $SAP_PROF
		sed -i  "/wp_no_btc =/ c\rdisp\/wp_no_btc = 60" $SAP_PROF
	else
		#Do nothing default config
		echo
	fi
}


###Main Body###

if [ -f "/etc/sap-app-quickstart" ]
then
        echo "****************************************************************"
	echo "****************************************************************"
        echo "The /etc/sap-app-quickstart file exists, exiting the Quick Start"
        echo "****************************************************************"
        echo "****************************************************************"
        exit 0
fi

_SET_NET=$(set_net)


if [ "$HOSTNAME" == $(hostname) ]
then
	echo "Successfully set and updated hostname"
	set_DB_hostname
else
	echo "FAILED to set hostname"
	#signal the waithandler, 1=Failed
        /root/install/signalFinalStatus.sh 1 "Failed to set hostname"
	set_cleanup_aasinifile
	exit 1
fi

_SET_AWSCLI=$(set_update_cli)

if [ "$_SET_AWSCLI" == 0 ]
then
	echo "Successfully installed AWS CLI"
else
	echo "FAILED to install AWS CLI...exiting"
	#signal the waithandler, 1=Failed
        /root/install/signalFinalStatus.sh 1 "FAILED to install AWS CLI...exiting"
	set_cleanup_aasinifile
	exit 1
fi

set_oss_configs
set_install_cfn

_SET_SSM=$(set_install_ssm)

if [ "$_SET_SSM" == 0 ]
then
	echo "Successfully installed SSM"
else
	echo "FAILED to install SSM...exiting"
	#signal the waithandler, 1=Failed
        /root/install/signalFinalStatus.sh 1 "FAILED to install ssm...exiting"
	set_cleanup_aasinifile
	exit 1
fi


_SET_UUIDD=$(set_uuidd)

if [ "$_SET_UUIDD" == 0 ]
then
	echo "Successfully installed UUIDD"
else
	echo "FAILED to install UUIDD...exiting"
	#signal the waithandler, 1=Failed
        /root/install/signalFinalStatus.sh 1 "FAILED to install UUIDD...exiting"
	set_cleanup_aasinifile
	exit 1
fi


_SET_TZ=$(set_tz)

if [ "$_SET_TZ" == 0 ]
then
	echo "Successfully updated TimeZone"
else
	echo "FAILED to update TimeZone...exiting"
	#signal the waithandler, 1=Failed
        /root/install/signalFinalStatus.sh 1 "FAILED to update TimeZone...exiting"
	set_cleanup_aasinifile
	exit 1
fi

_SET_NTP=$(set_ntp)

if [ "$_SET_NTP" == 0 ]
then
	echo "Successfully updated NTP"
else
	echo "FAILED to update NTP...exiting"
	#signal the waithandler, 1=Failed
        /root/install/signalFinalStatus.sh 1 "FAILED to update NTP...exiting"
	set_cleanup_aasinifile
	exit 1
fi

set_install_jq

_SET_FILESYSTEMS=$(set_filesystems)

_VAL_USR_SAP=$(df -h $USR_SAP) 

if [ -n "$_VAL_USR_SAP" ]
then
	echo "Successfully updated $USR_SAP filesystem"
else
	echo "FAILED to update $USR_SAP filesystem...exiting"
	#signal the waithandler, 1=Failed
        /root/install/signalFinalStatus.sh 1 "FAILED to  update $USR_SAP filesystem...exiting"
	set_cleanup_aasinifile
	exit 1
fi

_SET_AWSDP=$(set_awsdataprovider)

if [ "$_SET_AWSDP" == 0 ]
then
	echo "Successfully installed AWS Data Provider"
else
	echo "FAILED to install AWS Data Provider...exiting"
	#signal the waithandler, 1=Failed
        /root/install/signalFinalStatus.sh 1 "Failed to install AWS Data Provider...exiting"
	set_cleanup_aasinifile
	exit 1
fi


if [ "$INSTALL_SAP" == "No" ]
then
	echo "Completed setting up SAP App Server Infrastrucure."
	echo "Exiting as the option to install SAP software was set to: $INSTALL_SAP"
	#signal the waithandler, 0=Success
	/root/install/signalFinalStatus.sh 0 "Finished. Exiting as the option to install SAP software was set to: $INSTALL_SAP"
	exit 0

fi

MP=$(aws ssm get-parameters --names $SSM_PARAM_STORE --with-decryption --region $REGION --output text | awk '{ print $4}')
INVALID_MP=$(aws ssm get-parameters --names $SSM_PARAM_STORE --with-decryption --region $REGION --output text | awk '{ print $1}')

if [ "$INVALID_MP" == "INVALIDPARAMETERS" ]
then
	echo "Invalid encrypted SSM Parameter store: $SSM_PARAM_STORE...exiting"
	#signal the waithandler, 1=Failed
        /root/install/signalFinalStatus.sh 1 "Invalid SSM Parameter Store...exiting"
	set_cleanup_aasinifile
	exit 1
fi

if [ -z "$MP" ]
then
	echo "Could not read encrypted SSM Parameter store: $SSM_PARAM_STORE...exiting"
	#signal the waithandler, 1=Failed
        /root/install/signalFinalStatus.sh 1 "Could not read encrypted SSM Parameter store: $SSM_PARAM_STORE...exiting"
	set_cleanup_aasinifile
	exit 1
fi


_SET_AUTOFS=$(set_autofs)

_AUTOFS=$(df -h $SAPMNT | awk '{ print $NF }' | tail -1)


if [ "$_AUTOFS" == "$SAPMNT"  ]
then
	echo "Successfully setup autofs"
else
	echo "Failed to mount $SAPMNT...exiting"
	#signal the waithandler, 1=Failed
       	/root/install/signalFinalStatus.sh 1 "Failed to mount $SAPMNT, tried $COUNT times...exiting"
	set_cleanup_aasinifile
	exit 1
fi


###Execute sapinst###

set_ini_file

INI_FILE=$(cat /tmp/INI_FILE)

if [ ! -f "$INI_FILE" ]
then
	echo "Exiting script...no INI FILE...$INI_FILE"
	#signal the waithandler, 1=Failed
        /root/install/signalFinalStatus.sh 1 "Exiting script...no INI FILE...$INI_FILE"
	set_cleanup_aasinifile
	exit 1
fi


set_aasinifile

cd $SAPINST
sleep 5
./sapinst SAPINST_INPUT_PARAMETERS_URL="$INI_FILE" SAPINST_EXECUTE_PRODUCT_ID="$PRODUCT" SAPINST_USE_HOSTNAME="$HOSTNAME" SAPINST_SKIP_DIALOGS="true"

#configure SAP Workprocesses
set_configSAPWP

SIDADM=$(cat /tmp/SIDADM)
HOSTNAME=$(hostname)
su - $SIDADM -c "stopsap $HOSTNAME"
su - $SIDADM -c "startsap $HOSTNAME"

sleep 15

#test if SAP is up
_SAP_UP=$(netstat -an | grep 32"$SAPInstanceNum" | grep tcp | grep LISTEN | wc -l )

echo "This is the value of SAP_UP: $_SAP_UP"

if [ "$_SAP_UP" -eq 1 ]
then
	echo "Successfully installed SAP"
	set_cleanup_temp_PAS
	set_cleanup_aasinifile
	set_dist_hosts
	#signal the waithandler, 0=Success
        /root/install/signalFinalStatus.sh 0 "Successfully installed SAP. SAP_UP value is: $_SAP_UP"
	#create the /etc/sap-app-quickstart file
	touch /etc/sap-app-quickstart
	exit
else
	echo "SAP installed FAILED."
	set_cleanup_temp_PAS
	set_cleanup_aasinifile
	#signal the waithandler, 0=Success
	_ERR_LOG=$(find /tmp -type f -name "sapinst_dev.log")
	_PASS_ERR=$(grep ERR "$_ERR_LOG" | grep -i password)
	/root/install/signalFinalStatus.sh 1 "SAP ASCS install RETRY Failed...ASCS not installed 2nd retry...password error?= "$_PASS_ERR" "
fi
