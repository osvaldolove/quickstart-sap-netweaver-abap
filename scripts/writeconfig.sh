#!/bin/bash

# export var to config file
usage() { 
    cat <<EOF
    Usage: $0 [variable=value]
EOF
    exit 0
}


# ------------------------------------------------------------------
#          Read all inputs
# ------------------------------------------------------------------


[[ $# -ne 1 ]] && usage;

KV=$1

key=$(echo $KV | awk -F'=' '{print $1}')
value=$(echo $KV | awk -F'=' '{print $2}')

echo "export ${key}=${value}" >> /root/install/config.sh