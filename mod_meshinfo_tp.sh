#!/bin/bash 

#https://github.com/megalloid/bcmdhdscripts

[ -z "$(nvram get odmpid)" ] && ROUTER_MODEL=$(nvram get productid) || ROUTER_MODEL=$(nvram get odmpid)
dir=`dirname $0`


readonly SCRIPT_NAME="extStats_mod_meshinfo_tp"
readonly SCRIPT_debug=$1
readonly DATA_TEMP_FILE="/opt/tmp/$SCRIPT_NAME.stations.influx"
readonly DATA_FILE="/opt/tmp/$SCRIPT_NAME.influx"
readonly SCRIPT_DIR="/jffs/addons/extstats.d"
readonly SCRIPT_CONF="$SCRIPT_DIR/config.conf"
#readonly CMD_PASSH="$SCRIPT_DIR/passh"
readonly TEMP_FOLDER="/tmp"
readonly DHCP_EXTERNAL="/opt/tmp/dhcp_external.csv"
readonly KNOWN_HOST_FILE="/root/.ssh/known_hosts"

readonly EXTS_SSH_USER="admin"
readonly EXTS_SSH_PW="corgan80982"
readonly EXTS_TP_IP="192.168.2.248"


readonly CMD_PASSH="$SCRIPT_DIR/passh -t 5 -T -p $EXTS_SSH_PW"
    
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

check_known_hosts_for_ip()
{
    MESH_IP=$(echo "$1")
    isInFile=$(cat $KNOWN_HOST_FILE | grep -c $MESH_IP)   

    #check if meship is known
    if [ $isInFile -eq 0 ]; 
    then
        echo "$MESH_IP not found in $KNOWN_HOST_FILE, try to login"
        say_hello=$($SCRIPT_DIR/passh -P 'Do you want to continue connecting?' -p y $SCRIPT_DIR/passh -t 5 -T -i -p $EXTS_SSH_PW ssh $EXTS_SSH_USER@$MESH_IP uname -a)

        echo "$say_hello"
        echo "quit for this round"

        return 1
    else
        echo "$MESH_IP found in $KNOWN_HOST_FILE, login testing"
        login_str=$($SCRIPT_DIR/passh -t 5 -T -p $EXTS_SSH_PW ssh $EXTS_SSH_USER@$MESH_IP uname -a | tail +2)

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
    
    # echo "$STATION_IP"
    # echo "mac $STATION_MAC"        
    # echo "name $STATION_NAME"

    AID=$(echo $station | cut -d' ' -f2)
    CHAN=$(echo $station | cut -d' ' -f3)
    tx1_rate_pkt_raw=$(echo $station | cut -d' ' -f4 | tr -d 'M')
    tx1_rate_pkt=$(expr $tx1_rate_pkt_raw \* 1000)
    rx_rate_pkt_raw=$(echo $station | cut -d' ' -f5 | tr -d 'M')
    rx_rate_pkt=$(expr $rx_rate_pkt_raw \* 1000)
    RSSI_RAW=$(echo $station | cut -d' ' -f6 )
    RSSI=$(expr $RSSI_RAW - 96 )    
    #RSSI=$RSSI_RAW
    IDLE=$(echo $station | cut -d' ' -f7 )
    TXSEQ=$(echo $station | cut -d' ' -f8 )
    RXSEQ=$(echo $station | cut -d' ' -f9 )
#    CAPS=$(echo $station | cut -d' ' -f10 )
#    ACAPS=$(echo $station | cut -d' ' -f11 )
#    ERP=$(echo $station | cut -d' ' -f12 )
#    ERP=$(echo $station | cut -d' ' -f12 )


    columns="host=$node_name,client=$STATION_MAC,ip=$STATION_IP,hostname=$STATION_NAME,wifiBand=$band"
    points="tx1_rate_pkt=$tx1_rate_pkt,rx_rate_pkt=$rx_rate_pkt,rssi=$RSSI,idle=$IDLE,TXSEQ=$TXSEQ,RXSEQ=$RXSEQ,wifiBand=$band"

    CURDATE=`date +%s`
    name="router.wifi.clients2"
    data="$name,$columns $points ${CURDATE}000000000"

    echo $data >> $DATA_TEMP_FILE
    echo $data    

}

function_parse_stations() {
    
    #get Station Infos

    if check_known_hosts_for_ip $EXTS_TP_IP;
    then
        echo "TP Node $EXTS_TP_IP Successfully checked"
    else
        echo "cant login to $EXTS_TP_IP, so quit here" 
        unlock
        exit 1
    fi
   

    #get wlanconfig data from external node
    wlc_string_ath0="$CMD_PASSH ssh $EXTS_SSH_USER@$EXTS_TP_IP wlanconfig ath0 list sta "
    
    #remove header
    wlc_ath0=$($wlc_string_ath0 | tail +3)
    #echo "$wlc_ath0"

    #loop through stations for ath0
    while read -r station
    do
        #echo "$station"     
        parse_stations "$station" $EXTS_TP_IP  "" 2 "TP-Link-Pharos_oben"
    done <<<"$wlc_ath0"

    #echo ${DATA_TEMP_FILE}
    #export stations to influx
    $dir/export.sh "$DATA_TEMP_FILE" "$SCRIPT_debug" "file"

 }


lock
function_parse_stations
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