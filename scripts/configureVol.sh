#
# ------------------------------------------------------------------
#         Signal SUCCESS OR FAILURE of Wait Handle
# ------------------------------------------------------------------


SCRIPT_DIR=/root/install
if [ -z "${INSTALL_LOG_FILE}" ] ; then
    INSTALL_LOG_FILE=${SCRIPT_DIR}/install.log
fi

log() {
    echo $* 2>&1 | tee -a ${INSTALL_LOG_FILE}
}

usage() {
    cat <<EOF
    Usage: $0
EOF
    exit 0
}

source /root/install/config.sh


[[ $# -ne 0 ]] && usage;

# ------------------------------------------------------------------
#          Configure base vols
# ------------------------------------------------------------------

export USE_NEW_STORAGE=1


function calc { bc -l <<< ${@//[xX]/*}; };

log `date` configureVol.sh

if [ "${IsMasterNode}" == "1" ]; then
	backupSize=$(calc 250x${HostCount})
	if (( ${USE_NEW_STORAGE} == 1 ));
	then
		echo "configureVol.sh: DISABLED"
	else
		sh /root/install/create-attach-single-volume.sh ${backupSize}:gp2:/dev/sde:SAP-HANA-Backup
		sh /root/install/create-attach-single-volume.sh ${backupSize}:gp2:/dev/sdf:SAP-HANA-Backup
		echo ${backup}
	fi
fi

log `date` END configureVol.sh


exit 0
