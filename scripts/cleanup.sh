#!/bin/bash


# ------------------------------------------------------------------
#          Cleanup all scripts after install
# ------------------------------------------------------------------


# ------------------------------------------------------------------
#          Choose default log file
# ------------------------------------------------------------------


if [ -z "${HANA_LOG_FILE}" ] ; then
    HANA_LOG_FILE=${SCRIPT_DIR}/install.log
fi

log() {
    echo $* 2>&1 | tee -a ${HANA_LOG_FILE}
}

log `date` BEGIN post-install cleanup

source /root/install/config.sh
export AWS_DEFAULT_REGION=${REGION}

DIR=/root/install/awscli-bundle
if [ -d "$DIR" ]; then
    log "Removing dir ($DIR)"
    rm -rf "$DIR"
fi

cd /root/install

for f in awscli-bundle.zip cluster-watch-engine.sh config.sh install-aws.sh install-hana-master.sh install-hana-worker.sh install-master.sh install-prereq.sh install-worker.sh jq reconcile-ips.py reconcile-ips.sh wait-for-master.sh wait-for-workers.sh debug-log.sh download.sh fence-cluster.sh log2s3.sh README.txt *.sh *.py *.json
do
   FILE=/root/install/${f}
   if [ -f "$FILE" ]; then
      log "Removing file ($FILE)"
      rm -rf "$FILE"
   fi
done

# Do not delete right away because workers may be waiting on this!

if [ "${IsMasterNode}" == "1" ]; then
	sleep 240
	/usr/local/bin/aws dynamodb delete-table --table-name ${TABLE_NAME}
fi

#echo "/root/install has been cleaned up after install" >> /root/install/README.txt

# Finally as part of cleanup, delete the password from log files
for f in /var/log/cloud-init.log  /var/log/messages 
do
  log "Cleaning secret info from $f"
  sed -i '/install-master/d' $f
done

log `date` END post-install cleanup
