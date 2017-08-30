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





log `date` signal-failure

#if [ $# -eq 0 ]
#then
#	curl -X PUT -H 'Content-Type:' --data-binary '{"Status" : "FAILURE","Reason" : "The HANA installation did not succeed. Please check installation media.","UniqueId" : "HANAMaster","Data" : "Failure"}' "${WaitForMasterInstallWaitHandle}"

#	echo curl -X PUT -H 'Content-Type:' --data-binary '{"Status" : "FAILURE","Reason" : "The HANA installation did not succeed. Please check installation media.","UniqueId" : "HANAMaster","Data" : "Failure"}' "${WaitForMasterInstallWaitHandle}"
#else

case "$1" in

	HANAINSTALLFAIL) log "The HANA installation did not succeed. Please check installation media."
      
	curl -X PUT -H 'Content-Type:' --data-binary '{"Status" : "FAILURE","Reason" : "The HANA installation did not succeed. Please check installation media.","UniqueId" : "HANAMaster","Data" : "Failure"}' "${WaitForMasterInstallWaitHandle}"

        echo curl -X PUT -H 'Content-Type:' --data-binary '{"Status" : "FAILURE","Reason" : "The HANA installation did not succeed. Please check installation media.","UniqueId" : "HANAMaster","Data" : "Failure"}' "${WaitForMasterInstallWaitHandle}" 
	;;
 
      INCOMPATIBLE) log "Instance Type = X1 and O.S. is not supported with X1"

      curl -X PUT -H 'Content-Type:' --data-binary '{"Status" : "FAILURE","Reason" : "X1 instance type requires minimum kernel version of 3.10, Choose the right operating System and try again","UniqueId" : "HANAMaster","Data" : "Failure"}' "${WaitForMasterInstallWaitHandle}"

      echo curl -X PUT -H 'Content-Type:' --data-binary '{"Status" : "FAILURE","Reason" : "X1 instance type requires minimum kernel version of 3.10, Choose the right operating System and try again","UniqueId" : "HANAMaster","Data" : "Failure"}' "${WaitForMasterInstallWaitHandle}"
      ;;

      INCOMPATIBLE_RHEL) log "Instance Type = X1 and RHEL 6.6 is not supported with X1"

      curl -X PUT -H 'Content-Type:' --data-binary '{"Status" : "FAILURE","Reason" : "RHEL 6.6 is not compatible with X1 instance type. HANA on X1 requires minimum version of RHEL6.7, Choose the right operating System and try again","UniqueId" : "HANAMaster","Data" : "Failure"}' "${WaitForMasterInstallWaitHandle}"

      echo curl -X PUT -H 'Content-Type:' --data-binary '{"Status" : "FAILURE","Reason" : "RHEL 6.6 is not compatible with X1 instance type. HANA on X1 requires minimum version of RHEL 6.7, Choose the right operating System and try again","UniqueId" : "HANAMaster","Data" : "Failure"}' "${WaitForMasterInstallWaitHandle}"
      ;;

      INCOMPATIBLE_RHEL_SCALEOUT) log "RHEL 6.7 is not supported with X1 Scaleout"

      curl -X PUT -H 'Content-Type:' --data-binary '{"Status" : "FAILURE","Reason" : "Scale out deployment with X1 instance type is not compatible with RHEL 6.7, Choose the right operating System and try again","UniqueId" : "HANAMaster","Data" : "Failure"}' "${WaitForMasterInstallWaitHandle}"

      echo curl -X PUT -H 'Content-Type:' --data-binary '{"Status" : "FAILURE","Reason" : "Scale out deployment with X1 instance type is not compatible with RHEL 6.7, Choose the right operating System and try again","UniqueId" : "HANAMaster","Data" : "Failure"}' "${WaitForMasterInstallWaitHandle}"
      ;;

      YUM) log "Instance Type = X1 and yum repo is not supported"

      curl -X PUT -H 'Content-Type:' --data-binary '{"Status" : "FAILURE","Reason" : "Not able to access RedHat update repository, package installation may fail","UniqueId" : "HANAMaster","Data" : "Failure"}' "${WaitForMasterInstallWaitHandle}"

      echo curl -X PUT -H 'Content-Type:' --data-binary '{"Status" : "FAILURE","Reason" : "Not able to access RedHat update repository, package installation may fail","UniqueId" : "HANAMaster","Data" : "Failure"}' "${WaitForMasterInstallWaitHandle}"
      ;;

      ZYPPER) log "Instance Type = X1 and zypper repo is not supported"

      curl -X PUT -H 'Content-Type:' --data-binary '{"Status" : "FAILURE","Reason" : "Not able to access SUSE update repository, package installation may fail","UniqueId" : "HANAMaster","Data" : "Failure"}' "${WaitForMasterInstallWaitHandle}"

      echo curl -X PUT -H 'Content-Type:' --data-binary '{"Status" : "FAILURE","Reason" : "Not able to access SUSE update repository, package installation may fail","UniqueId" : "HANAMaster","Data" : "Failure"}' "${WaitForMasterInstallWaitHandle}"
      ;;

      *) log "Function Not Implemented"

      curl -X PUT -H 'Content-Type:' --data-binary '{"Status" : "FAILURE","Reason" : "signal-failure function not implemented","UniqueId" : "HANAMaster","Data" : "Failure"}' "${WaitForMasterInstallWaitHandle}"

      echo curl -X PUT -H 'Content-Type:' --data-binary '{"Status" : "FAILURE","Reason" : "signal-failure function not implemented","UniqueId" : "HANAMaster","Data" : "Failure"}' "${WaitForMasterInstallWaitHandle}"
      exit 1 
      esac

#fi

log `date` END signal-failure

exit 0

