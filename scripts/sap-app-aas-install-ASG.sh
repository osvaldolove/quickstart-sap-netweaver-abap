#!/bin/bash -x


#

#   This code was written by somckitk@amazon.com.
#   This sample code is provided on an "AS IS" BASIS,
#   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.

#

###Global Variables###
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

#source the config.sh file

set_configsh() {
#download and source the latest config.sh file 

	#download file config.sh file from S3
	aws s3 cp "$S3_BUCKET""config.sh" /tmp/config.sh

	#source the latest config.sh file (from /tmp/config.sh if it exists and its size is > 0)
	if [ -s /tmp/config.sh ]
	then
		source /tmp/config.sh
	else
		source /root/install/config.sh
	fi
}

set_configsh

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

    zypper -n install gcc

    zypper install libgcc_s1 libstdc++6

    echo "#END: This section inserted by AWS SAP HANA Quickstart" >> /etc/init.d/boot.local
    echo "###################" >> /etc/init.d/boot.local
}

set_awsdataprovider() {
#install the AWS dataprovider require for AWS support

	cd /tmp
	wget https://s3.amazonaws.com/aws-data-provider/bin/aws-agent_install.sh > /dev/null

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

	#set the profile directory
	sed -i  "/NW_readProfileDir.profileDir/ c\NW_readProfileDir.profileDir = /sapmnt/${SAP_SID}/profile" $INI_FILE

        _VAL_MP=$(grep "$MP" $INI_FILE)
	_VAL_SAP_SID=$(grep "$SAP_SID" $INI_FILE)

	#set the UID and GID
	sed -i  "/nwUsers.sidAdmUID/ c\nwUsers.sidAdmUID = ${SIDadmUID}" $INI_FILE
	sed -i  "/nwUsers.sapsysGID/ c\nwUsers.sapsysGID = ${SAPsysGID}" $INI_FILE

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

	bash /root/install/create-attach-single-volume.sh "50:gp2:$USR_SAP_DEVICE:$USR_SAP" > /dev/null
	USR_SAP_VOLUME=$(lsblk | grep xvdb)

	#allocate SWAP space
	bash /root/install/create-attach-single-volume.sh "16:gp2:/dev/xvdc:SWAP" > /dev/null

	if [ -z "$USR_SAP_VOLUME" ]
	then
		echo "Exiting, can not create $USR_SAP_DEVICE or $SAPMNT_DEVICE EBS volues"
	        #signal the waithandler, 1=Failed
	        /root/install/signalFinalStatus.sh 1
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

save_known_hosts() {
#setup environment variable (/sapmnt must be available)

	export LD_LIBRARY_PATH="/sapmnt/${SAP_SID}/exe/uc/linuxx86_64:$LD_LIBRARY_PATH"
	PF="/sapmnt/${SAP_SID}/profile/DEFAULT.PFL"

	set_services_file

	ALL_AAS_IP=$(/sapmnt/${SAP_SID}/exe/uc/linuxx86_64/lgtst pf=$PF | grep $NAME | awk '{ print $3 }' |  sed 's/\[//g' | sed 's/\]//g')
	ALL_AAS_NAME=$(/sapmnt/${SAP_SID}/exe/uc/linuxx86_64/lgtst pf=$PF | grep $NAME | awk '{ print $2 }' |  sed 's/\[//g' | sed 's/\]//g')

	PAS_EC2ID=$(aws ec2 describe-instances --region $REGION --query 'Reservations[].Instances[].[PrivateIpAddress,InstanceId]' --output text | grep "$SAP_PASIP" | awk '{ print $2 }')

	echo $PAS_EC2ID > /tmp/PAS_EC2ID
	aws ssm send-command --instance-ids  $PAS_EC2ID --document-name "AWS-RunShellScript" --comment "hosts" --parameters commands="cp $HOSTS_FILE $SW_TARGET/hosts.all" --region $REGION --output text
	sleep 15
	cat "$SW_TARGET/hosts.all" >> "$HOSTS_FILE"

	#merge the IP and NAMES and add to  /etc/hosts and /tmp
	paste <(echo "$ALL_AAS_IP") <(echo "$ALL_AAS_NAME") >> $HOSTS_FILE

}

determine_hostname() {
#save the known hosts first

	save_known_hosts

	HOSTNUM="99"

	for NUM in $(seq 1 $HOSTNUM)
	do
		#handle the 9th app server
		if [ $NUM -le 9 ]
		then
			PING0=$(ping -c 1 -W 1 $NAME\0$NUM | grep "100% packet loss")

			#check to see if the ping was NOT successful
			if [[ -z "$PING0" || "$PING0" =~ "100% packet loss" ]]
			then
				#test to see if we received 1 packet (PING0 could be unset because we did not grep for 1 pkt received)
				PING01=$(ping -c 1 -W 1 $NAME\0$NUM | grep "1 received")
				if [[ "$PING01" =~ "1 received" ]]
				then
					continue
				else
					#we have a match, this server is **not** in use
					#set our HOSTNAME to this server
					HOSTNAME=$NAME\0$NUM
					echo $HOSTNAME > /tmp/HOSTNAME
					break
				fi
			fi
		else
			#we are beyond 9 servers
			PING1=$(ping -c 1 -W 1 $NAME$NUM | grep "100% packet loss")

			#check to see if the ping was NOT successfull
			if [[ -z "$PING1" || "$PING1" =~ "100% packet loss" ]]
			then
				#test to see if we received 1 packet (PING1 could be unset because we did not grep for 1 pkt received)
				PING11=$(ping -c 1 -W 1 $NAME$NUM | grep "1 received")
				if [[ "$PING11" =~ "1 received" ]]
				then
					continue
				else
					#we have a match, this server is **not** in use
					#set our HOSTNAME to this server
					HOSTNAME=$NAME$NUM
					echo $HOSTNAME > /tmp/HOSTNAME
					break
				fi
               		fi

          	fi
	done

	_VAL_HOSTS=$(cat /tmp/HOSTNAME)

	if [ "$HOSTNAME" == "$_VAL_HOSTS" ]
	then
		echo 0
	else
		echo 1
	fi
}

set_tempname_PAS() {
#call over to the PAS server and update its /etc/hosts file with this a temp name to access /sapmnt

	PAS_EC2ID=$(aws ec2 describe-instances --region $REGION --query 'Reservations[].Instances[].[PrivateIpAddress,InstanceId]' --output text | grep "$SAP_PASIP" | awk '{ print $2 }')
	UPD_HOSTS_CMD="$IP    $TEMP_NAME"

	echo $PAS_EC2ID > /tmp/PAS_EC2ID
	_SND_PAS=$(aws ssm send-command --instance-ids  $PAS_EC2ID --document-name "AWS-RunShellScript" --comment "update_hosts" --parameters commands="echo $UPD_HOSTS_CMD >> $HOSTS_FILE" --query '*."CommandId"' --region $REGION --output text)
 
	sleep 10

	_SND_STAT=$(aws ssm list-command-invocations --command-id "$_SND_PAS" --details --region $REGION  | grep -i success | wc -l)

	#restart the nscd on the PAS
	_SND_PAS=$(aws ssm send-command --instance-ids  $PAS_EC2ID --document-name "AWS-RunShellScript" --comment "nscd_restart" --parameters commands="service nscd restart" --query '*."CommandId"' --region $REGION --output text)

	sleep 5

	if [ "$_SND_STAT" -ge 1 ]
	then
		echo 0
	else
		echo 1
	fi
}


set_PAS_hostname() {

	echo "$DBIP  $DBHOSTNAME" >> $HOSTS_FILE
	echo "$SAP_PASIP  $SAP_PAS" >> $HOSTS_FILE
	#echo "$SAP_ASCSIP  $SAP_ASCS" >> $HOSTS_FILE
}

set_perm_ssm() {
#call over to the PAS & ASCS servers and update its /etc/hosts file with this server's IP and HOSTNAME

	HOSTNAME=$(cat /tmp/HOSTNAME)
	UPD_HOSTS_CMD="$IP    $HOSTNAME"

	PAS_EC2ID=$(cat /tmp/PAS_EC2ID)
	#ASCS_EC2ID=$(aws ec2 describe-instances --region $REGION --query 'Reservations[].Instances[].[PrivateIpAddress,InstanceId]' --output text | grep "$SAP_ASCSIP" | awk '{ print $2 }')

	#for f in $PAS_EC2ID $ASCS_EC2ID
	for f in $PAS_EC2ID 
	do
		#save the current /etc/hosts file	
		_SND_BAK=$(aws ssm send-command --instance-ids  $f --document-name "AWS-RunShellScript" --comment "copy_hosts_bak" --parameters commands="cp $HOSTS_FILE $SW_TARGET/hosts.bak" --query '*."CommandId"' --region $REGION --output text)
		sleep 5
                _SND_STAT_BAK=$(aws ssm list-command-invocations --command-id "$_SND_BAK" --details --region $REGION  | grep -i success | wc -l)

	        #need to make sure the SND_BAK is successful before proceeding
	        RETRY_COUNT=0
       		RETRY_TIMES=10

        	while [ "$_SND_STAT_BAK" -lt 1 ]
        	do	
                	#retry 10 times then hard exit with failure
                	if [ "$RETRY_COUNT" -ge "$RETRY_TIMES" ]
                	then
                        	#signal failure and do not proceed
                        	set_cleanup_temp_PAS
                        	set_cleanup_aasinifile
                        	#signal the waithandler, 1=Failure
                        	/root/install/signalFinalStatus.sh 1
				echo 1
                        	exit 1
                	else
				_SND_BAK=$(aws ssm send-command --instance-ids  $f --document-name "AWS-RunShellScript" --comment "copy_hosts_bak" --parameters commands="cp $HOSTS_FILE $SW_TARGET/hosts.bak" --query '*."CommandId"' --region $REGION --output text)
                        	sleep 5
                		_SND_STAT_BAK=$(aws ssm list-command-invocations --command-id "$_SND_BAK" --details --region $REGION  | grep -i success | wc -l)
                        	let RETRY_COUNT=$RETRY_COUNT+1
                	fi
        	done	

		#update the PAS's hosts file
		if [ ! -z "$TEMP_NAME_NR" -o ! -z "$HOSTNAME" ]
		then
			grep -v "$TEMP_NAME_NR" $SW_TARGET/hosts.bak > $SW_TARGET/hosts.temp 
			grep -v "$HOSTNAME" $SW_TARGET/hosts.temp > $SW_TARGET/hosts.new 
			echo $UPD_HOSTS_CMD >> $SW_TARGET/hosts.new
			_SND_PAS=$(aws ssm send-command --instance-ids  $f --document-name "AWS-RunShellScript" --comment "copy_hosts" --parameters commands="cp "$SW_TARGET/hosts.new" "$HOSTS_FILE"" --query '*."CommandId"' --region $REGION --output text)
			sleep 5 
              		_SND_STAT=$(aws ssm list-command-invocations --command-id "$_SND_PAS" --details --region $REGION  | grep -i success | wc -l)
			aws ssm send-command --instance-ids  $f --document-name "AWS-RunShellScript" --comment "nscd_restart" --parameters commands="service ncsd restart" --region $REGION --output text
		else
			echo 1
			exit 1
		fi

                while [ "$_SND_STAT" -lt 1 ]
                do 
                        #retry 10 times then hard exit with failure
                        if [ "$RETRY_COUNT" -ge "$RETRY_TIMES" ]
                        then
                                #signal failure and do not proceed
                                set_cleanup_temp_PAS
                                set_cleanup_aasinifile
                                #signal the waithandler, 1=Failure
                                /root/install/signalFinalStatus.sh 1
                                exit 1
                        else
				_SND_PAS=$(aws ssm send-command --instance-ids  $f --document-name "AWS-RunShellScript" --comment "copy_hosts" --parameters commands="cp "$SW_TARGET/hosts.new" "$HOSTS_FILE"" --query '*."CommandId"' --region $REGION --output text)
                                sleep 5
              			_SND_STAT=$(aws ssm list-command-invocations --command-id "$_SND_PAS" --details --region $REGION  | grep -i success | wc -l)
				aws ssm send-command --instance-ids  $f --document-name "AWS-RunShellScript" --comment "nscd_restart" --parameters commands="service ncsd restart" --region $REGION --output text
                                let RETRY_COUNT=$RETRY_COUNT+1
                        fi
                done
	#done for the for loop
	done
}

set_hostname() {
#set and preserve the hostname

	determine_hostname

	#update DNS search order with our DNS Domain name
	sed -i "/NETCONFIG_DNS_STATIC_SEARCHLIST=""/ c\NETCONFIG_DNS_STATIC_SEARCHLIST="${DNS_DOMAIN}"" $NETCONFIG

	#update the /etc/resolv.conf file
	netconfig update -f > /dev/null

	HOSTNAME=$(cat /tmp/HOSTNAME)
	hostname $HOSTNAME

	#update /etc/hosts file
	echo "$IP  $HOSTNAME" >> $HOSTS_FILE
	echo "$HOSTNAME" > $HOSTNAME_FILE

	sed -i '/preserve_hostname/ c\preserve_hostname: true' $CLOUD_CFG

	#disable dhcp
	_DISABLE_DHCP=$(set_dhcp)

	#update the PAS & ASCS with the permanent hostname
	_PERM=$(set_perm_ssm)

	if [ "$PERM" -eq 1 ]
	then
		echo 1
		exit 1
	fi

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
#setup the /etc/auto.master and /etc/auto.direct files to mount /sapmnt from the PAS

	#sed -i '/+auto.master/ c\#+auto.master' $AUTO_MASTER
	#echo "/- auto.direct" >> $AUTO_MASTER
	#echo "$SAPMNT -rw,rsize=32768,wsize=32768,timeo=14,intr $SAP_PAS:$SAPMNT" >> $AUTO_DIRECT

	mkdir  $SAPMNT
        #check to see if there is already a /sapmnt entry in /etc/fstab
	_FSTAB=$(grep "$SAPMNT" /etc/fstab | wc -l )

	if [ $_FSTAB -ge 1 ]
	then
		echo 0
	else
		echo "$SAP_PAS:$SAPMNT  $SAPMNT nfs rw,soft,bg,timeo=14,intr 0 0" >> /etc/fstab 
	fi

	#update the /etc/hosts file on the PAS before we enable autofs
	set_PAS_hostname
	#now try to update the /etc/hosts file on the PAS
	_SND_SSM=$(set_tempname_PAS)

	PAS_EC2ID=$(cat /tmp/PAS_EC2ID)
	#restart rpc.mountd on the PAS
	aws ssm send-command --instance-ids  $PAS_EC2ID --document-name "AWS-RunShellScript" --comment "restart mountd" --parameters commands="pkill rpc.mountd; /usr/sbin/rpc.mountd" --region $REGION --output text
	#restart the nscd 
	aws ssm send-command --instance-ids  $PAS_EC2ID --document-name "AWS-RunShellScript" --comment "nscd_restart" --parameters commands="service nscd restart"  --region $REGION --output text

	COUNT=0

	mount $SAPMNT

	while [ "$_SND_SSM" == 1 ]
	do
		_SND_SSM=$(set_tempname_PAS)
		#restart rpc.mountd on the PAS
		aws ssm send-command --instance-ids  $PAS_EC2ID --document-name "AWS-RunShellScript" --comment "restart mountd" --parameters commands="pkill rpc.mountd; /usr/sbin/rpc.mountd" --region $REGION --output text
		#restart the nscd 
		aws ssm send-command --instance-ids  $PAS_EC2ID --document-name "AWS-RunShellScript" --comment "nscd_restart" --parameters commands="service nscd restart"  --region $REGION --output text
		echo "Trying to update the /etc/hosts on the PAS: $SAP_PAS..."
		sleep 15
		let COUNT=$COUNT+1
		mount $SAPMNT
		
		if [ $COUNT -ge 10 ]
		then
			echo "Failed to update the /etc/hosts on the PAS: $SAP_PAS after $COUNT tries...exiting"
			exit 1
		fi
	done

	#chkconfig autofs on
	#service autofs restart
	sleep 5

	#_AD=$(ps -ef | grep $(cat /var/run/automount.pid) | grep -v grep |wc -l )
	_DF=$(showmount -e "$SAP_PAS" | grep "$SAPMNT" | wc -l )

	#check showmount 
	if [ $_DF -eq 1 ]
	then
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
		#re-download template files
		FNAME=$(echo $INI_FILE | awk -F"/" '{ print $4 }')
		aws s3 cp "$S3_BUCKET""$FNAME" $SW_TARGET
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

set_cleanup_temp_PAS() {
#remove saptemp from PAS server

	PAS_EC2ID=$(cat /tmp/PAS_EC2ID)
	aws ssm send-command --instance-ids  $PAS_EC2ID --document-name "AWS-RunShellScript" --comment "update_hosts" --parameters commands="grep -v $TEMP_NAME $HOSTS_FILE > $HOSTS_FILE.temp" --query '*."CommandId"' --region $REGION --output text
	sleep 15
	aws ssm send-command --instance-ids  $PAS_EC2ID --document-name "AWS-RunShellScript" --comment "update_hosts" --parameters commands="cp $HOSTS_FILE.temp $HOSTS_FILE" --query '*."CommandId"' --region $REGION --output text
	sleep 15
	aws ssm send-command --instance-ids  $PAS_EC2ID --document-name "AWS-RunShellScript" --comment "update_hosts" --parameters commands="service ncsd restart" --query '*."CommandId"' --region $REGION --output text
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

set_dist_hosts() {
#from the current AAS server dist. hosts file ( the PAS server's /etc/hosts file has all of the known servers) 

	PAS_EC2ID=$(cat /tmp/PAS_EC2ID)
	_SND_PAS=$(aws ssm send-command --instance-ids  $PAS_EC2ID --document-name "AWS-RunShellScript" --comment "copy_hosts_file" --parameters commands="cp $HOSTS_FILE $SW_TARGET/hosts.pas" --query '*."CommandId"' --region $REGION --output text)

	sleep 15

	_SND_STAT=$(aws ssm list-command-invocations --command-id "$_SND_PAS" --details --region $REGION  | grep -i success | wc -l)

	#need to make sure the SND_PAS is successful before proceeding
	RETRY_COUNT=0
	RETRY_TIMES=10

       	while [ "$_SND_STAT" -lt 1 ]
 	do	
		#retry 10 times then hard exit with failure	
		if [ "$RETRY_COUNT" -ge "$RETRY_TIMES" ]
		then
			#signal failure and do not proceed		
		        set_cleanup_temp_PAS
        		set_cleanup_aasinifile
        		#signal the waithandler, 1=Failure
        		/root/install/signalFinalStatus.sh 1
			echo 1
			exit 1
		else
			_SND_PAS=$(aws ssm send-command --instance-ids  $PAS_EC2ID --document-name "AWS-RunShellScript" --comment "copy_hosts_file" --parameters commands="cp $HOSTS_FILE $SW_TARGET/hosts.pas" --query '*."CommandId"' --region $REGION --output text)
			sleep 15
			_SND_STAT=$(aws ssm list-command-invocations --command-id "$_SND_PAS" --details --region $REGION  | grep -i success | wc -l)
			let RETRY_COUNT=$RETRY_COUNT+1
		fi
	done	

	PF="/sapmnt/${SAP_SID}/profile/DEFAULT.PFL"
	export LD_LIBRARY_PATH="/sapmnt/${SAP_SID}/exe/uc/linuxx86_64:$LD_LIBRARY_PATH"

	#determine the valid EC2 servers in the SAP cluster by query the SAP message server
	ALL_IPS=$(/sapmnt/${SAP_SID}/exe/uc/linuxx86_64/lgtst pf=$PF | grep DIA | awk '{ print $3 }' |  sed 's/\[//g' | sed 's/\]//g')

	#Only update the hosts that are valid (conatined in ALL_IPS) and known to the SAP cluster 

	for i in $ALL_IPS
	do
        	MYEC2ID=$(aws ec2 describe-instances --region $REGION --query 'Reservations[].Instances[].[PrivateIpAddress,InstanceId]' --output text | grep "$i" | awk '{ print $2 }')
        	if [ ! -z "$MYEC2ID" ]
        	then
                	_SND=$(aws ssm send-command --instance-ids  $MYEC2ID --document-name "AWS-RunShellScript" --comment "update_hosts" --parameters commands="cp $SW_TARGET/hosts.pas $HOSTS_FILE" --query '*."CommandId"' --region $REGION --output text)
			sleep 5 
			_SND_STAT=$(aws ssm list-command-invocations --command-id "$_SND" --details --region $REGION  | grep -i success | wc -l)
			#restart the nscd 
			_SND_NSCD=$(aws ssm send-command --instance-ids  $MYEC2ID --document-name "AWS-RunShellScript" --comment "nscd_restart" --parameters commands="service nscd restart" --query '*."CommandId"' --region $REGION --output text)

			RETRY_COUNT=0
			RETRY_TIMES=10

			while [ "$_SND_STAT" -lt 1 ]
		 	do	
				#retry 10 times then hard exit with failure	
				if [ "$RETRY_COUNT" -ge "$RETRY_TIMES" ]
				then
					#signal failure and do not proceed		
		        		set_cleanup_temp_PAS
        				set_cleanup_aasinifile
        				#signal the waithandler, 1=Failure
        				/root/install/signalFinalStatus.sh 1
					exit 1
				else
					_SND=$(aws ssm send-command --instance-ids  $PAS_EC2ID --document-name "AWS-RunShellScript" --comment "copy_hosts_file" --parameters commands="cp $HOSTS_FILE $SW_TARGET/hosts.pas" --query '*."CommandId"' --region $REGION --output text)
					sleep 15
					#reset SND_STAT
					_SND_STAT=$(aws ssm list-command-invocations --command-id "$_SND" --details --region $REGION  | grep -i success | wc -l)
					#restart the nscd 
					_SND_NSCD=$(aws ssm send-command --instance-ids  $MYEC2ID --document-name "AWS-RunShellScript" --comment "nscd_restart" --parameters commands="service nscd restart" --query '*."CommandId"' --region $REGION --output text)
					#reset RETRY_COUNT 
					let RETRY_COUNT=$RETRY_COUNT+1
				fi
			done	
       		fi
	#done for the for loop
	done

	#copy PAS hosts file locally
	cp $SW_TARGET/hosts.pas /etc/hosts
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

#Test Internet connectivity - exit and terminate the EC2 instance if no connectivity#

_TEST_INTERNET_CONN=$(curl --connect-timeout 30 ifconfig.co > /tmp/TEST_INTERNET_CONN 2>&1)&

sleep 15

_TEST_INTERNET_RUNN=$(ps -ef | grep "curl --connect-timeout 30 ifconfig.co" | grep -v grep | wc -l)

sleep 20

_TEST_INTERNET_TO=$(grep "timed out" /tmp/TEST_INTERNET_CONN)

if [[ "$_TEST_INTERNET_TO" =~ .*timed.* ]]
then
        if [ $_TEST_INTERNET_RUNN -eq 1 ]
        then
                echo "No Internet Connectivity...Please terminate this EC2 instance or resolve the connection issue."
		#signal the waithandler, 1=Failed
		/root/install/signalFinalStatus.sh 1
		set_cleanup_aasinifile
                exit 1
        fi

fi

_SET_AWSCLI=$(set_update_cli)

if [ "$_SET_AWSCLI" == 0 ]
then
	echo "Successfully installed AWS CLI"
else
	echo "FAILED to install AWS CLI...exiting"
	#signal the waithandler, 1=Failed
	/root/install/signalFinalStatus.sh 1
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
	/root/install/signalFinalStatus.sh 1
	set_cleanup_aasinifile
	exit 1
fi


MP=$(aws ssm get-parameters --names $SSM_PARAM_STORE --with-decryption --region $REGION --output text | awk '{ print $NF}')
INVALID_MP=$(aws ssm get-parameters --names $SSM_PARAM_STORE --with-decryption --region $REGION --output text | awk '{ print $1}')

if [ "$INVALID_MP" == "INVALIDPARAMETERS" ]
then
	echo "Invalid encrypted SSM Parameter store: $SSM_PARAM_STORE...exiting"
	#signal the waithandler, 1=Failed
	/root/install/signalFinalStatus.sh 1
	set_cleanup_aasinifile
	exit 1
fi

if [ -z "$MP" ]
then
	echo "Could not read encrypted SSM Parameter store: $SSM_PARAM_STORE...exiting"
	#signal the waithandler, 1=Failed
	/root/install/signalFinalStatus.sh 1
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
	/root/install/signalFinalStatus.sh 1
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
	/root/install/signalFinalStatus.sh 1
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
	/root/install/signalFinalStatus.sh 1
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
	/root/install/signalFinalStatus.sh 1
	set_cleanup_aasinifile
	exit 1
fi

_SET_AUTOFS=$(set_autofs)

_AUTOFS=$(df -h $SAPMNT | awk '{ print $NF }' | tail -1)

#Set counter for Autofs retries
COUNT=0

if [ "$_AUTOFS" == "$SAPMNT"  ]
then
	echo "Successfully setup autofs"
else
	while [ "$_AUTOFS" != "$SAPMNT" ]
	do
		sleep 60
		set_autofs
		_AUTOFS=$(df -h $SAPMNT | awk '{ print $NF }' | tail -1)
		echo "waiting for $SAPMNT to become available: $_AUTOFS"
		let COUNT=$COUNT+1
	
		if [ $COUNT -ge 15 ]
		then
			echo "Failed to mount $SAPMNT, tried $COUNT times...exiting"
			#signal the waithandler, 1=Failed
			/root/install/signalFinalStatus.sh 1
			set_cleanup_aasinifile
			exit 1
		fi
	done
fi

_SET_HOSTNAME=$(set_hostname)

HOSTNAME=$(cat /tmp/HOSTNAME)

if [ "$HOSTNAME" == $(hostname) ]
then
	echo "Successfully set and updated hostname"
else
	echo "FAILED to set hostname"
	#signal the waithandler, 1=Failed
	/root/install/signalFinalStatus.sh 1
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
	/root/install/signalFinalStatus.sh 1
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
	/root/install/signalFinalStatus.sh 1
	set_cleanup_aasinifile
	exit 1
fi


set_aasinifile

cd $SAPINST
sleep 5
./sapinst SAPINST_INPUT_PARAMETERS_URL="$INI_FILE" SAPINST_EXECUTE_PRODUCT_ID="$PRODUCT" SAPINST_SKIP_DIALOGS="true"

#configure SAP Workprocesses
set_configSAPWP

SIDADM=$(cat /tmp/SIDADM)
HOSTNAME=$(cat /tmp/HOSTNAME)
su - $SIDADM -c "stopsap $HOSTNAME"
su - $SIDADM -c "startsap $HOSTNAME"

_SAP_UP=$(ps -ef | grep D | grep sap | grep -v grep)

if [ -n "$_SAP_UP" ]
then
	echo "Successfully installed SAP"
	set_cleanup_temp_PAS
	set_cleanup_aasinifile
	set_dist_hosts
	#signal the waithandler, 0=Success
	/root/install/signalFinalStatus.sh 0
	#create the /etc/sap-app-quickstart file
	touch /etc/sap-app-quickstart
	exit
else
	set_cleanup_temp_PAS
	set_cleanup_aasinifile
	#signal the waithandler, 0=Success
	/root/install/signalFinalStatus.sh 1
fi
