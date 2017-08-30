#!/bin/bash -x

###Global Variables###
source /root/install/config.sh
TZ_LOCAL_FILE="/etc/localtime"
NTP_CONF_FILE="/etc/ntp.conf"
USR_SAP="/usr/sap"
SAPMNT="/sapmnt"
USR_SAP_DEVICE="/dev/xvdb"
SAPMNT_DEVICE="/dev/xvdc"
FSTAB_FILE="/etc/fstab"
DHCP="/etc/sysconfig/network/dhcp"
CLOUD_CFG="/etc/cloud/cloud.cfg"
NETCONFIG="/etc/sysconfig/network/config"
IP=$(curl http://169.254.169.254/latest/meta-data/local-ipv4/)
HOSTS_FILE="/etc/hosts"
HOSTNAME_FILE="/etc/HOSTNAME"
ETC_SVCS="/etc/services"
SERVICES_FILE="/sapmnt/SWPM/services"
PAS_INI_FILE="/sapmnt/SWPM/PASX_D00_Linux_HDB.params"
PAS_PRODUCT="NW_ABAP_CI:NW740SR2.HDB.PIHA"
SW_TARGET="/sapmnt/SWPM"
ASCS_DONE="/sapmnt/SWPM/ASCS_DONE"
PAS_DONE="/sapmnt/SWPM/PAS_DONE"
MASTER_HOSTS="/sapmnt/SWPM/master_etc_hosts"
SAPINST="/sapmnt/SWPM/sapinst"
REGION=$(curl http://169.254.169.254/latest/dynamic/instance-identity/document/ | grep -i region | awk '{ print $3 }' | sed 's/"//g' | sed 's/,//g')
#
###  Variables below need to be CUSTOMIZED for your environment  ###
#
HOSTNAME="$(hostname)"
SAP_SID="HDB"
TZ_INPUT_PARAM="PDT"
TZ_ZONE_FILE_PDT="/usr/share/zoneinfo/US/Pacific"

###Functions###
set_install_jq () {
#install jq s/w

	cd /tmp
	wget http://download.opensuse.org/repositories/utilities/SLE-12-SP1/x86_64/jq-1.5-22.1.x86_64.rpm
	rpm -ivh jq*rpm
}

set_tz() {
#set correct timezone per CF parameter input

	rm "$TZ_LOCAL_FILE"
	ln -s "$TZ_ZONE_FILE" "$TZ_LOCAL_FILE"

	#validate correct timezone
	CURRENT_TZ=$(date +%Z | cut -c 1,3)
     
	_TZ_INPUT_PARAM=$(echo $TZ_INPUT_PARAM | cut -c 1,3)

	if [ "$CURRENT_TZ" == "$_TZ_INPUT_PARAM" ]
	then
		echo 0
	else
		echo 1
	fi
}

set_install_ssm() {

	cd /tmp
	wget https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/latest/linux_amd64/amazon-ssm-agent.rpm

	rpm -ivh /tmp/amazon-ssm-agent.rpm

	echo '#!/usr/bin/sh' > /etc/init.d/ssm
	echo "service amazon-ssm-agent start" >> /etc/init.d/ssm

	chmod 755 /etc/init.d/ssm

	chkconfig ssm on
}

set_pasinifile() {
#set the vname of the database server in the INI file

     sed -i  "/hdb.create.dbacockpit.user/ c\hdb.create.dbacockpit.user = true" $PAS_INI_FILE

     #set the password from the SSM parameter store
     sed -i  "/NW_GetMasterPassword.masterPwd/ c\NW_GetMasterPassword.masterPwd = ${MP}" $PAS_INI_FILE
     sed -i  "/NW_HDB_getDBInfo.systemPassword/ c\NW_HDB_getDBInfo.systemPassword = ${MP}" $PAS_INI_FILE
     sed -i  "/storageBasedCopy.hdb.systemPassword/ c\storageBasedCopy.hdb.systemPassword = ${MP}" $PAS_INI_FILE
     sed -i  "/storageBasedCopy.abapSchemaPassword/ c\storageBasedCopy.abapSchemaPassword = ${MP}" $PAS_INI_FILE
     sed -i  "/HDB_Schema_Check_Dialogs.schemaPassword/ c\HDB_Schema_Check_Dialogs.schemaPassword = ${MP}" $PAS_INI_FILE

     #set the profile directory
     sed -i  "/NW_readProfileDir.profileDir/ c\NW_readProfileDir.profileDir = /sapmnt/${SAP_SID}/profile" $PAS_INI_FILE

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

set_ntp() {
#set ntp in the /etc/ntp.conf file

     cp "$NTP_CONF_FILE" "$NTP_CONF_FILE.bak"
     echo "server 0.pool.ntp.org" >> "$NTP_CONF_FILE"
     echo "server 1.pool.ntp.org" >> "$NTP_CONF_FILE"
     echo "server 2.pool.ntp.org" >> "$NTP_CONF_FILE"
     echo "server 3.pool.ntp.org" >> "$NTP_CONF_FILE"
     systemctl start ntpd
     echo "systemctl start ntpd" >> /etc/init.d/boot.local
     
     COUNT_NTP=$(grep ntp "$NTP_CONF_FILE" | wc -l)

     if [ "$COUNT_NTP" -ge 4 ]
     then
          echo 0
     else
          #did not sucessfully update ntp config
          echo 1
     fi
}

set_filesystems() {
#create /usr/sap filesystem and mount /sapmnt

    #create and attach EBS volumes for /usr/sap and /sapmnt

    bash /root/install/create-attach-single-volume.sh "50:gp2:$USR_SAP_DEVICE:$USR_SAP"
    bash /root/install/create-attach-single-volume.sh "100:gp2:$SAPMNT_DEVICE:$SAPMNT"

    USR_SAP_VOLUME=$(lsblk | grep xvdb)
    SAPMNT_VOLUME=$(lsblk | grep xvdc)

    if [ -z "$USR_SAP_VOLUME" -o -z "$SAPMNT_VOLUME"]
    then
        echo "Exiting, can not create $USR_SAP_DEVICE or $SAPMNT_DEVICE EBS volues"
        exit 1
    else
        mkdir $USR_SAP > /dev/null
        mkdir $SAPMNT > /dev/null
        mkdir $SW > /dev/null
    fi

     mkfs -t xfs $USR_SAP_DEVICE > /dev/null
     mkfs -t xfs $SAPMNT_DEVICE > /dev/null

     #create /etc/fstab entries
     echo "$USR_SAP_DEVICE  $USR_SAP xfs nobarrier,noatime,nodiratime,logbsize=256k 0 0" >> $FSTAB_FILE
     echo "$SAPMNT_DEVICE   $SAPMNT  xfs nobarrier,noatime,nodiratime,logbsize=256k 0 0" >> $FSTAB_FILE
     #echo "$EFS_FILESYSTEM  $SW  nfs rw,soft,bg,timeo=3,intr 0 0"  >> $FSTAB_FILE

     mount -a > /dev/null

     #validate /usr/sap and /sapmnt filesystems were created and mounted
     FS_USR_SAP=$(df -h | grep "$USR_SAP" | awk '{ print $NF }')
     FS_SAPMNT=$(df -h | grep "$SAPMNT" | awk '{ print $NF }')

     

     if [ "$FS_USR_SAP" == "$USR_SAP" -a "$FS_SAPMNT" == "$SAPMNT" ]
     then
          
          #download the media from the S3 bucket provided
          aws s3 sync $S3_BUCKET $SW_TARGET
          if [ -d "$SAPINST" ]
          then
              chmod -R 755 $SW_TARGET > /dev/null 
              echo 0
          else
              echo 1
          fi
     fi

}

set_dhcp() {

     sed -i '/DHCLIENT_SET_HOSTNAME/ c\DHCLIENT_SET_HOSTNAME="no"' $DHCP
     #restart network
     service network restart

     #validate dhcp file is correct
     _DHCP=$(grep DHCLIENT_SET_HOSTNAME $DHCP | grep no)

     if [ "$_DHCP" ]
     then
          echo 0
     else
          #did not sucessfully create
          echo 1
     fi
}

set_net() {
#query the R53 private hosted zone for our hostname based on our I.P. Address

     #update DNS search order with our DNS Domain name
     sed -i "/NETCONFIG_DNS_STATIC_SEARCHLIST=""/ c\NETCONFIG_DNS_STATIC_SEARCHLIST="${DNS_DOMAIN}"" $NETCONFIG

     #update the /etc/resolv.conf file
     netconfig update -f

}

set_hostname() {
#set and preserve the hostname

	hostname $HOSTNAME

	#update /etc/hosts file
	echo "$IP  $HOSTNAME" >> $HOSTS_FILE

	#save our HOSTNAME to the master_etc_hosts file as well
	echo "$IP  $HOSTNAME  #PAS Server#" >> $MASTER_HOSTS

	echo "$HOSTNAME" > $HOSTNAME_FILE
	sed -i '/preserve_hostname/ c\preserve_hostname: true' $CLOUD_CFG

	#disable dhcp
	_DISABLE_DHCP=$(set_dhcp)

	#validate hostname and dhcp
	if [ "$(hostname)" == "$HOSTNAME" -a "$_DISABLE_DHCP" == 0 ]
	then
		echo 0
	else
		echo 1
	fi
}

set_services_file() {
#update the /etc/services file with customer supplied values

	#need to check if services files exists
	if [ -s "$SERVICES_FILE" ]
	then
		cat "$SERVICES_FILE" >> $ETC_SVCS
		echo 0
	else
		echo 1
	fi
}

set_nfsexport() {
#export the /sapmnt filesystem
     #need to check if /sapmnt filesystem files exists

     FS_SAPMNT=$(df -h | grep "$SAPMNT" | awk '{ print $NF }')

     if [ "$FS_SAPMNT" ]
     then
          EXPORTS=$(echo $HOSTNAME | cut -c1-3)
	  echo "$SAPMNT     $EXPORTS*(rw,no_root_squash,no_subtree_check)" >> /etc/exports
          chkconfig nfs on
          service nfsserver start
          echo "service nfsserver start" >> /etc/init.d/boot.local
          sleep 15
          exportfs -a
	  echo 0
     else
          #did not sucessfully export
          echo 1
     fi

}

set_uuidd() {
#Install the uuidd daemon per SAP Note 1391070

     zypper -n install uuidd > /dev/null

     #validate the Install was successful
     _UUIDD=$(rpm -qa | grep uuidd)

    if [ "$_UUIDD" ]
    then
         echo 0
    else
         echo 1
    fi
}

set_update_cli() {
#update the aws cli
     zypper -n install python-pip

     pip install --upgrade --user awscli
}

###Main Body###

set_install_jq

_SET_UUIDD=$(set_uuidd)

if [ "$_SET_UUIDD" == 0 ]
then
     systemctl enable uuidd
     systemctl start uuidd
     _UUID_UP=$(ps -ef | grep uuidd | grep -iv grep)
    
     if [ "$_UUID_UP" ]
     then
         echo "Success, uuidd daemon install...will configure uuidd to auto start"

     fi
else 
     echo "FAILED, to install uuidd...exiting..."
     exit
fi

_SET_TZ=$(set_tz)

if [ "$_SET_TZ" == 0 ]
then
     _CURRENT_TZ=$(date +%Z)
     echo "Success, current TZ = $_CURRENT_TZ"
else
     _CURRENT_TZ=$(date +%Z)
     echo "FAILED, current TZ = $_CURRENT_TZ"
     exit
fi

_SET_AWSDP=$(set_awsdataprovider)

if [ "$_SET_AWSDP" == 0 ]
then
     echo "Successfully installed AWS Data Provider"
else
     echo "FAILED to install AWS Data Provider...exiting"
     exit
fi

_SET_DNS_=$(set_net)

_SET_NTP=$(set_ntp)

if [ "$_SET_NTP" == 0 ]
then
     echo "Successfully set NTP"
else
     echo "FAILED to set NTP "
     exit
fi

_SET_FS=$(set_filesystems)

if [ "$_SET_FS" == 0 ]
then
     echo "Successfully created $USR_SAP and $SAPMNT"
else
     echo
     #echo "FAILED to set /usr/sap and /sapmnt"
     #exit
fi

_SET_HOSTNAME=$(set_hostname)

if [ "$_SET_HOSTNAME" == 0 ]
then
     echo "Successfully set and updated hostname"
else
     echo "FAILED to set hostname"
     exit
fi


_SET_NFS=$(set_nfsexport)
SHOWMOUNT=$(showmount -e | wc -l)

if [ "$_SET_NFS" == 0 -a $SHOWMOUNT -ge 2 ]
then
     echo "Successfully exported NFS file(s)"
else
     echo "FAILED to export NFS file(s)"
     exit
fi


set_oss_configs

set_update_cli

set_install_ssm

MP=$(aws ssm get-parameters --names $SSM_PARAM_STORE --with-decryption --region $REGION --output text | awk '{ print $NF}')

set_pasinifile

###Execute sapinst###

#wait until the ASCS_DONE file is created before installing the PAS
while [ ! -f "$ASCS_DONE" ]
do
        echo "checking $ASCS_DONE file..."
        _FILE=$(ls -l "$ASCS_DONE")
        echo $_FILE
	sleep 60
done


#Proceed with the PAS Install
_SET_SERVICES=$(set_services_file)

if [ "$_SET_SERVICES" == 0 ]
then
     echo "Successfully set services file"
else
     echo "FAILED to set services file"
     exit
fi


cd $SAPINST
./sapinst SAPINST_INPUT_PARAMETERS_URL="$PAS_INI_FILE" SAPINST_EXECUTE_PRODUCT_ID="$PAS_PRODUCT" SAPINST_SKIP_DIALOGS="true"

_SAP_UP=$(ps -ef | grep -i sap | grep -v grep)

if [ "$_SAP_UP" ]
then
     echo "Successfully installed SAP"
     #create the PAS done file
     touch "$PAS_DONE"
     exit
else
     echo "RETRY SAP install..."

     cd $SAPINST

     ./sapinst SAPINST_INPUT_PARAMETERS_URL="$INI_FILE" SAPINST_EXECUTE_PRODUCT_ID="$PRODUCT" SAPINST_SKIP_DIALOGS="true"

     _SAP_UP=$(ps -ef | grep -i sap | grep -v grep)

     if [ "$_SAP_UP" ]
     then
         #create the PAS done file
         touch "$PAS_DONE"
     else
         echo "SAP PAS failed to install...exiting"
         exit
     fi
fi
