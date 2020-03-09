#!/bin/sh
#
# Traffic logging tool for DD-WRT-based routers using InfluxDB
#
# Based on work from Emmanuel Brucy (e.brucy AT qut.edu.au)
# Based on work from Fredrik Erlandsson (erlis AT linux.nu)
# Based on traff_graph script by twist - http://wiki.openwrt.org/RrdTrafficWatch

# Edit by Corgan

# 1 https://www.instructables.com/id/How-to-graph-home-router-metrics/
#

[ -z "$(nvram get odmpid)" ] && ROUTER_MODEL=$(nvram get productid) || ROUTER_MODEL=$(nvram get odmpid)
dir=`dirname $0`
readonly SCRIPT_NAME="extStats"
readonly SCRIPT_debug=$2
readonly DHCP_HOSTNAMESMAC="/opt/tmp/dhcp_clients_mac.txt"
readonly MOD_NAME="mod_client_traffic"
readonly DATA_TEMP_FILE="/opt/tmp/$MOD_NAME.influx"
#generate new clientlist
$SCRIPT_DIR/helper_dhcpstaticlist.sh >/dev/null 2>&1


function lc() {
  if [ $# -eq 0 ]; then
    python -c 'import sys; print sys.stdin.read().decode("utf-8").lower()'
  else
    for i in "$@"; do
      echo $i | python -c 'import sys; print sys.stdin.read().decode("utf-8").lower()'
    done
  fi
}

# $1 = print to syslog, $2 = message to print, $3 = log level
Print_Output(){
	if [ "$SCRIPT_debug" = "true" ]; then
		logger -t "$MOD_NAME" "$2"
		printf "\\e[1m$3%s: $2\\e[0m\\n\\n" "$MOD_NAME"
	else
		printf "\\e[1m$3%s: $2\\e[0m\\n\\n" "$MOD_NAME"
	fi
}

lock()
{
	while [ -f /tmp/$MOD_NAME.lock ]; do
		if [ ! -d /proc/$(cat /tmp/$MOD_NAME.lock) ]; then
			echo "WARNING : Lockfile detected but process $(cat /tmp/$MOD_NAME.lock) does not exist !"
			rm -f /tmp/$MOD_NAME.lock
		fi
		sleep 1
	done
	echo $$ > /tmp/$MOD_NAME.lock
}

unlock()
{
	rm -f /tmp/$MOD_NAME.lock
}

LAN_IFNAME=$(nvram get lan_ifname)
WAN_IFNAME=$(nvram get wan_ifname)
rm -f $DATA_TEMP_FILE


case ${1} in
	"setup" )

		# Create the RRDIPT2 CHAIN (it doesn't matter if it already exists).
		# This one is for the whole LAN -> WAN and WAN -> LAN traffic measurement
		iptables -N RRDIPT2 #2> /dev/null

		# Add the RRDIPT2 CHAIN to the FORWARD chain (if non existing).
		iptables -L FORWARD -n | grep RRDIPT2 #> /dev/null
		if [ $? -ne 0 ]; then
			iptables -L FORWARD -n | grep "RRDIPT2" #> /dev/null
			if [ $? -eq 0 ]; then
				echo "DEBUG : iptables chain misplaced, recreating it..."
				iptables -D FORWARD -j RRDIPT2
			fi
			iptables -I FORWARD -j RRDIPT2
		fi

		# Add the LAN->WAN and WAN->LAN rules to the RRDIPT2 chain
		iptables -nvL RRDIPT2 | grep ${WAN_IFNAME}.*${LAN_IFNAME} #>/dev/null
		if [ $? -ne 0 ]; then
			iptables -I RRDIPT2 -i ${WAN_IFNAME} -o ${LAN_IFNAME} -j RETURN
		fi

		iptables -nvL RRDIPT2 | grep ${LAN_IFNAME}.*${WAN_IFNAME} #>/dev/null
		if [ $? -ne 0 ]; then
			iptables -I RRDIPT2 -i ${LAN_IFNAME} -o ${WAN_IFNAME} -j RETURN
		fi

		# Create the RRDIPT CHAIN (it doesn't matter if it already exists).
		iptables -N RRDIPT #2> /dev/null

		# Add the RRDIPT CHAIN to the FORWARD chain (if non existing).
		iptables -L FORWARD -n | grep RRDIPT[^2] #> /dev/null
		if [ $? -ne 0 ]; then
			iptables -L FORWARD -n | grep "RRDIPT" #> /dev/null
			if [ $? -eq 0 ]; then
				echo "DEBUG : iptables chain misplaced, recreating it..."
				iptables -D FORWARD -j RRDIPT
			fi
			iptables -I FORWARD -j RRDIPT
		fi

		# For each host in the ARP table
		grep ${LAN_IFNAME} /proc/net/arp | while read IP TYPE FLAGS MAC MASK IFACE
		do
			# Add iptable rules (if non existing).
			#echo "${IP}"

			iptables -nL RRDIPT | grep "${IP} " #> /dev/null
			if [ $? -ne 0 ]; then
				iptables -I RRDIPT -d ${IP} -j RETURN
				iptables -I RRDIPT -s ${IP} -j RETURN
			fi
		done	
		;;

	"update" )
		lock

		# Read and reset counters
		iptables -L RRDIPT -vnxZ -t filter > /tmp/traffic_$$.tmp
		iptables -L RRDIPT2 -vnxZ -t filter > /tmp/global_$$.tmp
		CURDATE=`date +%s`

		grep -Ev "0x0|IP" /proc/net/arp  | while read IP TYPE FLAGS MAC MASK IFACE
		do
			IN=0
			OUT=0
			# Add new data to the graph. 
				grep ${IP} /tmp/traffic_$$.tmp | while read PKTS BYTES TARGET PROT OPT IFIN IFOUT SRC DST
				do
				if [ "${DST}" = "${IP}" ]; then
					IN=${BYTES}
				fi

				if [ "${SRC}" = "${IP}" ]; then
					OUT=${BYTES}
				fi

				client_lc=$(lc "$MAC")

				ip=$(grep $client_lc /proc/net/arp | awk '{print $1}' | head -1)
				host=$(grep -i $client_lc $DHCP_HOSTNAMESMAC | awk '{print $1}' | head -1)

				#$ipp=$(echo $ip | awk '{print $1}')
				#echo $ipp

				if [ -z "$ip" ]; then
					ip=$MAC
				fi
				# echo $ip

				if [ -z "$host" ]; then
					host=$MAC
				fi

				if [[ -n "$ip" ]] && [[ -n "$host" ]] && [[ -n "$MAC" ]]; then
					columns="host=${ROUTER_MODEL},mac=$MAC,ip=$ip,hostname=$host"
					points="inBytes=${IN},outBytes=${OUT}"
					name="router.client_traffic"
					CURDATE=`date +%s`
					#echo "1 host $host ip $ip mac $client_lc"

					data="$name,$columns $points ${CURDATE}000000000"
					echo $data >> $DATA_TEMP_FILE

					#printf "$client_lc \t $ip \t $host \n"
					#echo $data
					#curl -is -XPOST "https://${DBURL}/write?db=${DBNAME}&u=${USER}&p=${PASS}" --data-binary "$data" >/dev/null 2>&1

					#Print_Output "$SCRIPT_debug" "$data" "$WARN"
					#$dir/export.sh "$data" "$SCRIPT_debug" "file"

				fi
			done
		done

		# Chain RRDIPT2 Processing
		IN=0
		OUT=0
		grep ${LAN_IFNAME} /tmp/global_$$.tmp | while read PKTS BYTES TARGET PROT OPT IFIN IFOUT SRC DST
		do
			if [ "${IFIN}" = "${LAN_IFNAME}" ]; then
				IN=${BYTES}
			fi

			if [ "${IFIN}" = "${WAN_IFNAME}" ]; then
				OUT=${BYTES}
			fi

			client_lc=$(lc "$MAC")
			ip=$(grep $client_lc /proc/net/arp | awk '{print $1}' | head -1)
			host=$(grep -i $client_lc $DHCP_HOSTNAMESMAC | awk '{print $1}' | head -1)

			if [ -z "$ip" ]; then
				ip=$MAC
			fi

			if [ -z "$host" ]; then
				host=$MAC
			fi

			if [[ -n "$ip" ]] && [[ -n "$host" ]] && [[ -n "$MAC" ]]; then
				columns="host=${ROUTER_MODEL},mac=$MAC,ip=$ip,hostname=$host"
				points="inBytes=${IN},outBytes=${OUT}"
				name="router.client_traffic"
				CURDATE=`date +%s`

				#echo "2 host $host ip $ip mac $client_lc"
				#data="$name,$columns $points ${CURDATE}000000000"

				data="$name,$columns $points ${CURDATE}000000000"
				echo $data >> $DATA_TEMP_FILE

				#Print_Output "$SCRIPT_debug" "$data" "$WARN"
				#$dir/export.sh "$data" "$SCRIPT_debug"

			fi
		done

		$dir/export.sh "$DATA_TEMP_FILE" "$SCRIPT_debug" "file"

		# Free some memory
		rm -f /tmp/*_$$.tmp
		rm -f $DATA_TEMP_FILE
		unlock
		;;

	*)
		echo "Usage : $0 {setup|update}"
		echo "Options : "
		echo "   $0 setup"
		echo "   $0 update"
		exit
		;;
esac

