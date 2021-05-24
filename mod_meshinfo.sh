#!/bin/bash -x

#https://github.com/megalloid/bcmdhdscripts

[ -z "$(nvram get odmpid)" ] && ROUTER_MODEL=$(nvram get productid) || ROUTER_MODEL=$(nvram get odmpid)
dir=`dirname $0`

#opkg install  openssh-keygen
# ssh-keygen


readonly SCRIPT_NAME="extStats_mod_meshinfo"
readonly SCRIPT_debug=$1
readonly DHCP_HOSTNAMESMAC="/opt/tmp/dhcp_clients_mac.txt"
readonly CLIENTLIST="/opt/tmp/client-list.txt"
readonly DATA_TEMP_FILE="/opt/tmp/$SCRIPT_NAME.influx"
readonly DATA_FILE="/opt/tmp/$SCRIPT_NAME.influx"


TMP_FOLDER="/opt/tmp/"
timeout="5"
cmd_curl="/usr/bin/curl"
cmd_wget="/usr/bin/wget"
USER="admin"
IP="192.168.2.4"

#ssh ${USER}@${IP} wl > ${TMP_FOLDER}"/${IP}.wl"
#cat ${TMP_FOLDER}"/telekom/telekom_${IP}.json"
