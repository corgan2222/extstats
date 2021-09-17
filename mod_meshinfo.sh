#!/bin/bash 

#https://github.com/megalloid/bcmdhdscripts

#exit 

#needs 
# bash 
# install coreutils-timeout

[ -z "$(nvram get odmpid)" ] && ROUTER_MODEL=$(nvram get productid) || ROUTER_MODEL=$(nvram get odmpid)
dir=`dirname $0`


readonly SCRIPT_NAME="extStats_mod_meshinfo"
readonly SCRIPT_debug=$1
readonly DATA_TEMP_FILE="/opt/tmp/$SCRIPT_NAME.stations.influx"
readonly DATA_FILE="/opt/tmp/$SCRIPT_NAME.influx"
readonly SCRIPT_DIR="/jffs/addons/extstats.d"
readonly SCRIPT_CONF="$SCRIPT_DIR/config.conf"
readonly EXTS_SSH_USER=$(grep "EXTS_SSH_USER" "$SCRIPT_CONF" | cut -f2 -d"=")
readonly EXTS_SSH_PW=$(grep "EXTS_SSH_PW" "$SCRIPT_CONF" | cut -f2 -d"=")

readonly CMD_PASSH="$SCRIPT_DIR/passh -p $EXTS_SSH_PW"

readonly TEMP_FOLDER="/tmp"
readonly DHCP_EXTERNAL="/opt/tmp/dhcp_external.csv"
readonly KNOWN_HOST_FILE="/root/.ssh/known_hosts"

#$SCRIPT_DIR/helper_dhcpstaticlist.sh >/dev/null 2>&1

Print_Output(){
  # $1 = print to syslog, $2 = message to print, $3 = log level
	if [ "$SCRIPT_debug" = "true" ]; then
		logger -t "$SCRIPT_NAME" "$2"
		printf "\\e[1m$3%s: $2\\e[0m\\n\\n" "$SCRIPT_NAME"
	else
		printf "\\e[1m$3%s: $2\\e[0m\\n\\n" "$SCRIPT_NAME"
	fi
}

lock()
{
	while [ -f /tmp/$SCRIPT_NAME.lock ]; do
		if [ ! -d /proc/$(cat $TEMP_FOLDER/$SCRIPT_NAME.lock) ]; then
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
    rm -f $DATA_TEMP_FILE
}


# function check_ping()
# {
#     MESH_IP=$(echo "$1")
#     if ($( ping $MESH_IP -c1 > /dev/null )) ; then
#         return 0
#     fi
# }

check_known_hosts_for_ip()
{
    MESH_IP=$(echo "$1")
    isInFile=$(cat $KNOWN_HOST_FILE | grep -c $MESH_IP)   

    #check if meship is known
    if [ $isInFile -eq 0 ]; 
    then
        echo "$MESH_IP not found in $KNOWN_HOST_FILE, try to login"
        say_hello=$($SCRIPT_DIR/passh -P 'Do you want to continue connecting?' -p y $SCRIPT_DIR/passh -t 5 -T -i -p $EXTS_SSH_PW ssh $EXTS_SSH_USER@$mesh_node_ip uname -a)

        echo "$say_hello"
        echo "quit for this round"

        return 1
    else
        echo "$MESH_IP found in $KNOWN_HOST_FILE, login testing"
        login_str=$($SCRIPT_DIR/passh -t 5 -T -p $EXTS_SSH_PW ssh $EXTS_SSH_USER@$mesh_node_ip uname -a | tail +2)

        if [[ -n $login_str ]];
        then
            echo "$login_str"
            return 0
        else
            echo "cant login to $KNOWN_HOST_FILE - $login_str"
            return 1
        fi        
    fi    
}

get_Mesh_Devices()
{
    #get asus mesh devices from nvram
    devices=$(nvram get asus_device_list)

    #Define multi-character delimiter
    delimiter="<"

    #Concatenate the delimiter with the main string
    string=$devices$delimiter

    #Split the text based on the delimiter
    myarray=()
    while [[ $string ]]; do
    myarray+=( "${string%%"$delimiter"*}" )
    string=${string#*"$delimiter"}
    done

    #Print the words after the split
    for value in ${myarray[@]}
    do
        if [[ $i -gt 0 ]] #ignore router
        then
            #get ip            
            ip=$(echo $value | egrep -E -o '(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)' | head -1)
            mac=$(echo $value  | grep -o -E '([[:xdigit:]]{1,2}:){5}[[:xdigit:]]{1,2}')
            
            echo "$ip|$mac"
                     
        fi    
        (( i = i + 1 ))
    done

}


function parse_stations() {
    
    station=$(echo "$1")
    node_ip=$(echo "$2")
    node_mac=$(echo "$3")
    band=$(echo "$4")
    node_name=$(echo "$5")

    STATION_MAC=$(echo "$station" | grep -o -E '([[:xdigit:]]{1,2}:){5}[[:xdigit:]]{1,2}')        
    STATION_IP=$(grep -i $STATION_MAC $DHCP_EXTERNAL | cut -d ';' -f2 )
    STATION_NAME=$(grep -i $STATION_MAC $DHCP_EXTERNAL | cut -d ';' -f3 )

    if [ "$STATION_NAME" = "" ]; then
        #STATION_NAME=$STATION_MAC
        return
    fi
    

    AID=$(echo $station | cut -d' ' -f2)
    CHAN=$(echo $station | cut -d' ' -f3)
    tx1_rate_pkt_raw=$(echo $station | cut -d' ' -f4 | tr -d 'M')
    tx1_rate_pkt=$(expr $tx1_rate_pkt_raw \* 1000)
    rx_rate_pkt_raw=$(echo $station | cut -d' ' -f5 | tr -d 'M')
    rx_rate_pkt=$(expr $rx_rate_pkt_raw \* 1000)
    RSSI_RAW=$(echo $station | cut -d' ' -f6 )
    RSSI=$(expr $RSSI_RAW - 96 )    
    MINRSSI_raw=$(echo $station | cut -d' ' -f7 )
    MINRSSI=$(expr $MINRSSI_raw - 96)
    MAXRSSI_raw=$(echo $station | cut -d' ' -f8 )
    MAXRSSI=$(expr $MAXRSSI_raw - 96 )
    IDLE=$(echo $station | cut -d' ' -f9 )
    CAPS=$(echo $station | cut -d' ' -f12 )
    HTCAPS=$(echo $station | cut -d' ' -f16 )
    ASSOCTIME=$(echo $station | cut -d' ' -f17 | awk -F: '{ print ($1 * 3600) + ($2 * 60) + $3 }' )
    #IEs=$(echo $station | cut -d' ' -f18 )
    #MODE=$(echo $station | cut -d' ' -f19 )
    #RXNSS=$(echo $station | cut -d' ' -f21 )
    #TXNSS=$(echo $station | cut -d' ' -f22 )

    columns="host=$node_name,client=$STATION_MAC,ip=$STATION_IP,hostname=$STATION_NAME,wifiBand=$band"
    points="tx1_rate_pkt=$tx1_rate_pkt,rx_rate_pkt=$rx_rate_pkt,rssi=$RSSI,online=$ASSOCTIME,idle=$IDLE,min_rssi=$MINRSSI,max_rssi=$MAXRSSI,wifiBand=$band"

    CURDATE=`date +%s`
    name="router.wifi.clients2"
    data="$name,$columns $points ${CURDATE}000000000"

    echo $data >> $DATA_TEMP_FILE
    #echo $data    

}

function_parse_Mesh_devices() {
    
    mesh_node_ip=$(echo $1 | cut -d'|' -f1)
    mesh_node_mac=$(echo $1 | cut -d'|' -f2)    

    
    if check_known_hosts_for_ip $mesh_node_ip;
    then
        echo "Mesh Node $mesh_node_ip Successfully checked"
    else
        echo "cant login to $mesh_node_ip, so quit here" 
        unlock
        exit 1
    fi

    mesh_node_name=$(grep -i $mesh_node_mac "$DHCP_EXTERNAL" | cut -d ';' -f3 )

    if [ "$mesh_node_name" = "" ]; then
        mesh_node_name=$($CMD_PASSH ssh $EXTS_SSH_USER@$mesh_node_ip uname -a | tail +2 | awk '{print $2}')    
    fi    

    #get Station Infos

    #get wlanconfig data from external node
    wlc_string_ath0="$CMD_PASSH ssh $EXTS_SSH_USER@$mesh_node_ip wlanconfig ath0 list sta | tail +2"
    wlc_string_ath2="$CMD_PASSH ssh $EXTS_SSH_USER@$mesh_node_ip wlanconfig ath2 list sta | tail +2"
    
    #remove header
    wlc_ath0=$($wlc_string_ath0 | tail +2)
    wlc_ath2=$($wlc_string_ath2 | tail +2)  
 

    #loop through stations for ath0
    while read -r station
    do
        #echo "$station"     
        parse_stations "$station" $mesh_node_ip  $mesh_node_mac 2 $mesh_node_name
    done <<<"$wlc_ath0"

    #loop through stations for ath2
    while read -r station2
    do
        #echo "$station"     
        parse_stations "$station2" $mesh_node_ip  $mesh_node_mac 5 $mesh_node_name
    done <<<"$wlc_ath2"

    #Connections Infos
    function_connections $mesh_node_ip $mesh_node_mac $mesh_node_name

    #Uptime Infos
    function_uptime $mesh_node_ip $mesh_node_mac $mesh_node_name

    #CPU Infos
    function_cpu $mesh_node_ip $mesh_node_mac $mesh_node_name

    #net
    function_net $mesh_node_ip $mesh_node_mac $mesh_node_name

 }

function_connections()
{
    CURDATE=$(date +%s)
    mesh_node_ip=$(echo "$1")
    mesh_node_mac=$(echo "$2")
    mesh_node_name=$(echo "$3")
        
    wifi_24=`wl -i eth6 assoclist | awk '{print $2}' | wc -l`
    wifi_5=`wl -i eth7 assoclist | awk '{print $2}' | wc -l`

    wlc_string_ath0="$CMD_PASSH ssh $EXTS_SSH_USER@$mesh_node_ip wlanconfig ath0 list sta"
    wlc_string_ath2="$CMD_PASSH ssh $EXTS_SSH_USER@$mesh_node_ip wlanconfig ath2 list sta"
    
    wlc_ath0=$($wlc_string_ath0 | wc -l)
    wlc_ath2=$($wlc_string_ath2 | tail +3 | wc -l)

    name="router.connections"
    columns="host=${mesh_node_name},type=connections"
    mod_connections="$name,$columns wifi_24=$wlc_ath0,wifi_5=$wlc_ath2 ${CURDATE}000000000"
    #echo "$mod_connections"
    Print_Output "${SCRIPT_debug}_connections" "$mod_connections" "$WARN"
    $dir/export.sh "$mod_connections" "$SCRIPT_debug"

}

function_uptime()
{
    CURDATE=$(date +%s)
    mesh_node_ip=$(echo "$1")
    mesh_node_mac=$(echo "$2")
    mesh_node_name=$(echo "$3")

    uptime_raw="$CMD_PASSH ssh $EXTS_SSH_USER@$mesh_node_ip cat /proc/uptime"
    uptime_str=$($uptime_raw | tail +2)
    uptime=$(echo $uptime_str | cut -d' ' -f1)

    name="router.uptime"
    columns="host=${mesh_node_name}"
    mod_uptime="${name},${columns} uptime=${uptime} ${CURDATE}000000000"

    Print_Output "${SCRIPT_debug}_uptime" "$mod_uptime" "$WARN"
    $dir/export.sh "$mod_uptime" "$SCRIPT_debug"   

    #echo "$mod_uptime"    
}


function_net(){
    maxint=4294967295
    
    scriptname=`basename $0`

    CURDATE=$(date +%s)
    mesh_node_ip=$(echo "$1")
    mesh_node_mac=$(echo "$2")
    mesh_node_name=$(echo "$3")

    old="/tmp/$scriptname.net.$mesh_node_name.data.old"
    new="/tmp/$scriptname.net.$mesh_node_name.data.new"

    old_epoch_file="/tmp/$scriptname.net.$mesh_node_name.epoch.old"
    DATA_TEMP_FILE_MESH="/tmp/$scriptname.net.$mesh_node_name.influx"
    rm -f $DATA_TEMP_FILE_MESH

    old_epoch=`cat $old_epoch_file`
    new_epoch=`date "+%s"`
    echo $new_epoch > $old_epoch_file

    interval=`expr $new_epoch - $old_epoch` # seconds since last sample

    if [ -f $new ]; then
        awk -v old=$old -v interval=$interval -v maxint=$maxint '{
            getline line < old
            split(line, a)
            if( $1 == a[1] ){
                recv_bytes  = $2 - a[2]
                trans_bytes = $5 - a[5]
                if(recv_bytes < 0) {recv_bytes = recv_bytes + maxint}    # maxint counter rollover
                if(trans_bytes < 0) {trans_bytes = trans_bytes + maxint} # maxint counter rollover
                recv_mbps  = (8 * (recv_bytes) / interval) / 1048576     # mbits per second
                trans_mbps = (8 * (trans_bytes) / interval) / 1048576    # mbits per second
                print $1, recv_mbps, $3 - a[3], $4 - a[4], trans_mbps, $6 - a[6], $7 - a[7]
            }
        }' $new  | while read line; do
            #echo $line
            interface=$(echo $line | cut -d' ' -f1)
            recv_mbps=$(echo $line | cut -d' ' -f2)
            recv_errs=$(echo $line | cut -d' ' -f3)
            recv_drop=$(echo $line | cut -d' ' -f4)
            trans_mbps=$(echo $line | cut -d' ' -f5)
            trans_errs=$(echo $line | cut -d' ' -f6)
            trans_drop=$(echo $line | cut -d' ' -f7)

            name="router.network"
            columns="host=${mesh_node_name},interface=${interface}"
            points="recv_mbps=${recv_mbps},recv_errs=${recv_errs},recv_drop=${recv_drop},trans_mbps=${trans_mbps},trans_errs=${trans_errs},trans_drop=${trans_drop}"
            mod_net_data="$name,${columns} ${points} ${CURDATE}000000000"
            #echo $mod_net_data 
            echo $mod_net_data >> $DATA_TEMP_FILE_MESH

        done
        mv $new $old
    fi

    net_dev_raw="$CMD_PASSH ssh $EXTS_SSH_USER@$mesh_node_ip cat /proc/net/dev | tail +3 | tr ':|' '  '  "
    net_dev_str=$($net_dev_raw | awk '{print $1,$2,$4,$5,$10,$12,$13}' | tail +2)    
    
    echo "$net_dev_str" > $new
    #echo "$net_dev_str"

    $dir/export.sh "$DATA_TEMP_FILE_MESH" "$SCRIPT_debug" "file"
}



function_cpu(){
    
    mesh_node_ip=$(echo "$1")
    mesh_node_mac=$(echo "$2")
    mesh_node_name=$(echo "$3")

    CURDATE=`date +%s`
    name="router.cpu"
    columns="usr sys nic idle io irq sirq"

    top_cpu_cmd="$CMD_PASSH ssh $EXTS_SSH_USER@$mesh_node_ip top -bn1 | head -3 | awk '/CPU/' "
    top_load_cmd="$CMD_PASSH ssh $EXTS_SSH_USER@$mesh_node_ip top -bn1 | head -3 | awk '/Load average:/' "
    processes_cmd="$CMD_PASSH ssh $EXTS_SSH_USER@$mesh_node_ip ps | wc -l"

    top_cpu_str=$($top_cpu_cmd | tail +2)
    top_load_str=$($top_load_cmd | tail +2)
    top_process_str=$($processes_cmd | tail +2 |tr -d '\r' |tr -d '\n')

    points2=$(echo $top_cpu_str | awk '/CPU/ {print $2}' | sed 's/%//g' )
    points4=$(echo $top_cpu_str | awk '/CPU/ {print $4}' | sed 's/%//g' )
    points6=$(echo $top_cpu_str | awk '/CPU/ {print $6}' | sed 's/%//g' )
    points8=$(echo $top_cpu_str | awk '/CPU/ {print $8}' | sed 's/%//g' )
    points10=$(echo $top_cpu_str | awk '/CPU/ {print $10}' | sed 's/%//g' )
    points12=$(echo $top_cpu_str | awk '/CPU/ {print $12}' | sed 's/%//g' )
    points14=$(echo $top_cpu_str | awk '/CPU/ {print $14}' | sed 's/%//g' )

    load1=$(echo $top_load_str | awk '/Load average:/ {print $3}' | sed 's/%//g')
    load5=$(echo $top_load_str | awk '/Load average:/ {print $4}' | sed 's/%//g')
    load15=$(echo $top_load_str| awk '/Load average:/ {print $5}' | sed 's/%//g')


    columns="host=${mesh_node_name}"
    points="usr=$points2,sys=$points4,nic=$points6,idle=$points8,io=$points10,irq=$points12,sirq=$points12,load1=$load1,load5=$load5,load15=$load15,processes=${top_process_str}"
    mod_cpu_data="${name},${columns} ${points} ${CURDATE}000000000"

    Print_Output "${SCRIPT_debug}_cpu" "$mod_cpu_data" "$WARN"
    $dir/export.sh "$mod_cpu_data" "$SCRIPT_debug"
}


mod_mesh(){

    #get list of Asus Mesh Devices
    devices=$(get_Mesh_Devices)

    for device in ${devices[@]}
    do
        function_parse_Mesh_devices $device
    done

    #export stations to influx
    $dir/export.sh "$DATA_TEMP_FILE" "$SCRIPT_debug" "file"

}   

lock
mod_mesh
unlock


# 'AID' = Association ID, a client sequence number assigned by the AP to a station when it first 
#connects, seemingly in consecutive order, and on a per-radio basis.

 

# RXSEQ and TXSEQ may still be unchanged from the Madwifi days, but I haven't 
#yet figured out the significance of these numbers, or especially why 5GHz 
#stations *always* show 0 for TXSEQ and 65535 (0xffff) for RXSEQ - possibly a reporting bug?     

#Following the main IE string indicating operating 802.11 mode, all my stations give a single-digit (bit?) number of either 1 or 0, which sometimes changes (does anyone know the significance of this?), followed by RSN and WME, where RSN = enhanced WPA security as noted above (I think this implies use of the AES cipher rather than TKIP, among other things), and WME = Wireless Multimedi Extensions, a QoS prioritization scheme related to 802.11e.

# AID 	Association Identifier 	Die laufende Nummer des verbundenen Endgeräts auf dieser Schnittstelle
# CHAN 	Channel 	Der Channel auf dem das Endgerät mit dem Access Point verbunden ist
# TXRATE 	Transmit Rate 	Die Senderate/Verbindungsgeschwindigkeit vom Access Point zum Endgerät
# RXRATE 	Receive Rate 	Die Empfangsrate/Verbindungsgeschwindigkeit vom Endgerät zum Access Point (auf Seite des Endgeräts als TX Rate angegeben)
# RSSI 	Received Signal Strength Indication 	Signalstärke der Verbindung von diesem Endgerät (Erläuterung siehe Tabelle RSSI)
# MINRSSI 	Minimum RSSI 	Minimale Signalstärke der Verbindung von diesem Endgerät
# MAXRSSI 	Maximum RSSI 	Maximale Signalstärke der Verbindung von diesem Endgerät
# IDLE 	Idle 	Zeit in Sekunden seit der letzten aktiven Kommunikation dieses Endgeräts
# TXSEQ 	Transmit Sequence 	Das Feld ist meines Erachtens nicht mehr aktuell. Üblicherweise immer 0
# RXSEQ 	Receive Sequence 	Das Feld ist meines Erachtens nicht mehr aktuell. Üblicherweise immer 65535
# CAPS 	Capabilities 	Unterstützte Fähigkeiten/Funktionen des Clients (siehe separate Tabelle Capabilities)
# ACAPS 	Atheros/Advanced Capabilities 	Unterstützte Fähigkeiten/Funktionen des Clients (siehe separate Tabelle Atheros/Advanced Capabilities)
# ERP 	Extended Rate PHYsical 	802.11g definiert z.B. ERP-OFDM & ERP-DSSS/CCK als verpflichtend. In diesem Feld habe ich bisher „b“ und „f“ (2.4 GHz 11gn Dell Laptop) gesehen und muss noch prüfen inwieweit das zuzuordnen ist. Dieses Feld ist nur für 2.4 GHz relevant.
# STATE MAXRATE(DOT11) 	STATE MAXRATE(DOT11) 	Das Feld ist meines Erachtens nicht mehr aktuell. Üblicherweise immer 0
# HTCAPS 	High-Throughput Capabilities 	Unterstützte Fähigkeiten/Funktionen des Clients (siehe separate Tabelle High-Throughput Capabilities)
# ASSOCTIME 	Association Time 	Zeit in hh:mm:ss die dieses Endgerät am Access Point angemeldet ist
# IEs 	Information Elements 	Informationselemente über die unterstützten Funktionen (siehe separate Tabelle Information Elements)
# MODE 	Mode 	Verbindungsmodus mit diesem Endgerät z.B. IEEE80211_MODE_11AC_VHT80 (IEEE 802.11ac mit 80MHz Kanalbreite) oder IEEE80211_MODE_11NG_HT20 (IEEE 802.11ng mit 20 MHz Kanalbreite)
# PSMODE 	Power Save Mode 	Gibt an ob das Endgerät gerade im Power Save Modus (1) ist oder nicht (0)
# RXNSS 	Receive Number of Spatial Streams 	Die Anzahl der Spatial Steams 0-n
# TXNSS 	Transmit Number of Spatial Streams 	Die Anzahl der Spatial Steams 0-n
# Capabilities (CAPS)
# Capability 	Vollständige Bezeichnung (Englisch) 	Erläuterung
# E 	Basic Service Set (BSS) / Extended Service Set (ESS) 	Das werden wir immer sehen
# I 	Independent Basic Service Set (IBSS) 	Nur relevant bei Ad-Hoc Netzen
# c 	Contention Free (CF) Pollable 	Teil von Point Coordination Function (PCF)
# C 	Contention Free (CF) Poll Request 	Teil von Point Coordination Function (PCF)
# P 	Privacy 	Gibt an dass das Endgerät verschlüsseln kann (das sollte immer gesetzt sein!)
# S 	Short Preamble 	Kurze Präambel, war nicht verpflichtend in 802.11b
# B 	Packet Binary Convolutional Coding (PBCC) 	War ein optionaler Teil von 802.11b und hat 22 & 33 Mbps ermöglicht
# A 	Channel Agility 	Gibt an dass Frequency Hopping (FH) und Direct Sequence (DS) zur gleichen Zeit unterstützt werden.
# s 	Short Slot Time 	Gibt an ob das Endgerät die Funktion unterstützt (wird typischerweise nur bei 2.4GHz angegeben, da es eine 802.11g Funktion ist)
# D 	DSSS-OFDM 	Diese Funktion wurde in 802.11g eingeführt/ermöglicht, wobei der Header mit DSSS gesendet wurde und die eigentlichen Daten (Payload) mit OFDM
# Atheros/Advanced Capabilities (ACAPS)

# Diese Tabelle ist nur der Vollständigkeit halber hier aufgeführt. Bei ACAPS handelt es sich um Atheros 802.11 SuperG, was heute im Vergleich zu 802.11ac wohl eher nicht mehr „super“ ist. ;)
# Capability 	Vollständige Bezeichnung (Englisch) 	Erläuterung
# D 	Node Turbo Prime 	Dynamischer Turbo-Modus
# A 	Node Advanced Radar 	Erweiterte Radarerkennung
# T 	Node Boost 	Turbo-Modus
# 0 	None 	Mir sind ACAPS noch nie über den Weg gelaufen, der Wert war immer „0“. Bitte direkt auf die HTCAPS schauen
# High-Throughput Capabilities (HTCAPS)
# Capability 	Vollständige Bezeichnung (Englisch) 	Erläuterung
# A 	Advanced Coding 	Findet man so nirgends, damit ist die Unterstützung von Low-Density-Parity-Check (LDPC) gemeint (seit 802.11n)
# W 	Channel Width 40 	Unterstützung für Kanalbreite von 40 MHz
# P 	Spatial Multiplexing PowerSave (Disabled) 	Stromsparmodus (Power Save) für Spatial Multiplexing deaktiviert (802.11n)
# Q 	Spatial Multiplexing PowerSave Static 	Stromsparmodus (Power Save) für Spatial Multiplexing statisch (802.11n)
# R 	Spatial Multiplexing PowerSave Dynamic 	Stromsparmodus (Power Save) für Spatial Multiplexing dynamisch (802.11n)
# G 	Greenfield 	Greenfield Präambel (802.11n)
# S 	Short Guard Interval (40) 	Short Guard Interval (40)
# D 	Delayed Block-ACK 	Delayed Block-ACK
# M 	Maximum A-MSDU Size 	Das Endgerät teilt seine maximale Aggregated - Mac Service Data Unit (A-MSDU) Größe mit
# Information Elements (IEs)
# Capability 	Vollständige Bezeichnung (Englisch) 	Erläuterung
# WPA 	Wi-Fi Protected Access 	Verschlüsselung (veraltet)
# WME 	Wireless Multimedia Extensions 	Quality-of-Service (QoS)
# ATH 	Atheros Protocol Extensions 	Protokollerweiterungen von Atheros
# VEN 	Vendor-specific Extensions 	(Proprietäre) Erweiterungen eines (unbekannten) Herstellers
# RSN 	Robust Secure Network (RSN) 	Verschlüsselung (aktuell)
# Modes
# Modus 	Erläuterung
# IEEE80211_MODE_AUTO 	IEEE 802.11 Automatisch
# IEEE80211_MODE_11A 	IEEE 802.11a
# IEEE80211_MODE_11B 	IEEE 802.11b
# IEEE80211_MODE_11G 	IEEE 802.11g
# IEEE80211_MODE_FH 	IEEE 802.11 Frequency Hopping (FH)
# IEEE80211_MODE_TURBO_A 	IEEE 802.11 Turbo a
# IEEE80211_MODE_TURBO_G 	IEEE 802.11 Turbo g
# IEEE80211_MODE_11NA_HT20 	IEEE 802.11na (HT20)
# IEEE80211_MODE_11NG_HT20 	IEEE 802.11ng (HT20)
# IEEE80211_MODE_11NA_HT40PLUS 	IEEE 802.11na (HT40+)
# IEEE80211_MODE_11NA_HT40MINUS 	IEEE 802.11na (HT40-)
# IEEE80211_MODE_11NG_HT40PLUS 	IEEE 802.11ng (HT40+)
# IEEE80211_MODE_11NG_HT40MINUS 	IEEE 802.11ng (HT40-)
# IEEE80211_MODE_11NG_HT40 	IEEE 802.11ng (HT40)
# IEEE80211_MODE_11NA_HT40 	IEEE 802.11na (HT40)
# IEEE80211_MODE_11AC_VHT20 	IEEE 802.11ac (VHT20)
# IEEE80211_MODE_11AC_VHT40PLUS 	IEEE 802.11ac (VHT40+)
# IEEE80211_MODE_11AC_VHT40MINUS 	IEEE 802.11ac (VHT40-)
# IEEE80211_MODE_11AC_VHT40 	IEEE 802.11ac (VHT40)
# IEEE80211_MODE_11AC_VHT80 	IEEE 802.11ac (VHT80)
# IEEE80211_MODE_11AC_VHT160 	IEEE 802.11ac (VHT160)
# IEEE80211_MODE_11AC_VHT80_80 	IEEE 802.11ac (VHT80_80)
# Erläuterung zu Received Signal Strength Indication (RSSI)

# Der RSSI-Wert geht bei Stellar Wireless von 0 bis 99. Je höher der Wert ist, desto besser ist die Signalstärke/qualität des Endgeräts. Um den RSSI-Wert in dBm zu konvertieren, zieht man 96 vom RSSI-Wert ab.
# RSSI 	dBm 	Qualität
# 10 	-86 	Schlecht
# 11 	-85 	Schlecht
# 12 	-84 	Schlecht
# 13 	-83 	Schlecht
# 14 	-82 	Schlecht
# 15 	-81 	Schlecht
# 16 	-80 	Schlecht
# 17 	-79 	Schlecht
# 18 	-78 	Schlecht
# 19 	-77 	Schlecht
# 20 	-76 	Schlecht
# 21 	-75 	Schlecht
# 22 	-74 	Ausreichend
# 23 	-73 	Ausreichend
# 24 	-72 	Ausreichend
# 25 	-71 	Ausreichend
# 26 	-70 	Ausreichend
# 27 	-69 	Ausreichend
# 28 	-68 	Ausreichend
# 29 	-67 	Gut
# 30 	-66 	Gut
# 31 	-65 	Gut
# 32 	-64 	Gut
# 33 	-63 	Gut
# 34 	-62 	Gut
# 35 	-61 	Gut
# 36 	-60 	Gut
# 37 	-59 	Gut
# 38 	-58 	Gut
# 39 	-57 	Gut
# 40 	-56 	Gut
# 41 	-55 	Gut
# 42 	-54 	Gut
# 43 	-53 	Gut
# 44 	-52 	Gut
# 45 	-51 	Gut
# 46 	-50 	Gut
# 47 	-49 	Gut
# 48 	-48 	Gut
# 49 	-47 	Gut
# 50 	-46 	Gut
# 51 	-45 	Gut
# 52 	-44 	Gut
# 53 	-43 	Gut
# 54 	-42 	Gut
# 55 	-41 	Gut
# 56 	-40 	Gut 