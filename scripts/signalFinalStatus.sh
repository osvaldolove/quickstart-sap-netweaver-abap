#!/bin/bash -x

#
# ------------------------------------------------------------------
#         Signal SUCCESS OR FAILURE of Wait Handle
# ------------------------------------------------------------------

source /root/install/config.sh

SCRIPT_DIR="/root/install"
if [ -z "${INSTALL_LOG_FILE}" ] ; then
    INSTALL_LOG_FILE=${SCRIPT_DIR}/install.log
fi

log() {
    echo $* 2>&1 | tee -a ${INSTALL_LOG_FILE}
}

usage() {
    cat <<EOF
    Usage: $0 [0 or 1] #1=FAILURE 0=SUCCESS
EOF
    exit 0
}

set_install_cfn() {
#install the cfn helper scripts
	
	cd /tmp
	wget https://s3.amazonaws.com/cloudformation-examples/aws-cfn-bootstrap-latest.tar.gz
	gzip -df aws-cfn-bootstrap-latest.tar.gz
	tar -xvf aws-cfn-bootstrap-latest.tar
        ln -s /tmp/aws-cfn-bootstrap-1.4 /opt/aws
        chmod -R 755 /tmp/aws-cfn-bootstrap-1.4

	zypper -n install python-pip

	pip install --upgrade setuptools

}


# ------------------------------------------------------------------
#          Read all inputs
# ------------------------------------------------------------------


[[ $# -ne 1 ]] && usage;

set_install_cfn
export PYTHONPATH=/opt/aws:$PYTHONPATH

SIGNAL=$*

log `date` signalFinalStatus.sh

if [ "${SIGNAL}" == "0" ]; then
   /opt/aws/bin/cfn-signal -e 0 -r "SAP Install Success." "${WaitForPASInstallWaitHandle}"
else
   /opt/aws/bin/cfn-signal -e 1 -r "SAP Install Failed."  "${WaitForPASInstallWaitHandle}"
fi

log `date` END signalFinalStatus.sh


exit 0
