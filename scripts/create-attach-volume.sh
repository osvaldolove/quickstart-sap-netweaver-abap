#!/bin/bash


# ------------------------------------------------------------------
# 			Creates volume and waits for it to finish
#			Input specified as #Vols x #size x #Type x #starting dir
# ------------------------------------------------------------------



[ -e /root/install/jq ] && export JQ_COMMAND=/root/install/jq
[ -z ${JQ_COMMAND} ] && export JQ_COMMAND=/home/ec2-user/jq

export PATH=${PATH}:/sbin:/usr/sbin:/usr/local/sbin:/root/bin:/usr/local/bin:/usr/bin:/bin:/usr/bin/X11:/usr/X11R6/bin:/usr/games:/usr/lib/AmazonEC2/ec2-api-tools/bin:/usr/lib/AmazonEC2/ec2-ami-tools/bin:/usr/lib/mit/bin:/usr/lib/mit/sbin

usage() { 
    cat <<EOF
Usage: $0 #vol:#size:Type:{#PIOPS}:DeviceStart:Name
Examples: 5:20:gp2:/dev/sdb:node [ 5 gp2 EBS, 20 GB each, /dev/sd{b,c,d,e,f}
Examples: 5:12:standard:/dev/sdb:node [ 5 standard EBS, 12 GB each, /dev/sd{b,c,d,e,f}
Examples: 5:12:io1:5000:/dev/sdb:node [ 5 PIOPS vol, 5000 IoPS, 12 GB each, /dev/sd{b,c,d,e,f}
EOF
    exit 0
}


# ------------------------------------------------------------------
#          Read all inputs
# ------------------------------------------------------------------

[[ $# -ne 1 ]] && usage;
ARGS_LIST=$1

[ -e /root/install/config.sh ] && source /root/install/config.sh 
export AWS_DEFAULT_REGION=${REGION}
export AWS_DEFAULT_AVAILABILITY_ZONE=${AVAILABILITY_ZONE}


if [ -z ${AWS_DEFAULT_REGION} ]; then
	 export AWS_DEFAULT_REGION=$(curl -s http://169.254.169.254/latest/dynamic/instance-identity/document \
					| ${JQ_COMMAND} '.region'  \
					| sed 's/^"\(.*\)"$/\1/' )
fi
if [ -z ${AWS_DEFAULT_AVAILABILITY_ZONE} ]; then
	 export AWS_DEFAULT_AVAILABILITY_ZONE=$(curl -s http://169.254.169.254/latest/dynamic/instance-identity/document \
						| ${JQ_COMMAND} '.availabilityZone' \
						| sed 's/^"\(.*\)"$/\1/' )
fi

if [ -z ${AWS_INSTANCEID} ]; then
	 export AWS_INSTANCEID=$(curl -s http://169.254.169.254/latest/dynamic/instance-identity/document \
						| ${JQ_COMMAND} '.instanceId' \
						| sed 's/^"\(.*\)"$/\1/' )
fi


# ------------------------------------------------------------------
#          remove double quotes, if any. cli doesn't like it!
# ------------------------------------------------------------------

export AWS_DEFAULT_REGION=$(echo ${AWS_DEFAULT_REGION} | sed 's/^"\(.*\)"$/\1/' )
export AWS_DEFAULT_AVAILABILITY_ZONE=$(echo ${AWS_DEFAULT_AVAILABILITY_ZONE} | sed 's/^"\(.*\)"$/\1/' )
export AWS_INSTANCEID=$(echo ${AWS_INSTANCEID} | sed 's/^"\(.*\)"$/\1/' )


# ------------------------------------------------------------------
#          Choose default log file
# ------------------------------------------------------------------
SCRIPT_DIR=/root/install/
SCRIPT_DIR=./
if [ -z "${HANA_LOG_FILE}" ] ; then
    HANA_LOG_FILE=${SCRIPT_DIR}/install.log
fi
log() {
	if [ -e /root/install/config.sh ]; then
		echo $* 2>&1 |  tee -a ${HANA_LOG_FILE}
	else
		echo $* 2>&1 
	fi
}


# ------------------------------------------------------------------
#          Wait until volume status says "ok"
# ------------------------------------------------------------------
wait_for_volume_create () {
   local volumeid="$1"
    while true; do
		status=$(aws ec2 describe-volume-status --volume-ids ${volumeid}  | \
				${JQ_COMMAND} '.VolumeStatuses[].VolumeStatus.Status' )
		echo ${volumeid}:${status}
        case "$status" in
			*ok* ) break;;
        esac
		sleep 10
	done	
	log ${volumeid}:"ok"
}

# ------------------------------------------------------------------
#          Wait until volume attach to say "okay"
# ------------------------------------------------------------------
wait_for_attach_volume () {
   local volumeid="$1"
    while true; do
		status=$(aws ec2 describe-volumes --volume-ids ${volumeid}  | \
				${JQ_COMMAND} '.Volumes[].Attachments[].State' )
		echo ${volumeid}:${status}
        case "$status" in
			*attached* ) break;;
        esac
		sleep 10
	done	
	log ${volumeid}:"attached"
}

# ------------------------------------------------------------------
#          Change device attribute to "delete on termination"
# ------------------------------------------------------------------
set_device_delete_ontermination () {
	local device="$1"
    blkdev_template='"[{\"DeviceName\":\"DEVICE_STRING\",\"Ebs\":{\"DeleteOnTermination\":true}}]"'
   
	blkdev_json=$(echo -n ${blkdev_template} | sed "s:DEVICE_STRING:$device:")
	echo aws ec2 modify-instance-attribute --instance-id ${AWS_INSTANCEID} --block-device-mappings ${blkdev_json} | sh
	log ${device}->"DeleteOnTermination:True"
}

log `date` BEGIN Creating Volumes and Attaching ${ARGS_LIST}

ARGS_LIST_ARRAY=(${ARGS_LIST//:/ })
VOL_COUNT=${ARGS_LIST_ARRAY[0]}
VOL_SIZE=${ARGS_LIST_ARRAY[1]}
VOL_TYPE=${ARGS_LIST_ARRAY[2]}
VOL_PIOPS=


[ -z ${VOL_COUNT} ] && usage;
[ -z ${VOL_SIZE} ] && usage;
[ -z ${VOL_TYPE} ] && usage;

if [[ "${VOL_TYPE}" == "io1" ]] ; then
    VOL_PIOPS=${ARGS_LIST_ARRAY[3]}
	DEVICE_START=${ARGS_LIST_ARRAY[4]}
	VOL_NAME=${ARGS_LIST_ARRAY[5]}
	[ -z ${VOL_PIOPS} ] && usage;
else
	DEVICE_START=${ARGS_LIST_ARRAY[3]}	
	VOL_NAME=${ARGS_LIST_ARRAY[4]}
fi

[ -z ${DEVICE_START} ] && usage;
[ -z ${VOL_NAME} ] && usage;


declare -A DeviceIndices
DeviceIndices=([a]=0 [b]=1 [c]=2 [d]=3 [e]=4 [f]=5 [g]=6 [h]=7 \
			   [i]=8 [j]=9 [k]=10 [l]=11 [m]=12 [n]=13 [o]=14 \
			   [p]=15 [q]=16 [r]=17 [s]=18 [t]=19 [u]=20 [v]=21 \
			   [w]=22 [x]=23 [y]=24 [z]=25)
DeviceNames=(a b c d e f g h i j k l m n o p q r s t u v w x y z)

DEVICE_START_ALPHABET=${DEVICE_START: -1}
DeviceIndexStart=${DeviceIndices[${DEVICE_START_ALPHABET}]}

DEVICE_GENERIC="${DEVICE_START%?}"

COUNTER=0
while [  $COUNTER -lt ${VOL_COUNT} ]; do
	device=${DEVICE_GENERIC}${DeviceNames[${DeviceIndexStart}]}
	device=$(echo ${device} | sed 's/^"\(.*\)"$/\1/')
	let DeviceIndexStart=DeviceIndexStart+1
	let COUNTER=COUNTER+1 
	if [[ "${VOL_TYPE}" == "io1" ]]; then
		volumeid=$(aws ec2 create-volume \
					--region ${AWS_DEFAULT_REGION} \
					--availability-zone ${AWS_DEFAULT_AVAILABILITY_ZONE} \
					--size ${VOL_SIZE} \
					--volume-type ${VOL_TYPE} --iops ${VOL_PIOPS} | ${JQ_COMMAND} '.VolumeId')
	else
		volumeid=$(aws ec2 create-volume \
					--region ${AWS_DEFAULT_REGION} \
					--availability-zone ${AWS_DEFAULT_AVAILABILITY_ZONE} \
					--size ${VOL_SIZE} \
					--volume-type ${VOL_TYPE}| ${JQ_COMMAND} '.VolumeId')
	fi	
	volumeid=$(echo ${volumeid} | sed 's/^"\(.*\)"$/\1/')
	log "Creating new volume ${volumeid}. Waiting for create"
	wait_for_volume_create ${volumeid}	
	
#	Attach volume to the instance and expose with the specified device name
	log "Attaching new volume ${volumeid} as ${device}. Waiting for attach"
	aws ec2 attach-volume --volume-id ${volumeid} --instance-id ${AWS_INSTANCEID} --device ${device}
	wait_for_attach_volume ${volumeid}	
	log "setting device attribute  ${device}:DeleteOnTermination"
	set_device_delete_ontermination ${device}
	log "setting device name  ${device}:$VOL_NAME"
	 aws ec2 create-tags --resources ${volumeid}  --tags Key=Name,Value=${VOL_NAME}
done


			   
log `date` END Creating Volumes and Attaching ${ARGS_LIST}




