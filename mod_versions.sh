#!/bin/sh

[ -z "$(nvram get odmpid)" ] && ROUTER_MODEL=$(nvram get productid) || ROUTER_MODEL=$(nvram get odmpid)
dir=`dirname $0`
readonly SCRIPT_NAME="extstats"
readonly MOD_NAME="mod_versions"
readonly SCRIPT_DIR="/jffs/addons/$SCRIPT_NAME.d"
readonly SCRIPT_CONF="$SCRIPT_DIR/config.conf"
readonly SCRIPT_debug=$1
readonly TEMP_FOLDER="/opt/tmp"

#InfluxDB Settings
readonly EXTS_URL=$(grep "EXTS_URL" "$SCRIPT_CONF" | cut -f2 -d"=")
readonly EXTS_DATABASE=$(grep "EXTS_DATABASE" "$SCRIPT_CONF" | cut -f2 -d"=")
readonly EXTS_USERNAME=$(grep "EXTS_USERNAME" "$SCRIPT_CONF" | cut -f2 -d"=")
readonly EXTS_PASSWORD=$(grep "EXTS_PASSWORD" "$SCRIPT_CONF" | cut -f2 -d"=")
readonly EXTS_USESSH=$(grep "EXTS_USESSH" "$SCRIPT_CONF" | cut -f2 -d"=")
readonly EXTS_NOVERIFIY=$(grep "EXTS_NOVERIFIY" "$SCRIPT_CONF" | cut -f2 -d"=")
readonly EXTS_PORT=$(grep "EXTS_PORT" "$SCRIPT_CONF" | cut -f2 -d"=")


# $1 = print to syslog, $2 = message to print, $3 = log level
Print_Output(){
	if [ "$1" = "true" ]; then
		logger -t "$SCRIPT_NAME" "$2"
		printf "\\e[1m$3%s: $2\\e[0m\\n\\n" "$SCRIPT_NAME"
	else
		printf "\\e[1m$3%s: $2\\e[0m\\n\\n" "$SCRIPT_NAME"
	fi
}


mod_versions(){
    CURDATE=`date +%s`

    buildinfo=$(nvram get buildinfo | awk '{print $7}') #merlin@df77b49
    buildno=$(nvram get buildno) # buildno=384.15
    buildno_org=$(nvram get buildno_org) # buildno_org=384.15
    bwdpi_sig_ver=$(nvram get bwdpi_sig_ver) # bwdpi_sig_ver=2.166
    firmver=$(nvram get firmver) # firmver=3.0.0.4

    name="router.versions"
    columns="host=${ROUTER_MODEL},bwdpi_sig_ver=$bwdpi_sig_ver,firmver=${firmver}"
    points="buildno=$buildno,buildno_org=${buildno_org}"
    mod_versions_data="$name,$columns $points ${CURDATE}000000000"
    Print_Output "$SCRIPT_debug" "$mod_versions_data" "$WARN"
    $dir/export.sh "$mod_versions_data" "$SCRIPT_debug"
}


mod_versions 


