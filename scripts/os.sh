# ------------------------------------------------------------------
#          RHEL or SLES
# ------------------------------------------------------------------

source /root/install/config.sh

isRHEL() {
    if [ "$MyOS" == "RHEL66SAPHVM" ]; then
        echo 1
    elif [ "$MyOS" == "RHEL67SAPHVM" ]; then
    	echo 1
    elif [ "$MyOS" == "RHEL72SAPHVM" ]; then
    	echo 1
    else
      echo 0
    fi
}

isRHEL6() {
    if [ "$MyOS" == "RHEL66SAPHVM" ]; then
        echo 1
    elif [ "$MyOS" == "RHEL67SAPHVM" ]; then
	echo 1
    else
      echo 0
    fi
}

isRHEL7() {
    if [ "$MyOS" == "RHEL72SAPHVM" ]; then
        echo 1
    else
      echo 0
    fi
}

isSLES() {
    if [ "$MyOS" == "SLES11SP4HVM" ]; then
      echo 1
    elif [ "$MyOS" == "SLES12HVM" ]; then
      echo 1
    elif [ "$MyOS" == "SLES12SP1HVM" ]; then
      echo 1
    else
      echo 0
    fi
}

isSLES11SP4() {
    if [ "$MyOS" == "SLES11SP4HVM" ]; then
      echo 1
    else
      echo 0
    fi
}

isSLES12() {
    if [ "$MyOS" == "SLES12HVM" ]; then
      echo 1
    else
      echo 0
    fi
}

isSLES12SP1() {
    if [ "$MyOS" == "SLES12SP1HVM" ]; then
      echo 1
    else
      echo 0
    fi
}

issignal_check() {
    if [ -e "$SIG_FLAG_FILE" ]; then
      echo 1
    else
      echo 0
    fi
}
