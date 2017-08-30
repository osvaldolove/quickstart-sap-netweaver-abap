#!/bin/bash
# ------------------------------------------------------------------
#		   Queue to send interrupt messages to nodes
#      Each node posts its status in a queue (replicated)
#      Other nodes will lookup and interrupt if needed
#      Anyone can create, only master deletes
# ------------------------------------------------------------------

usage() {
  cat <<EOF
  Usage: $0 [options]
    -h print usage
    -q Queue URL [Optional, if available in config.sh]
    -c Check for deploy interrupt message
    -i Print messages in queues
    -p Post deploy interrupt message
EOF
  exit 1
}


[ -f ./config.sh ] && source ./config.sh
[ ! -z ${DeploymentInterruptQ} ] && export QUEUEURL=${DeploymentInterruptQ}
export AWS_DEFAULT_REGION=${REGION}
export JQ_COMMAND=./jq
[ ! -f ${JQ_COMMAND} ] && export JQ_COMMAND=/home/ec2-user/jq
if [ ! -f ${JQ_COMMAND} ]; then
	export JQ_COMMAND=./jq
  wget -O ${JQ_COMMAND} https://s3.amazonaws.com/quickstart-reference/sap/hana/latest/media/jq
  chmod 755 ${JQ_COMMAND}
fi
export PATH=${PATH}:/sbin:/usr/sbin:/usr/local/sbin:/root/bin:/usr/local/bin:/usr/bin:/bin:/usr/bin/X11:/usr/X11R6/bin:/usr/games:/usr/lib/AmazonEC2/ec2-api-tools/bin:/usr/lib/AmazonEC2/ec2-ami-tools/bin:/usr/lib/mit/bin:/usr/lib/mit/sbin
export AWS_CMD=/usr/local/bin/aws
export SIGNALCODE="StopDeploymentNow"

# ------------------------------------------------------------------
#          Read all inputs
# ------------------------------------------------------------------

POSTSTOP=0
CHECKSTOP=0
PRINTMSGS=0
while getopts ":h:q:cip" o; do
    case "${o}" in
      h) usage && exit 0
      ;;
      q) QUEUEURL=${OPTARG}
      ;;
      c) CHECKSTOP=1
      ;;
      p) POSTSTOP=1
      ;;
			i) PRINTMSGS=1
      ;;
      *) usage
      ;;
    esac
done

shift $((OPTIND-1))
[[ $# -gt 0 ]] && usage;

log() {
  echo $* 2>&1 | tee -a ${HANA_LOG_FILE}
}

# ------------------------------------------------------------------
#          Make sure NODECOUNT parameters is filled
# ------------------------------------------------------------------

[ -z ${QUEUEURL} ] && usage
declare -a QUEUEURLs=()
QUEUEURLs[0]=${QUEUEURL}

function PostStopMSG() {
  genJSON='
  {
      "QueueUrl": "QUEUE-REPLACE-ME",
      "MessageBody": "SIGNAL-REPLACE-ME",
      "DelaySeconds": 0,
      "MessageAttributes": {
          "InterruptReason": {
              "StringValue": "Install Error. Bail out now!",
              "DataType": "String"
          }
      }
  }'

  for url in ${QUEUEURLs[@]}; do
    json=$(echo ${genJSON} | sed "s/QUEUE-REPLACE-ME/${url//\//\/}/g")
    json=$(echo ${json} | sed "s/SIGNAL-REPLACE-ME/${SIGNALCODE//\//\/}/g")
    ${AWS_CMD} sqs send-message  --cli-input-json "${json}"
  done
}

function PrintMSGS() {
  genJSON='
  {
      "QueueUrl": "QUEUE-REPLACE-ME",
      "MessageAttributeNames": ["InterruptReason"]
  }'
  for url in ${QUEUEURLs[@]}; do
    json=$(echo ${genJSON} | sed "s/QUEUE-REPLACE-ME/${url//\//\/}/g")
    ${AWS_CMD} sqs receive-message  --cli-input-json "${json}"
  done
}

function IfStopMsgRecvd() {
  genJSON='
  {
      "QueueUrl": "QUEUE-REPLACE-ME",
      "MessageAttributeNames": ["InterruptReason"]
  }'
  for url in ${QUEUEURLs[@]}; do
    json=$(echo ${genJSON} | sed "s/QUEUE-REPLACE-ME/${url//\//\/}/g")
    msg=$(${AWS_CMD} sqs receive-message  --cli-input-json "${json}" | ${JQ_COMMAND}  '.Messages[] | .Body')
    echo ${msg} | sed 's/"//g'
  done
}

if [ $CHECKSTOP -eq 1 ]; then
# Keep your sanity and loop. Sometimes during successive calls, sqs doesn't deliver
  for i in `seq 1 10`;
  do
    stopmsg=$(IfStopMsgRecvd)
    if [ "${stopmsg}" == "$SIGNALCODE" ]
    then
      echo 1
      exit
    fi
  done
  echo 0
fi


if [ $POSTSTOP -eq 1 ]; then
  PostStopMSG
fi

if [ $PRINTMSGS -eq 1 ]; then
  PrintMSGS
fi
