#!/bin/sh

[ -z "$(nvram get odmpid)" ] && ROUTER_MODEL=$(nvram get productid) || ROUTER_MODEL=$(nvram get odmpid)
dir=`dirname $0`
readonly SCRIPT_NAME="extStats_mod_wifi_clients"
readonly SCRIPT_debug=$1
readonly DHCP_HOSTNAMESMAC="/opt/tmp/dhcp_clients_mac.txt"
readonly CLIENTLIST="/opt/tmp/client-list.txt"
readonly DATA_TEMP_FILE="/opt/tmp/$SCRIPT_NAME.influx"
readonly DHCP_EXTERNAL="/opt/tmp/dhcp_external.csv"

#generate new clientlist
$SCRIPT_DIR/helper_dhcpstaticlist.sh >/dev/null 2>&1
rm -f $DATA_TEMP_FILE

Print_Output(){
  # $1 = print to syslog, $2 = message to print, $3 = log level
	if [ "$SCRIPT_debug" = "true" ]; then
		logger -t "$SCRIPT_NAME" "$2"
		printf "\\e[1m$3%s: $2\\e[0m\\n\\n" "$SCRIPT_NAME"
	else
		printf "\\e[1m$3%s: $2\\e[0m\\n\\n" "$SCRIPT_NAME"
	fi
}

function lc() {
  if [ $# -eq 0 ]; then
    python -c 'import sys; print(sys.stdin.read().lower())'
  else
    for i in "$@"; do
      echo $i | python -c 'import sys; print(sys.stdin.read().lower())'
    done
  fi
}


lock()
{
	while [ -f /tmp/$SCRIPT_NAME.lock ]; do
		if [ ! -d /proc/$(cat /tmp/$SCRIPT_NAME.lock) ]; then
			echo "WARNING : Lockfile detected but process $(cat /tmp/$SCRIPT_NAME.lock) does not exist !"
			rm -f /tmp/$SCRIPT_NAME.lock
		fi
		sleep 1
	done
	echo $$ > /tmp/$SCRIPT_NAME.lock
}

unlock()
{
	rm -f /tmp/$SCRIPT_NAME.lock
}

mod_wifi_clients()
{

  wifiInterface=$(nvram get wl_ifnames)
  #echo $wifiInterface

  for wlan in $wifiInterface; do
    clients=$(wl -i $wlan assoclist | awk '{print $2}')
    #printf "$wlan \n"

        for client in $clients; do

            if [ ! -d $DHCP_EXTERNAL ]; then
              STATION_NAME=$(grep -i $client $DHCP_EXTERNAL | cut -d ';' -f3 )
              ip=$(grep -i $client $DHCP_EXTERNAL | cut -d ';' -f2 )
            else
              client_lc=$(lc "$client")
              ip=$(grep $client_lc /proc/net/arp | awk '{print $1}')

              if [ "$ip" = "" ]; then
                ip=$client
              fi
              #host=$(grep -i $client_lc /mnt/routerUSB/scripts/clients.txt | awk '{print $1}')
              STATION_NAME=$(grep -i $client_lc $DHCP_HOSTNAMESMAC | awk '{print $1}')                       

              if [ "$STATION_NAME" = "" ]; then
                  STATION_NAME=$(grep -i $client_lc $CLIENTLIST | head -1 | awk '{print $1}')                
                  if [ "$STATION_NAME" = "" ]; then
                    STATION_NAME=$client
                  fi
              fi
            fi

            wl_info=$(wl -i $wlan sta_info $client)            

            rsi_antenna1=$(echo "$wl_info" | awk '/per antenna rssi of last rx data frame/ {print $9}')
            rsi_antenna2=$(echo "$wl_info" | awk '/per antenna rssi of last rx data frame/ {print $10}')
            rsi_antenna3=$(echo "$wl_info" | awk '/per antenna rssi of last rx data frame/ {print $11}')
            rsi_antenna4=$(echo "$wl_info" | awk '/per antenna rssi of last rx data frame/ {print $12}')

            rsi_antenna_avg_1=$(echo "$wl_info" | awk '/per antenna average rssi of rx data frames/ {print $9}')
            rsi_antenna_avg_2=$(echo "$wl_info" | awk '/per antenna average rssi of rx data frames/ {print $10}')
            rsi_antenna_avg_3=$(echo "$wl_info" | awk '/per antenna average rssi of rx data frames/ {print $11}')
            rsi_antenna_avg_4=$(echo "$wl_info" | awk '/per antenna average rssi of rx data frames/ {print $12}')

            noise_antenna_1=$(echo "$wl_info" | awk '/per antenna noise floor/ {print $5}')
            noise_antenna_2=$(echo "$wl_info" | awk '/per antenna noise floor/ {print $6}')
            noise_antenna_3=$(echo "$wl_info" | awk '/per antenna noise floor/ {print $7}')
            noise_antenna_4=$(echo "$wl_info" | awk '/per antenna noise floor/ {print $8}')

            rx_rate_pkt=$(echo "$wl_info" | awk '/rate of last rx pkt:/ {print $6}')
            tx1_rate_pkt=$(echo "$wl_info" | awk '/rate of last tx pkt:/ {print $6}')
            tx2_rate_pkt=$(echo "$wl_info" | awk '/rate of last tx pkt:/ {print $9}')

            link_bandwidth=$(echo "$wl_info" | awk '/link bandwidth/ {print $4}')
            tx_failures=$(echo "$wl_info" | awk '/tx failures:/ {print $3}')
            rx_decrypt_failures=$(echo "$wl_info" | awk '/rx decrypt failures:/ {print $4}')

            idle=$(echo "$wl_info" | awk '/idle/ {print $2}')
            online=$(echo "$wl_info" | awk '/in network/ {print $3}')
            rssi=$(wl -i $wlan rssi $client)

            if [ "$wlan" = "eth6" ]; then
              chann="2"
            elif [ "$wlan" = "eth7"  ]; then
              chann="5"
            fi            

            columns="host=${ROUTER_MODEL},client=$client,ip=$ip,hostname=$STATION_NAME,wifiBand=$chann"
            points="tx2_rate_pkt=$tx2_rate_pkt,tx1_rate_pkt=$tx1_rate_pkt,rx_rate_pkt=$rx_rate_pkt,rssi=$rssi,online=$online,rx_rate_pkt=$rx_rate_pkt,rsi_antenna1=$rsi_antenna1,rsi_antenna2=$rsi_antenna2,rsi_antenna3=$rsi_antenna3,rsi_antenna4=$rsi_antenna4,rsi_antenna_avg_1=$rsi_antenna_avg_1,rsi_antenna_avg_2=$rsi_antenna_avg_2,rsi_antenna_avg_3=$rsi_antenna_avg_3,rsi_antenna_avg_4=$rsi_antenna_avg_4,noise_antenna_1=$noise_antenna_1,noise_antenna_2=$noise_antenna_2,noise_antenna_3=$noise_antenna_3,noise_antenna_4=$noise_antenna_4,wifiBand=$chann,link_bandwidth=$link_bandwidth,tx_failures=$tx_failures,rx_decrypt_failures=$rx_decrypt_failures,wifiBand=$chann"
            
            #echo $columns
            #echo $points

            CURDATE=`date +%s`
            name="router.wifi.clients2"
            data="$name,$columns $points ${CURDATE}000000000"

            echo $data >> $DATA_TEMP_FILE
            echo $data
            
        done;
  done;
  
  $dir/export.sh "$DATA_TEMP_FILE" "$SCRIPT_debug" "file"

}

rm -f $DATA_TEMP_FILE
lock
mod_wifi_clients
unlock

#/opt/bin/bash $dir/mod_meshinfo.sh