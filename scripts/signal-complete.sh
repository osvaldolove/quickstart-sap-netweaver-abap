#
# ------------------------------------------------------------------
#         Signal Completion of Wait Handle
# ------------------------------------------------------------------


SCRIPT_DIR=/root/install/
if [ -z "${HANA_LOG_FILE}" ] ; then
    HANA_LOG_FILE=${SCRIPT_DIR}/install.log
fi

log() {
    echo $* 2>&1 | tee -a ${HANA_LOG_FILE}
}

usage() { 
    cat <<EOF
    Usage: $0
EOF
    exit 0
}

source /root/install/config.sh

# ------------------------------------------------------------------
#          Read all inputs
# ------------------------------------------------------------------


[[ $# -ne 0 ]] && usage;


log `date` signal-complete

echo curl -X PUT -H 'Content-Type:' --data-binary '{"Status" : "SUCCESS","Reason" : "The HANA Master server has been installed and is ready","UniqueId" : "HANAMaster","Data" : "Done"}' "${WaitForMasterInstallWaitHandle}"

curl -X PUT -H 'Content-Type:' --data-binary '{"Status" : "SUCCESS","Reason" : "The HANA Master server has been installed and is ready","UniqueId" : "HANAMaster","Data" : "Done"}' "${WaitForMasterInstallWaitHandle}"

log `date` END signal-complete

exit 0








