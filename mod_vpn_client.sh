#!/bin/sh
readonly SCRIPT_NAME="extstats"
readonly MOD_NAME="mod_vpn_client"
SCRIPT_DEBUG="${1}" #(true/false)
SCRIPT_DEBUG_SYSLOG="${2}" #(true/false)
SCRIPT_DEBUG_FULL="${3}" #(true/false)

dir=`dirname $0`
CURDATE=`date +%s`

Print_Output(){
	#$1 = message to print, $2 = log level

	if [ "$SCRIPT_DEBUG" = "true" ]; then
		printf "\\e[1m%s: $1\\e[0m\\n" "$SCRIPT_NAME:$MOD_NAME"

		if [ "$SCRIPT_DEBUG_SYSLOG" = "true" ]; then
			logger -t "$SCRIPT_NAME:$MOD_NAME" "$1"
		fi

		if [ "$3" = "true" ]; then
			logger -t "$SCRIPT_NAME:$MOD_NAME" "$1"
		fi
	fi
}

mod_vpn_client(){

    for item in 1 2 3 4 5;
    do
        name="router.vpnClients"
        VPN_STAT_FILE="/etc/openvpn/client${item}/status"
        columns="vpn_client=vpn_client$item"

        if [ -r "$VPN_STAT_FILE" ]; then

            Print_Output $name
            Print_Output $VPN_STAT_FILE
            Print_Output $columns

            tun_r=`cat $VPN_STAT_FILE | grep "TUN/TAP read bytes" | cut -d, -f2`
            tun_w=`cat $VPN_STAT_FILE | grep "TUN/TAP write bytes" | cut -d, -f2`
            tcp_r=`cat $VPN_STAT_FILE | grep "TCP/UDP read bytes" | cut -d, -f2`
            tcp_w=`cat $VPN_STAT_FILE | grep "TCP/UDP write bytes" | cut -d, -f2`
            auth_r=`cat $VPN_STAT_FILE | grep "Auth read bytes" | cut -d, -f2`

            points="tun_r=$tun_r,tun_w=$tun_w,tcp_r=$tcp_r,tcp_w=$tcp_w,auth_r=$auth_r"
            DATA="$name,$columns $points ${CURDATE}000000000"

            Print_Output "Export VPN Client$item data into InfluxDB." true true
            Print_Output "$DATA" true true
  
            $dir/export.sh "$DATA" "$SCRIPT_DEBUG"
        fi

    done
}

mod_vpn_client