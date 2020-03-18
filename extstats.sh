#!/bin/sh

#####################################################
##                                                 ##
##                __  _____  __          __        ##
##   ___   _  __ / /_/ ___/ / /_ ____ _ / /_ _____ ##
##  / _ \ | |/_// __/\__ \ / __// __ `// __// ___/ ##
## /  __/_>  < / /_ ___/ // /_ / /_/ // /_ (__  )  ##
## \___//_/|_| \__//____/ \__/ \__,_/ \__//____/   ##
##                                                 ##
##      Corgan - Stefan Knaak 2020                 ##
##                                                 ##
#####################################################
##                                                 ##
##      https://github.com/corgan2222/extstats     ##
##                                                 ##
#####################################################

### Start of script variables ###
readonly SCRIPT_NAME="extstats"
readonly SCRIPT_NAME_LOWER=$(echo $SCRIPT_NAME | tr 'A-Z' 'a-z' | sed 's/d//')
readonly SCRIPT_DIR="/jffs/addons/$SCRIPT_NAME_LOWER.d"
readonly SCRIPT_CONF="$SCRIPT_DIR/config.conf"
readonly SCRIPT_VERSION="v0.1.3"
readonly SCRIPT_BRANCH="master"
readonly SCRIPT_REPO="https://raw.githubusercontent.com/corgan2222/""$SCRIPT_NAME""/""$SCRIPT_BRANCH"
readonly DHCP_HOSTNAMESMAC="/opt/tmp/dhcp_clients_mac.txt"
readonly DHCP_HOSTNAMESMAC_CSV="/opt/tmp/dhcp_clients_mac.csv"
readonly DHCP_HOSTNAMESMAC_SB_IP="/opt/tmp/dhcp_clients_mac_sb_ip.txt"
readonly DHCP_HOSTNAMESMAC_SB_MAC="/opt/tmp/dhcp_clients_mac_sb_mac.txt"
readonly DHCP_HOSTNAMESMAC_SB_HOST="/opt/tmp/dhcp_clients_mac_sb_host.txt"
[ -z "$(nvram get odmpid)" ] && ROUTER_MODEL=$(nvram get productid) || ROUTER_MODEL=$(nvram get odmpid)
[ -f /opt/bin/sqlite3 ] && SQLITE3_PATH=/opt/bin/sqlite3 || SQLITE3_PATH=/usr/sbin/sqlite3
### End of script variables ###

readConfigData()
{
	if [ -f "$SCRIPT_CONF" ]; then
		EXTS_URL=$(grep "EXTS_URL" "$SCRIPT_CONF" | cut -f2 -d"=")
		EXTS_DATABASE=$(grep "EXTS_DATABASE" "$SCRIPT_CONF" | cut -f2 -d"=")
		EXTS_USERNAME=$(grep "EXTS_USERNAME" "$SCRIPT_CONF" | cut -f2 -d"=")
		EXTS_PASSWORD=$(grep "EXTS_PASSWORD" "$SCRIPT_CONF" | cut -f2 -d"=")
		EXTS_USESSH=$(grep "EXTS_USESSH" "$SCRIPT_CONF" | cut -f2 -d"=")
		EXTS_NOVERIFIY=$(grep "EXTS_NOVERIFIY" "$SCRIPT_CONF" | cut -f2 -d"=")
		EXTS_PORT=$(grep "EXTS_PORT" "$SCRIPT_CONF" | cut -f2 -d"=")
		if [ "$EXTS_USESSH" != "false" ]; then HTTP="https"; else HTTP="http"; fi
		if [ "$EXTS_NOVERIFIY" == "true" ]; then VERIFIY="-k"; fi #ignore ssl error

		CURL_OPTIONS="${VERIFIY} -POST" #get is deprecated
		UN_COUNT=$(echo $EXTS_PASSWORD | wc -m)
		UP_COUNT=$(echo $EXTS_PASSWORD | wc -m)

		if [[  ${UP_COUNT} -gt 1 ]]; then EXTS_PW_STRING=":${EXTS_PASSWORD}"; fi
		if [[  ${UN_COUNT} -gt 1 ]]; then EXTS_USER_STRING="-u ${EXTS_USERNAME}"; fi

		CURL_USER="${EXTS_USER_STRING}${EXTS_PW_STRING}"
		TEST_URL="${HTTP}://${EXTS_URL}:${EXTS_PORT}"
	fi
}

readConfigData
### Start of output format variables ###
readonly CRIT="\\e[41m"
readonly ERR="\\e[31m"
readonly WARN="\\e[33m"
readonly PASS="\\e[32m"

### End of output format variables ###

# $1 = print to syslog, $2 = message to print, $3 = log level
Print_Output(){
	if [ "$1" = "true" ]; then
		logger -t "$SCRIPT_NAME" "$2"
		printf "\\e[1m$3%s: $2\\e[0m\\n\\n" "$SCRIPT_NAME"
	else
		printf "\\e[1m$3%s: $2\\e[0m\\n\\n" "$SCRIPT_NAME"
	fi
}

### Code for this function courtesy of https://github.com/decoderman- credit to @thelonelycoder ###
Firmware_Version_Check(){
	echo "$1" | awk -F. '{ printf("%d%03d%03d%03d\n", $1,$2,$3,$4); }'
}
############################################################################

### Code for these functions inspired by https://github.com/Adamm00 - credit to @Adamm ###
Check_Lock(){
	if [ -f "/tmp/$SCRIPT_NAME.lock" ]; then
		ageoflock=$(($(date +%s) - $(date +%s -r /tmp/$SCRIPT_NAME.lock)))
		if [ "$ageoflock" -gt 60 ]; then
			Print_Output "true" "Stale lock file found (>60 seconds old) - purging lock" "$ERR"
			kill "$(sed -n '1p' /tmp/$SCRIPT_NAME.lock)" >/dev/null 2>&1
			Clear_Lock
			echo "$$" > "/tmp/$SCRIPT_NAME.lock"
			return 0
		else
			Print_Output "true" "Lock file found (age: $ageoflock seconds) - ping test likely currently running" "$ERR"
			if [ -z "$1" ]; then
				exit 1
			else
				return 1
			fi
		fi
	else
		echo "$$" > "/tmp/$SCRIPT_NAME.lock"
		return 0
	fi
}

Clear_Lock(){
	rm -f "/tmp/$SCRIPT_NAME.lock" 2>/dev/null
	return 0
}

Update_File(){

	tmpfile="/tmp/$1"
	Download_File "$SCRIPT_REPO/$1" "$tmpfile"
	if ! diff -q "$tmpfile" "$SCRIPT_DIR/$1" >/dev/null 2>&1; then
		Download_File "$SCRIPT_REPO/$1" "$SCRIPT_DIR/$1"
		chmod 0755 "$SCRIPT_DIR/$1"
		Print_Output "true" "New version of $1 downloaded" "$PASS"
	fi
	rm -f "$tmpfile"


}

Update_Version(){
	if [ -z "$1" ]; then
		doupdate="false"
		localver=$(grep "SCRIPT_VERSION=" /jffs/scripts/"$SCRIPT_NAME" | grep -m1 -oE 'v[0-9]{1,2}([.][0-9]{1,2})([.][0-9]{1,2})')
		/usr/sbin/curl -fsL --retry 3 "$SCRIPT_REPO/$SCRIPT_NAME.sh" | grep -qF "corgan2222" || { Print_Output "true" "404 error detected - stopping update" "$ERR"; return 1; }
		serverver=$(/usr/sbin/curl -fsL --retry 3 "$SCRIPT_REPO/$SCRIPT_NAME.sh" | grep "SCRIPT_VERSION=" | grep -m1 -oE 'v[0-9]{1,2}([.][0-9]{1,2})([.][0-9]{1,2})')
		if [ "$localver" != "$serverver" ]; then
			doupdate="version"
		else
			localmd5="$(md5sum "/jffs/scripts/$SCRIPT_NAME" | awk '{print $1}')"
			remotemd5="$(curl -fsL --retry 3 "$SCRIPT_REPO/$SCRIPT_NAME.sh" | md5sum | awk '{print $1}')"
			if [ "$localmd5" != "$remotemd5" ]; then
				doupdate="md5"
			fi
		fi
		
		if [ "$doupdate" = "version" ]; then
			Print_Output "true" "New version of $SCRIPT_NAME available - updating to $serverver" "$PASS"
		elif [ "$doupdate" = "md5" ]; then
			Print_Output "true" "MD5 hash of $SCRIPT_NAME does not match - downloading updated $serverver" "$PASS"
		fi

		Update_File "export.sh"
		Update_File "export_py.py"
		Update_File "helper_dhcpstaticlist.sh"
		Update_File "mod_basic.sh"
		Update_File "mod_client_traffic.sh"
		Update_File "mod_constats.sh"
		Update_File "mod_ping_ext.sh"
		Update_File "mod_spdstats.sh"
		Update_File "mod_trafficAnalyzer.sh"
		Update_File "mod_vpn_client.sh"
		Update_File "mod_wifi_clients.sh"

		
		if [ "$doupdate" != "false" ]; then
			/usr/sbin/curl -fsL --retry 3 "$SCRIPT_REPO/$SCRIPT_NAME.sh" -o "/jffs/scripts/$SCRIPT_NAME" && Print_Output "true" "$SCRIPT_NAME successfully updated"
			chmod 0755 /jffs/scripts/"$SCRIPT_NAME"
			Clear_Lock
			exit 0
		else
			Print_Output "true" "No new version - latest is $localver" "$WARN"
			Clear_Lock
		fi
	fi
	
	case "$1" in
		force)
			serverver=$(/usr/sbin/curl -fsL --retry 3 "$SCRIPT_REPO/$SCRIPT_NAME.sh" | grep "SCRIPT_VERSION=" | grep -m1 -oE 'v[0-9]{1,2}([.][0-9]{1,2})([.][0-9]{1,2})')
			Print_Output "true" "Downloading latest version ($serverver) of $SCRIPT_NAME" "$PASS"

			Update_File "export.sh"
			Update_File "export_py.py"
			Update_File "helper_dhcpstaticlist.sh"
			Update_File "mod_basic.sh"
			Update_File "mod_client_traffic.sh"
			Update_File "mod_constats.sh"
			Update_File "mod_ping_ext.sh"
			Update_File "mod_spdstats.sh"
			Update_File "mod_trafficAnalyzer.sh"
			Update_File "mod_vpn_client.sh"
			Update_File "mod_wifi_clients.sh"

			/usr/sbin/curl -fsL --retry 3 "$SCRIPT_REPO/$SCRIPT_NAME.sh" -o "/jffs/scripts/$SCRIPT_NAME" && Print_Output "true" "$SCRIPT_NAME successfully updated"
			chmod 0755 /jffs/scripts/"$SCRIPT_NAME"
			Clear_Lock
			exit 0
		;;
	esac
}
############################################################################

Validate_Number(){
	if [ "$2" -eq "$2" ] 2>/dev/null; then
		return 0
	else
		formatted="$(echo "$1" | sed -e 's/|/ /g')"
		if [ -z "$3" ]; then
			Print_Output "false" "$formatted - $2 is not a number" "$ERR"
		fi
		return 1
	fi
}

Download_File(){
	/usr/sbin/curl -fsL --retry 3 "$1" -o "$2"
}

Create_Dirs(){
	if [ ! -d "$SCRIPT_DIR" ]; then
		mkdir -p "$SCRIPT_DIR"
	fi

	if [ -f "/jffs/configs/extstats.conf" ]; then
		mv "/jffs/configs/extstats.conf" "$SCRIPT_DIR/extstats.conf"
	fi

	if [ -f "/jffs/configs/extstats.conf.default" ]; then
		mv "/jffs/configs/extstats.conf.default" "$SCRIPT_DIR/extstats.conf.default"
	fi

}

Conf_Exists(){

	if [ -f "$SCRIPT_CONF" ]; then
		dos2unix "$SCRIPT_CONF"
		chmod 0644 "$SCRIPT_CONF"
		sed -i -e 's/"//g' "$SCRIPT_CONF"
		return 0
	else
		{ echo "EXTS_DATABASE=telegraf"; echo "EXTS_USERNAME="; echo "EXTS_PASSWORD="; echo "EXTS_USESSH=false" ; echo "EXTS_URL=" ; echo "EXTS_PORT=8086"; echo "EXTS_BASIC_ENABLED=false"; echo "EXTS_WIFI_ENABLED=false"; echo "EXTS_TRAFFIC_ENABLED=false"; echo "EXTS_NTPMERLIN_ENABLED=false"; echo "EXTS_SPDSTATS_ENABLED=false"; echo "EXTS_VPN_ENABLED=false"; echo "EXTS_TRAFFIC_ANALYZER_ENABLED=false"; echo "EXTS_NOVERIFIY=false"; } >> "$SCRIPT_CONF"
		return 1
	fi
}

Auto_ServiceEvent(){
	case $1 in
		create)
			if [ -f /jffs/scripts/service-event ]; then
				STARTUPLINECOUNT=$(grep -c '# '"$SCRIPT_NAME" /jffs/scripts/service-event)
				# shellcheck disable=SC2016
				STARTUPLINECOUNTEX=$(grep -cx "/jffs/scripts/$SCRIPT_NAME_LOWER generate"' "$1" "$2" &'' # '"$SCRIPT_NAME" /jffs/scripts/service-event)
				
				if [ "$STARTUPLINECOUNT" -gt 1 ] || { [ "$STARTUPLINECOUNTEX" -eq 0 ] && [ "$STARTUPLINECOUNT" -gt 0 ]; }; then
					sed -i -e '/# '"$SCRIPT_NAME"'/d' /jffs/scripts/service-event
				fi
				
				if [ "$STARTUPLINECOUNTEX" -eq 0 ]; then
					# shellcheck disable=SC2016
					echo "/jffs/scripts/$SCRIPT_NAME_LOWER generate"' "$1" "$2" &'' # '"$SCRIPT_NAME" >> /jffs/scripts/service-event
				fi
			else
				echo "#!/bin/sh" > /jffs/scripts/service-event
				echo "" >> /jffs/scripts/service-event
				# shellcheck disable=SC2016
				echo "/jffs/scripts/$SCRIPT_NAME_LOWER generate"' "$1" "$2" &'' # '"$SCRIPT_NAME" >> /jffs/scripts/service-event
				chmod 0755 /jffs/scripts/service-event
			fi
		;;
		delete)
			if [ -f /jffs/scripts/service-event ]; then
				STARTUPLINECOUNT=$(grep -c '# '"$SCRIPT_NAME" /jffs/scripts/service-event)
				
				if [ "$STARTUPLINECOUNT" -gt 0 ]; then
					sed -i -e '/# '"$SCRIPT_NAME"'/d' /jffs/scripts/service-event
				fi
			fi
		;;
	esac
}


Shortcut_EXTS(){
	case $1 in
		create)
			if [ -d "/opt/bin" ] && [ ! -f "/opt/bin/$SCRIPT_NAME" ] && [ -f "/jffs/scripts/$SCRIPT_NAME" ]; then
				ln -s /jffs/scripts/"$SCRIPT_NAME" /opt/bin
				chmod 0755 /opt/bin/"$SCRIPT_NAME"
			fi
		;;
		delete)
			if [ -f "/opt/bin/$SCRIPT_NAME" ]; then
				rm -f /opt/bin/"$SCRIPT_NAME"
			fi
		;;
	esac
}

PressEnter(){
	while true; do
		printf "Press enter to continue..."
		read -r "key"
		case "$key" in
			*)
				break
			;;
		esac
	done
	return 0
}

exts_basic(){
    case $1 in
		enable)
			sed -i 's/^EXTS_BASIC_ENABLED.*$/EXTS_BASIC_ENABLED=true/' "$SCRIPT_CONF"
			Auto_Cron create "cron_mod_basic" 2>/dev/null
		;;
		disable)
			sed -i 's/^EXTS_BASIC_ENABLED.*$/EXTS_BASIC_ENABLED=false/' "$SCRIPT_CONF"
			Auto_Cron delete "cron_mod_basic" 2>/dev/null
		;;
		check)
			EXTS_BASIC_ENABLED=$(grep "EXTS_BASIC_ENABLED" "$SCRIPT_CONF" | cut -f2 -d"=")
			if [ "$EXTS_BASIC_ENABLED" = "true" ]; then return 0; else return 1; fi
		;;
	esac
}
exts_wifi(){
    case $1 in
		enable)
			sed -i 's/^EXTS_WIFI_ENABLED.*$/EXTS_WIFI_ENABLED=true/' "$SCRIPT_CONF"
			Auto_Cron create "cron_mod_wifi_clients" 2>/dev/null
		;;
		disable)
			sed -i 's/^EXTS_WIFI_ENABLED.*$/EXTS_WIFI_ENABLED=false/' "$SCRIPT_CONF"
			Auto_Cron delete "cron_mod_wifi_clients" 2>/dev/null
		;;
		check)
			EXTS_WIFI_ENABLED=$(grep "EXTS_WIFI_ENABLED" "$SCRIPT_CONF" | cut -f2 -d"=")
			if [ "$EXTS_WIFI_ENABLED" = "true" ]; then return 0; else return 1; fi
		;;
	esac
}
exts_traffic(){
    case $1 in
		enable)
			sed -i 's/^EXTS_TRAFFIC_ENABLED.*$/EXTS_TRAFFIC_ENABLED=true/' "$SCRIPT_CONF"
			Auto_Cron create "cron_mod_client_traffic_setup" 2>/dev/null
			Auto_Cron create "cron_mod_client_traffic_update" 2>/dev/null
		;;
		disable)
			sed -i 's/^EXTS_TRAFFIC_ENABLED.*$/EXTS_TRAFFIC_ENABLED=false/' "$SCRIPT_CONF"
			Auto_Cron delete "cron_mod_client_traffic_setup" 2>/dev/null
			Auto_Cron delete "cron_mod_client_traffic_update" 2>/dev/null
		;;
		check)
			EXTS_TRAFFIC_ENABLED=$(grep "EXTS_TRAFFIC_ENABLED" "$SCRIPT_CONF" | cut -f2 -d"=")
			if [ "$EXTS_TRAFFIC_ENABLED" = "true" ]; then return 0; else return 1; fi
		;;
	esac
}

exts_ntpmerlin(){
    case $1 in
		enable)
			sed -i 's/^EXTS_NTPMERLIN_ENABLED.*$/EXTS_NTPMERLIN_ENABLED=true/' "$SCRIPT_CONF"
			Auto_Cron create "cron_mod_constats" 2>/dev/null
		;;
		disable)
			sed -i 's/^EXTS_NTPMERLIN_ENABLED.*$/EXTS_NTPMERLIN_ENABLED=false/' "$SCRIPT_CONF"
			Auto_Cron delete "cron_mod_constats" 2>/dev/null
		;;
		check)
			EXTS_NTPMERLIN_ENABLED=$(grep "EXTS_NTPMERLIN_ENABLED" "$SCRIPT_CONF" | cut -f2 -d"=")
			if [ "$EXTS_NTPMERLIN_ENABLED" = "true" ]; then return 0; else return 1; fi
		;;
	esac
}

exts_traffic_analyzer(){
    case $1 in
		enable)
			sed -i 's/^EXTS_TRAFFIC_ANALYZER_ENABLED.*$/EXTS_TRAFFIC_ANALYZER_ENABLED=true/' "$SCRIPT_CONF"
			Auto_Cron create "cron_mod_trafficAnalyzer" 2>/dev/null
		;;
		disable)
			sed -i 's/^EXTS_TRAFFIC_ANALYZER_ENABLED.*$/EXTS_TRAFFIC_ANALYZER_ENABLED=false/' "$SCRIPT_CONF"
			Auto_Cron delete "cron_mod_trafficAnalyzer" 2>/dev/null
		;;
		check)
			EXTS_TRAFFIC_ANALYZER_ENABLED=$(grep "EXTS_TRAFFIC_ANALYZER_ENABLED" "$SCRIPT_CONF" | cut -f2 -d"=")
			if [ "$EXTS_TRAFFIC_ANALYZER_ENABLED" = "true" ]; then return 0; else return 1; fi
		;;
	esac
}

exts_spdstats(){
    case $1 in
		enable)
			sed -i 's/^EXTS_SPDSTATS_ENABLED.*$/EXTS_SPDSTATS_ENABLED=true/' "$SCRIPT_CONF"
			Auto_Cron create "cron_mod_spdstats" 2>/dev/null
		;;
		disable)
			sed -i 's/^EXTS_SPDSTATS_ENABLED.*$/EXTS_SPDSTATS_ENABLED=false/' "$SCRIPT_CONF"
			Auto_Cron delete "cron_mod_spdstats" 2>/dev/null
		;;
		check)
			EXTS_SPDSTATS_ENABLED=$(grep "EXTS_SPDSTATS_ENABLED" "$SCRIPT_CONF" | cut -f2 -d"=")
			if [ "$EXTS_SPDSTATS_ENABLED" = "true" ]; then return 0; else return 1; fi
		;;
	esac
}

exts_vpn(){
    case $1 in
		enable)
			sed -i 's/^EXTS_VPN_ENABLED.*$/EXTS_VPN_ENABLED=true/' "$SCRIPT_CONF"
			Auto_Cron create "cron_mod_vpn_client" 2>/dev/null
		;;
		disable)
			sed -i 's/^EXTS_VPN_ENABLED.*$/EXTS_VPN_ENABLED=false/' "$SCRIPT_CONF"
			Auto_Cron delete "cron_mod_vpn_client" 2>/dev/null
		;;
		check)
			EXTS_VPN_ENABLED=$(grep "EXTS_VPN_ENABLED" "$SCRIPT_CONF" | cut -f2 -d"=")
			if [ "$EXTS_VPN_ENABLED" = "true" ]; then return 0; else return 1; fi
		;;
	esac
}


exts_URL(){
	case "$1" in
		update)
			if [ "$URL" != "exit" ]; then
				sed -i 's/^EXTS_URL.*$/EXTS_URL='"$SERVERURL"'/' "$SCRIPT_CONF"
			else
				return 1
			fi
		;;
		disable)
			sed -i 's/^EXTS_URL.*$/EXTS_URL=/' "$SCRIPT_CONF"
		;;
		check)
			EXTS_URL=$(grep "EXTS_URL" "$SCRIPT_CONF" | cut -f2 -d"=")
			if [ -z "$EXTS_URL" ]; then return 1; else return 0; fi
		;;
		list)
			EXTS_URL=$(grep "EXTS_URL" "$SCRIPT_CONF" | cut -f2 -d"=")
			echo "$EXTS_URL"
		;;
	esac
}

exts_Database(){
	case "$1" in
		update)
			if [ "$DATABASE" != "exit" ]; then
				sed -i 's/^EXTS_DATABASE.*$/EXTS_DATABASE='"$DATABASE"'/' "$SCRIPT_CONF"
			else
				return 1
			fi
		;;
		disable)
			sed -i 's/^EXTS_DATABASE.*$/EXTS_DATABASE=/' "$SCRIPT_CONF"
		;;
		check)
			EXTS_DATABASE=$(grep "EXTS_DATABASE" "$SCRIPT_CONF" | cut -f2 -d"=")
			if [ -z "$EXTS_DATABASE" ]; then return 1; else return 0; fi
		;;
		list)
			EXTS_DATABASE=$(grep "EXTS_DATABASE" "$SCRIPT_CONF" | cut -f2 -d"=")
			echo "$EXTS_DATABASE"
		;;
	esac
}

exts_Port(){
	case "$1" in
		update)
			if [ "$PORT" != "exit" ]; then
				sed -i 's/^EXTS_PORT.*$/EXTS_PORT='"$PORT"'/' "$SCRIPT_CONF"
			else
				return 1
			fi
		;;
		disable)
			sed -i 's/^EXTS_PORT.*$/EXTS_PORT=/' "$SCRIPT_CONF"
		;;
		check)
			EXTS_PORT=$(grep "EXTS_PORT" "$SCRIPT_CONF" | cut -f2 -d"=")
			if [ -z "$EXTS_PORT" ]; then return 1; else return 0; fi
		;;
		list)
			EXTS_PORT=$(grep "EXTS_PORT" "$SCRIPT_CONF" | cut -f2 -d"=")
			echo "$EXTS_PORT"
		;;
	esac
}

exts_Username(){
	case "$1" in
		update)
			if [ "$USERNAME" != "exit" ]; then
				sed -i 's/^EXTS_USERNAME.*$/EXTS_USERNAME='"$USERNAME"'/' "$SCRIPT_CONF"
			else
				return 1
			fi
		;;
		disable)
			sed -i 's/^EXTS_USERNAME.*$/EXTS_USERNAME=/' "$SCRIPT_CONF"
		;;
		check)
			EXTS_USERNAME=$(grep "EXTS_USERNAME" "$SCRIPT_CONF" | cut -f2 -d"=")
			if [ -z "$EXTS_USERNAME" ]; then return 1; else return 0; fi
		;;
		list)
			EXTS_DATABASE=$(grep "EXTS_USERNAME" "$SCRIPT_CONF" | cut -f2 -d"=")
			echo "$EXTS_USERNAME"
		;;
	esac
}


exts_Password(){
	case "$1" in
		update)
			if [ "$PASSWORD" != "exit" ]; then
				sed -i 's/^EXTS_PASSWORD.*$/EXTS_PASSWORD='"$PASSWORD"'/' "$SCRIPT_CONF"
			else
				return 1
			fi
		;;
		disable)
			sed -i 's/^EXTS_PASSWORD.*$/EXTS_PASSWORD=/' "$SCRIPT_CONF"
		;;
		check)
			EXTS_PASSWORD=$(grep "EXTS_PASSWORD" "$SCRIPT_CONF" | cut -f2 -d"=")
			if [ -z "$EXTS_PASSWORD" ]; then return 1; else return 0; fi
		;;
		list)
			EXTS_PASSWORD=$(grep "EXTS_PASSWORD" "$SCRIPT_CONF" | cut -f2 -d"=")
			echo "$EXTS_PASSWORD"
		;;
	esac
}

exts_Usessh(){
	case "$1" in
		enable)
			sed -i 's/^EXTS_USESSH.*$/EXTS_USESSH=true/' "$SCRIPT_CONF"
		;;
		disable)
			sed -i 's/^EXTS_USESSH.*$/EXTS_USESSH=false/' "$SCRIPT_CONF"
		;;
		check)
			EXTS_USESSH=$(grep "EXTS_USESSH" "$SCRIPT_CONF" | cut -f2 -d"=")
			if [ -z "$EXTS_USESSH" ]; then return 1; else return 0; fi
		;;
		list)
			EXTS_USESSH=$(grep "EXTS_USESSH" "$SCRIPT_CONF" | cut -f2 -d"=")
			echo "$EXTS_USESSH"
		;;
	esac
}

exts_noverify(){
	case "$1" in
		enable)
			sed -i 's/^EXTS_NOVERIFIY.*$/EXTS_NOVERIFIY=true/' "$SCRIPT_CONF"
		;;
		disable)
			sed -i 's/^EXTS_NOVERIFIY.*$/EXTS_NOVERIFIY=false/' "$SCRIPT_CONF"
		;;
		check)
			EXTS_NOVERIFIY=$(grep "EXTS_NOVERIFIY" "$SCRIPT_CONF" | cut -f2 -d"=")
			if [ -z "$EXTS_NOVERIFIY" ]; then return 1; else return 0; fi
		;;
		list)
			EXTS_NOVERIFIY=$(grep "EXTS_NOVERIFIY" "$SCRIPT_CONF" | cut -f2 -d"=")
			echo "$EXTS_NOVERIFIY"
		;;
	esac
}


Menu_EditDatabase(){
	exitmenu="false"
	ScriptHeader

	while true; do
		printf "\\n\\e[1mPlease enter the influxDB Server (like server.com or 127.0.0.1) WITHOUT PORT!! :\\e[0m\\n"
		read -r "URL"

		if [ "$URL" = "e" ]; then
			exitmenu="exit"
			break
		else
			if [ -z "$URL" ] ; then
				printf "\\n\\e[31mPlease enter a valid Server\\e[0m\\n"
			else
				SERVERURL="$URL"
                exts_URL update "$URL"
				printf "\\n"
                break
			fi
		fi
    done

    if [ "$exitmenu" != "exit" ]; then
        while true; do
            printf "\\n\\e[1mPlease enter the influxDB Database Port (like 8086) :\\e[0m\\n"
            read -r "PORT"

            if [ "$PORT" = "e" ]; then
                exitmenu="exit"
                break
            else
                if [ -z "$PORT" ] ; then
                    printf "\\n\\e[31mPlease enter a valid Port\\e[0m\\n"
                else
                    EXTS_PORT="$DATABASE"
                    exts_Port update "$PORT"
                    printf "\\n"
                    break
                fi
            fi
        done
    fi

   if [ "$exitmenu" != "exit" ]; then
        while true; do
            printf "\\n\\e[1mPlease enter the influxDB Username (like telegraf or Admin) :\\e[0m\\n"
            read -r "USERNAME"

            if [ "$USERNAME" = "e" ]; then
                exitmenu="exit"
                break
            else
                if [ -z "$USERNAME" ] ; then
                    printf "\\n\\e[31mPlease enter a valid Username\\e[0m\\n"
                else
                    EXTS_USERNAME="$USERNAME"
                    exts_Username update "$USERNAME"
                    printf "\\n"
                    break
                fi
            fi
        done
    fi

  if [ "$exitmenu" != "exit" ]; then
        while true; do
            printf "\\n\\e[1mUse SSH (y/n)\\e[0m\\n"
			read -r "USESSH"

            case "$USESSH" in
                y|Y)
                    EXTS_USESSH="true"
                    exts_Usessh enable
                    printf "\\n"
                    break
                ;;
                *)
                    EXTS_USESSH="false"
                    exts_Usessh disable
                    break
                ;;
            esac
        done
    fi

  if [ "$exitmenu" != "exit" ]; then
        while true; do
            printf "\\n\\e[1mDont verify SSL (if you want use SSL without correct certificate) (y/n)\\e[0m\\n"
			read -r "NOVERIFIY"

            case "$NOVERIFIY" in
                y|Y)
                    EXTS_NOVERIFIY="true"
                    exts_noverify enable
                    printf "\\n"
                    break
                ;;
                *)
                    EXTS_NOVERIFIY="false"
                    exts_noverify disable
                    break
                ;;
            esac
        done
    fi


    if [ "$exitmenu" != "exit" ]; then
		while true; do
			printf "\\n\\e[1mPlease enter the influxDB Password :\\e[0m\\n"
			read -r "PASSWORD"

			if [ "$PASSWORD" = "e" ]; then
				exitmenu="exit"
				break
			else
				EXTS_PASSWORD="$PASSWORD"
				exts_Password update "$PASSWORD"
				printf "\\n"
				break
			fi
		done
    fi


	if [ "$exitmenu" != "exit" ]; then
        while true; do
            printf "\\n\\e[1mCreate a new Database (y) or use existing (n)\\e[0m\\n"
			read -r "newDatabase"

            case "$newDatabase" in
                y|Y)
                    CREATEDB="true"
                    printf "\\n"
                    break
                ;;
                *)
                    CREATEDB="FALSE"
                    break
                ;;
            esac
        done
	fi

    if [ "$exitmenu" != "exit" ]; then
        while true; do
            printf "\\n\\e[1mPlease enter the influxDB Database Name (like telegraf or routerData) :\\e[0m\\n"
            read -r "DATABASE"

            if [ "$DATABASE" = "e" ]; then
                exitmenu="exit"
                break
            else
                if [ -z "$DATABASE" ] ; then
                    printf "\\n\\e[31mPlease enter a valid Database Name\\e[0m\\n"
                else
                    EXTS_DATABASE="$DATABASE"
                    exts_Database update "$DATABASE"

					if [ "$CREATEDB" = "true" ]; then
						if [ "$USESSH" != "false" ]; then HTTP="https"; else HTTP="http"; fi
						if [ "$NOVERIFIY" == "true" ]; then VERIFIY="-k"; fi #ignore ssl error

						CURL_OPTIONS="${VERIFIY} -POST" #get is deprecated
						CURL_USER="-u ${USERNAME}:${PASSWORD}"
						INFLUX_URL="${HTTP}://${URL}:${PORT}"
						curl -is  ${INFLUX_URL}/query ${CURL_USER} --data-urlencode "q=CREATE DATABASE ${DATABASE}"

						break
							readConfigData
							ScriptHeader
							MainMenu
					fi

                    printf "\\n"
                    break
                fi
            fi
        done
    fi



	# if [ "$exitmenu" != "exit" ]; then
	# 	TestSchedule "update" "$starthour" "$endhour" "$startminute"
	# fi

	Clear_Lock
}

pingDB(){
	readConfigData

    PING_RESPONSE=$(curl -is ${TEST_URL}/ping)
    response_header=$(echo "${PING_RESPONSE}" | head -1)
    response_header_int=$(echo "${PING_RESPONSE}" | head -1 | awk '{print $2}' )

	case "$response_header_int" in
		100) # extstats: HTTP/1.1 204 No Content
			return 1
			break
		;;
		204) # extstats: HTTP/1.1 204 No Content
			#printf "$response_header_int \\n $response_header \\n"
			#printf "Testing Database Conection $ on ${TEST_URL}/ping \\n\\n"
			return 0
			break
		;;
		*)
			return 1
			break
		;;

	esac

    
}

test_DB()
{
    CURDATE=`date +%s`

    printf "Testing Database Conection on ${TEST_URL} \\n\\n"
    curl -sL -I ${TEST_URL}/ping

    printf "creating database\\n"
	CURL_CMD="${CURL_OPTIONS}  ${TEST_URL}/query ${CURL_USER} --data-urlencode q=CREATE DATABASE ${EXTS_DATABASE}"
	echo "curl $CURL_CMD"
    curl ${CURL_OPTIONS} ${TEST_URL}/query ${CURL_USER} --data-urlencode "q=CREATE DATABASE extstats_testDB"

    #printf "\\ncreating retention policy\n"
    #curl ${CURL_OPTIONS} ${TEST_URL}/query ${CURL_USER} --data-urlencode "q=CREATE RETENTION POLICY myrp ON ${EXTS_DATABASE} DURATION 365d REPLICATION 1 DEFAULT"

    printf "\\nshowing Databases q=SHOW DATABASES \\n"
    curl ${CURL_OPTIONS} ${TEST_URL}/query ${CURL_USER} --data-urlencode "q=SHOW DATABASES"

    printf "\\nInsert Test Data in DB ${EXTS_DATABASE}\\n"
    CURDATE=`date +%s`
    data="router.test,host=router 24=1,50=100 ${CURDATE}000000000"
    #curl ${CURL_OPTIONS} "${TEST_URL}/write?db=${EXTS_DATABASE} ${CURL_USER}" --data-binary "${data}" 
	curl -is ${CURL_OPTIONS} -XPOST "${TEST_URL}/write?db=${EXTS_DATABASE}&u=${EXTS_USERNAME}&p=${EXTS_PASSWORD}" --data-binary "${data}"

    printf "\\nSHOW MEASUREMENTS from DB ${EXTS_DATABASE}\\n"
    curl ${CURL_OPTIONS} ${TEST_URL}/query ${CURL_USER} --data-urlencode "db=${EXTS_DATABASE}" --data-urlencode "q=SHOW MEASUREMENTS" --data-urlencode "pretty=true"

    printf "\\nSHOW SERIES from DB ${EXTS_DATABASE}\\n"
    curl ${CURL_OPTIONS} ${TEST_URL}/query ${CURL_USER} --data-urlencode "db=${EXTS_DATABASE}" --data-urlencode "q=SHOW SERIES" --data-urlencode "pretty=true"

    printf "\nRemove Test Database\n"
    curl ${CURL_OPTIONS}  ${TEST_URL}/query ${CURL_USER} --data-urlencode "q=DROP DATABASE extstats_testDB"

    printf "\\n "
    Clear_Lock

}

ScriptHeader(){
	clear
	#pingDB

    EXTS_URL=$(grep "EXTS_URL" "$SCRIPT_CONF" | cut -f2 -d"=")
    EXTS_DATABASE=$(grep "EXTS_DATABASE" "$SCRIPT_CONF" | cut -f2 -d"=")
    EXTS_USERNAME=$(grep "EXTS_USERNAME" "$SCRIPT_CONF" | cut -f2 -d"=")
    EXTS_PASSWORD=$(grep "EXTS_PASSWORD" "$SCRIPT_CONF" | cut -f2 -d"=")
    EXTS_USESSH=$(grep "EXTS_USESSH" "$SCRIPT_CONF" | cut -f2 -d"=")
    EXTS_PORT=$(grep "EXTS_PORT" "$SCRIPT_CONF" | cut -f2 -d"=")

	printf "\\e[1m#######################################################\\e[0m\\n"
	printf "\\e[1m##                 __  _____  __          __         ##\\e[0m\\n"
	printf "\\e[1m##    ___   _  __ / /_/ ___/ / /_ ____ _ / /_ _____  ##\\e[0m\\n"
	printf "\\e[1m##   / _ \ | |/_// __/\__ \ / __// __  // __// ___/  ##\\e[0m\\n"
	printf "\\e[1m##  /  __/_>  < / /_ ___/ // /_ / /_/ // /_ (__  )   ##\\e[0m\\n"
	printf "\\e[1m##  \___//_/|_| \__//____/ \__/ \__,_/ \__//____/    ##\\e[0m\\n"
	printf "\\e[1m##                                                   ##\\e[0m\\n"
	printf "\\e[1m#######################################################\\e[0m\\n"
	printf "\\e[1m##                                                   ##\\e[0m\\n"
	printf "\\e[1m##               %s on %-9s                 ##\\e[0m\\n" "$SCRIPT_VERSION" "$ROUTER_MODEL"
	printf "\\e[1m##                                                   ##\\e[0m\\n"
	printf "\\e[1m##       https://github.com/corgan2222/extstats      ##\\e[0m\\n"
	printf "\\e[1m##       Corgan - Stefan Knaak 2020		     ##\\e[0m\\n"
	printf "\\e[1m##                                                   ##\\e[0m\\n"
	printf "\\e[1m#######################################################\\e[0m\\n"
	printf "\\e[1m   Config  %s  \\e[0m\\n" "$SCRIPT_DIR/extstats.conf"
    printf "\\e[1m   URL  %s  %s@%s \\e[0m\\n" "$TEST_URL" "$EXTS_USERNAME" "$EXTS_DATABASE"
	printf "\\e[1m   USESSH  [%s]  NO VERIFY [%s] \\e[0m\\n" "$EXTS_USESSH" "$EXTS_NOVERIFIY"
	#printf "\\e[1m##  Password  %s  \\e[0m\\n" "$EXTS_PASSWORD"
	printf "\\e[1m#######################################################\\e[0m\\n"

	printf "\\n"
}

MainMenu(){

	EXTS_BASIC_ENABLED=""
	EXTS_WIFI_ENABLED=""
	EXTS_TRAFFIC_ENABLED=""
	EXTS_TRAFFIC_ANALYZER_ENABLED=""
	EXTS_NTPMERLIN_ENABLED=""
	EXTS_SPDSTATS_ENABLED=""
	EXTS_VPN_ENABLED=""

	if exts_basic check; then EXTS_BASIC_ENABLED="[Enabled] "; else EXTS_BASIC_ENABLED="[Disabled]"; fi
	if exts_wifi check; then EXTS_WIFI_ENABLED="[Enabled] "; else EXTS_WIFI_ENABLED="[Disabled]"; fi
	if exts_traffic check; then EXTS_TRAFFIC_ENABLED="[Enabled] "; else EXTS_TRAFFIC_ENABLED="[Disabled]"; fi
	if exts_traffic_analyzer check; then EXTS_TRAFFIC_ANALYZER_ENABLED="[Enabled] "; else EXTS_TRAFFIC_ANALYZER_ENABLED="[Disabled]"; fi
	if exts_ntpmerlin check; then EXTS_NTPMERLIN_ENABLED="[Enabled] "; else EXTS_NTPMERLIN_ENABLED="[Disabled]"; fi
	if exts_spdstats check; then EXTS_SPDSTATS_ENABLED="[Enabled] "; else EXTS_SPDSTATS_ENABLED="[Disabled]"; fi
	if exts_vpn check; then EXTS_VPN_ENABLED="[Enabled] "; else EXTS_VPN_ENABLED="[Disabled]"; fi

#client traffic
#1 * * * * /mnt/routerUSB/scripts/scripts/asuswrt/metrics2influx/router_client_traffic.sh setup  #TtInit#
#15 * * * * /mnt/routerUSB/scripts/scripts/asuswrt/metrics2influx/router_TrafficAnalyzer_influx.sh update  #Traffic#

#spdMerlin - Speedtest
#30 * * * * /mnt/routerUSB/scripts/scripts/asuswrt/metrics2influx/router_spdstats_influx.sh update  #spdstats#

#constats - connmon - Internet Uptime Monitoring
#45 * * * * /mnt/routerUSB/scripts/scripts/asuswrt/metrics2influx/router_constats_influx.sh update  #connstats#

	printf "\\e[1mDatabase\\e[0m\\n"
    printf "1.    Setup external Database (influxDB only atm)\\n\\n"
	
if pingDB; then
	printf "\\e[1mSelect the data you want to export to an external Database\\e[0m\\n"	
	printf "2.    %s Toogle basic stats (CPU, MEM, Temps, Net) \\n" "$EXTS_BASIC_ENABLED"
	printf "3.    %s Toogle wifi stats\\n" "$EXTS_WIFI_ENABLED"
	printf "4.    %s Toogle Traffic by Client stats\\n" "$EXTS_TRAFFIC_ENABLED"
	printf "5.    %s Toogle Traffic Analyzer stats \\n" "$EXTS_TRAFFIC_ANALYZER_ENABLED"
	printf "6.    %s Toogle Connmon Stats (Uptime Monitoring)\\n" "$EXTS_NTPMERLIN_ENABLED"
	printf "7.    %s Toogle spdMerlin Stats (Speedtest)\\n" "$EXTS_SPDSTATS_ENABLED"
	printf "8.    %s Toogle VPN stats\\n" "$EXTS_VPN_ENABLED"

	printf "\\n\\e[1mTest\\e[0m\\n"	
	printf "t1.    Test Database conection\\n"
	printf "t2.    Test basic stats \\n"
	printf "t3.    Test wifi stats \\n"
	printf "t4.    Test Traffic by Client \\n"
	printf "t5.    Test Traffic Analyzer \\n"
	printf "t6.    Test Connmon Stats \\n"
	printf "t7.    Test spdStats \\n"
	printf "t8.    Test VPN stats \\n\\n"
	printf "t9.    Test all \\n"
else
	printf "\\n\\e[1mCant ping Database! Please setup Database (1)\\e[0m\\n"	
fi
    printf "\\n\\e[1mDebug\\e[0m\\n"	
	printf "d.    Show DHCP Client list \\n"
	printf "h.    Htop\\n\\n"
	printf "\\e[1mOther\\e[0m\\n"
	printf "x.    Check Requirements\\n"
	printf "u.    Check for updates\\n"
	printf "uf.   Update %s with latest version (force update)\\n\\n" "$SCRIPT_NAME"
	printf "e.    Exit %s\\n\\n" "$SCRIPT_NAME"
	printf "z.    Uninstall %s\\n" "$SCRIPT_NAME"
	printf "\\n"
	printf "\\e[1m#####################################################\\e[0m\\n"
	printf "\\n"

	while true; do
		printf "Choose an option:    "
		read -r "menu"
		case "$menu" in
			1)
				printf "\\n"
				if Check_Lock "menu"; then
					Menu_EditDatabase
				fi
				PressEnter
				break
			;;
			2)
				printf "\\n"
                if exts_basic check; then
                    exts_basic disable
                else
                     exts_basic enable
                fi
				break
			;;
			3)
				printf "\\n"
                if exts_wifi check; then
                    exts_wifi disable
                else
                     exts_wifi enable
                fi
				break
			;;
			4)
				printf "\\n"
                if exts_traffic check; then
                    exts_traffic disable
                else
                     exts_traffic enable
                fi
				break
			;;
			5)
				printf "\\n"
                if exts_traffic_analyzer check; then
                    exts_traffic_analyzer disable
                else

					while true; do
						printf "\\n\\e[1mWould you like to import all available Traffic Data into influx? This can take some time on the first import (y/n)\\e[0m\\n"
						read -r "confirm"
						case "$confirm" in
							y|Y)
								$SCRIPT_DIR/mod_trafficAnalyzer.sh "full" "true"
								PressEnter
								break
							;;
							*)
								PressEnter
								break
							;;
						esac
					done

					exts_traffic_analyzer enable
                fi
				break
			;;
			6)
				printf "\\n"
                if exts_ntpmerlin check; then
                    exts_ntpmerlin disable
                else
					while true; do
						printf "\\n\\e[1mWould you like to import all available Uptime Data into influx? This can take some time on the first import (y/n)\\e[0m\\n"
						read -r "confirm"
						case "$confirm" in
							y|Y)
								$SCRIPT_DIR/mod_constats.sh "full" "true"
								PressEnter
								break
							;;
							*)
								PressEnter
								break
							;;
						esac
					done

                     exts_ntpmerlin enable
                fi
				break
			;;
			7)
				printf "\\n"
                if exts_spdstats check; then
                    exts_spdstats disable
                else
					while true; do
						printf "\\n\\e[1mWould you like to import all available Speedtest Data into influx? This can take some time on the first import (y/n)\\e[0m\\n"
						read -r "confirm"
						case "$confirm" in
							y|Y)
								$SCRIPT_DIR/mod_spdstats.sh "full" "true"
								PressEnter
								break
							;;
							*)
								PressEnter
								break
							;;
						esac
					done

                     exts_spdstats enable
                fi
				break
			;;
			8)
				printf "\\n"
                if exts_vpn check; then
                    exts_vpn disable
                else
                     exts_vpn enable
                fi
				break
			;;

			t1)
				printf "\\n"
				if Check_Lock "menu"; then
					test_DB
				fi
                Clear_Lock
				PressEnter
				break
				printf "\\n"

			;;
			t2)
				printf "\\n"
				if Check_Lock "menu"; then
					$SCRIPT_DIR/mod_basic.sh "true"
				fi
                Clear_Lock
				PressEnter
				break
				printf "\\n"
			;;
			t3)
				printf "\\n"
				if Check_Lock "menu"; then
					$SCRIPT_DIR/mod_wifi_clients.sh "false"
				fi
                Clear_Lock
				PressEnter
				break
				printf "\\n"
			;;
			t4)
				printf "\\n"
				if Check_Lock "menu"; then
					$SCRIPT_DIR/mod_client_traffic.sh "setup" "true"
					$SCRIPT_DIR/mod_client_traffic.sh "update" "true"
				fi
                Clear_Lock
				PressEnter
				break
				printf "\\n"
			;;
			t5)
				printf "\\n"
				if Check_Lock "menu"; then
					$SCRIPT_DIR/mod_trafficAnalyzer.sh "update" "true"
				fi
                Clear_Lock
				PressEnter
				break
				printf "\\n"
			;;
			t6)
				printf "\\n"
				if Check_Lock "menu"; then
					$SCRIPT_DIR/mod_constats.sh "update" "true"
				fi
                Clear_Lock
				PressEnter
				break
				printf "\\n"
			;;
			t7)
				printf "\\n"
				if Check_Lock "menu"; then
					$SCRIPT_DIR/mod_spdstats.sh "update" "true"
				fi
                Clear_Lock
				PressEnter
				break
				printf "\\n"
			;;
			t8)
				printf "\\n"
				if Check_Lock "menu"; then
					$SCRIPT_DIR/mod_vpn_client.sh "true"
				fi
                Clear_Lock
				PressEnter
				break
				printf "\\n"

			;;
			t9)
				printf "\\n"
				if Check_Lock "menu"; then
					test_DB
					PressEnter
					$SCRIPT_DIR/mod_basic.sh "true"
					PressEnter
					$SCRIPT_DIR/mod_wifi_clients.sh "false"
					PressEnter
					$SCRIPT_DIR/mod_client_traffic.sh "setup" "true"
					$SCRIPT_DIR/mod_client_traffic.sh "update" "true"
					PressEnter
					$SCRIPT_DIR/mod_trafficAnalyzer.sh "update" "true"
					PressEnter
					$SCRIPT_DIR/mod_constats.sh "update" "true"
					PressEnter
					$SCRIPT_DIR/mod_spdstats.sh "update" "true"
					PressEnter
					$SCRIPT_DIR/mod_vpn_client.sh "true" 
					PressEnter
				fi
                Clear_Lock
				PressEnter
				break
			;;
			d)
				printf "\\n"
				if Check_Lock "menu"; then
					$SCRIPT_DIR/helper_dhcpstaticlist.sh 

                    ip_count=$(cat "$DHCP_HOSTNAMESMAC" | wc -l)
                    printf "\\n %s Clients saved to %s \\n" "$ip_count" "$DHCP_HOSTNAMESMAC"
                    printf "\\n saved as CSV to %s \\n\\n" "$DHCP_HOSTNAMESMAC_CSV"

                    while true; do
                        printf "s1. Show sorted by Hostname $DHCP_HOSTNAMESMAC_SB_HOST \\n"
                        printf "s2. Show sorted by IP $DHCP_HOSTNAMESMAC_SB_IP\\n"
                        printf "s3. SShow sorted by Mac $DHCP_HOSTNAMESMAC_SB_MAC\\n"
                        printf "se. exit \\n"
                        read -r "sortby"
                        case "$sortby" in
                            s1)
                                clear
                                cat $DHCP_HOSTNAMESMAC_SB_HOST
                                PressEnter
                                break
                                printf "\\n"
                            ;;
                            s2)
                                clear
                                cat $DHCP_HOSTNAMESMAC_SB_IP
                                PressEnter
                                break
                                printf "\\n"
                            ;;
                            s3)
                                clear
                                cat $DHCP_HOSTNAMESMAC_SB_MAC
                                PressEnter
                                break
                                printf "\\n"
                            ;;
                            *)
				                break
				                printf "\\n"
                            ;;
                        esac
                    done
                fi
                Clear_Lock
				PressEnter
				break
			;;
			h)
				printf "\\n"
				program=""
				if [ -f /opt/bin/opkg ]; then
					if [ -f /opt/bin/htop ]; then
						program="htop"
					else
						program=""
						while true; do
							printf "\\n\\e[1mWould you like to install htop (enhanced version of top)? (y/n)\\e[0m\\n"
							read -r "confirm"
							case "$confirm" in
								y|Y)
									program="htop"
									opkg install htop
									break
								;;
								*)
									program="top"
									break
								;;
							esac
						done
					fi
				else
					program="top"
				fi
				trap trap_ctrl 2
				trap_ctrl(){
					exec "$0"
				}
				"$program"
				trap - 2
				PressEnter
				break
			;;

			x)
				printf "\\n"
				Check_Requirements Check_Lock
				PressEnter
				break
			;;
			u)
				printf "\\n"
				if Check_Lock "menu"; then
					Menu_Update
				fi
				PressEnter
				break
			;;
			uf)
				printf "\\n"
				if Check_Lock "menu"; then
					Menu_ForceUpdate
				fi
				PressEnter
				break
			;;
			e)
				ScriptHeader
				printf "\\n\\e[1mThanks for using %s!\\e[0m\\n\\n\\n" "$SCRIPT_NAME"
				exit 0
			;;
			z)
				while true; do
					printf "\\n\\e[1mAre you sure you want to uninstall %s? (y/n)\\e[0m\\n" "$SCRIPT_NAME"
					read -r "confirm"
					case "$confirm" in
						y|Y)
							Menu_Uninstall
							exit 0
						;;
						*)
							break
						;;
					esac
				done
			;;
			*)
				printf "\\nPlease choose a valid option\\n\\n"
			;;
		esac
	done
	
	ScriptHeader
	MainMenu
}


AutomaticMode(){

	MOD_CRON_JOB=${2}

	case $MOD_CRON_JOB in
		cron_mod_basic)
			config_var="EXTS_BASIC_ENABLED"
		;;
		cron_mod_wifi_clients)
			config_var="EXTS_WIFI_ENABLED"
		;;
		cron_mod_client_traffic)
			config_var="EXTS_TRAFFIC_ENABLED"
		;;
		cron_mod_trafficAnalyzer)
			config_var="EXTS_TRAFFIC_ANALYZER_ENABLED"
		;;
		cron_mod_constats)
			config_var="EXTS_NTPMERLIN_ENABLED"
		;;
		cron_mod_spdstats)
			config_var="EXTS_SPDSTATS_ENABLED"
		;;
		cron_mod_vpn_client)
			config_var="EXTS_VPN_ENABLED"
		;;
	esac


	case "$1" in
		enable)
			#sed -i 's/^AUTOMATED.*$/AUTOMATED=true/' "$SCRIPT_CONF"
			sed -i 's/^${config_var}.*$/${config_var}=true/' "$SCRIPT_CONF"
			Auto_Cron create 2>/dev/null
			#per mod mode
		;;
		disable)
			#sed -i 's/^AUTOMATED.*$/AUTOMATED=false/' "$SCRIPT_CONF"
			sed -i 's/^${config_var}.*$/${config_var}=false/' "$SCRIPT_CONF"
			Auto_Cron delete 2>/dev/null
		;;
		check)
			AUTOMATED=$(grep "$config_var" "$SCRIPT_CONF" | cut -f2 -d"=")
			if [ "$AUTOMATED" = "true" ]; then return 0; else return 1; fi
		;;
	esac
}


Menu_Startup(){

	Auto_Startup create 2>/dev/null #create /jffs/scripts/extstats startup in services-start

	#set crons on startup based on config
	if AutomaticMode check "cron_mod_basic"; then Auto_Cron create "cron_mod_basic" 2>/dev/null; else Auto_Cron delete "cron_mod_basic" 2>/dev/null; fi
	if AutomaticMode check "cron_mod_wifi_clients"; then Auto_Cron create "cron_mod_wifi_clients" 2>/dev/null; else Auto_Cron delete "cron_mod_wifi_clients" 2>/dev/null; fi
	if AutomaticMode check "cron_mod_client_traffic"; then Auto_Cron create "cron_mod_client_traffic_setup" 2>/dev/null; else Auto_Cron delete "cron_mod_client_traffic_setup" 2>/dev/null; fi
	if AutomaticMode check "cron_mod_client_traffic"; then Auto_Cron create "cron_mod_client_traffic_update" 2>/dev/null; else Auto_Cron delete "cron_mod_client_traffic_update" 2>/dev/null; fi
	if AutomaticMode check "cron_mod_trafficAnalyzer"; then Auto_Cron create "cron_mod_trafficAnalyzer" 2>/dev/null; else Auto_Cron delete "cron_mod_trafficAnalyzer" 2>/dev/null; fi
	if AutomaticMode check "cron_mod_constats"; then Auto_Cron create "cron_mod_constats" 2>/dev/null; else Auto_Cron delete "cron_mod_constats" 2>/dev/null; fi
	if AutomaticMode check "cron_mod_spdstats"; then Auto_Cron create "cron_mod_spdstats" 2>/dev/null; else Auto_Cron delete "cron_mod_spdstats" 2>/dev/null; fi
	if AutomaticMode check "cron_mod_vpn_client"; then Auto_Cron create "cron_mod_vpn_client" 2>/dev/null; else Auto_Cron delete "cron_mod_vpn_client" 2>/dev/null; fi

	Auto_ServiceEvent create 2>/dev/null

	Shortcut_EXTS create
	Create_Dirs
	Clear_Lock
}

Auto_Startup(){
	case $1 in
		create)
			if [ -f /jffs/scripts/services-start ]; then
				STARTUPLINECOUNT=$(grep -c '# '"$SCRIPT_NAME" /jffs/scripts/services-start)
				STARTUPLINECOUNTEX=$(grep -cx "/jffs/scripts/$SCRIPT_NAME_LOWER startup"' # '"$SCRIPT_NAME" /jffs/scripts/services-start)

				if [ "$STARTUPLINECOUNT" -gt 1 ] || { [ "$STARTUPLINECOUNTEX" -eq 0 ] && [ "$STARTUPLINECOUNT" -gt 0 ]; }; then
					sed -i -e '/# '"$SCRIPT_NAME"'/d' /jffs/scripts/services-start
				fi

				if [ "$STARTUPLINECOUNTEX" -eq 0 ]; then
					echo "/jffs/scripts/$SCRIPT_NAME_LOWER startup"' # '"$SCRIPT_NAME" >> /jffs/scripts/services-start
				fi
			else
				echo "#!/bin/sh" > /jffs/scripts/services-start
				echo "" >> /jffs/scripts/services-start
				echo "/jffs/scripts/$SCRIPT_NAME_LOWER startup"' # '"$SCRIPT_NAME" >> /jffs/scripts/services-start
				chmod 0755 /jffs/scripts/services-start
			fi
		;;
		delete)
			if [ -f /jffs/scripts/services-start ]; then
				STARTUPLINECOUNT=$(grep -c '# '"$SCRIPT_NAME" /jffs/scripts/services-start)

				if [ "$STARTUPLINECOUNT" -gt 0 ]; then
					sed -i -e '/# '"$SCRIPT_NAME"'/d' /jffs/scripts/services-start
				fi
			fi
		;;
	esac
}

Auto_Cron(){

	MOD_CRON_ACTION=${1}
	MOD_CRON_JOB=${2}

	case $MOD_CRON_JOB in
		cron_mod_basic)
			CRONTIME="*/1 * * * *" #At every minute
		;;
		cron_mod_wifi_clients)
			CRONTIME="*/1 * * * *" #At every minute
		;;
		cron_mod_client_traffic_setup)
			CRONTIME="5 */1 * * *" #At minute 5 past every hour
		;;
		cron_mod_client_traffic_update)
			CRONTIME="*/1 * * * *" #At every 5 minutes
		;;
		cron_mod_trafficAnalyzer)
			CRONTIME="*/5 * * * *" #At minute 5 past every hour
		;;
		cron_mod_constats)
			CRONTIME="10 */1 * * *" #At minute 10 past every hour
		;;
		cron_mod_spdstats)
			CRONTIME="10 */1 * * *" #At minute 10 past every hour
		;;
		cron_mod_vpn_client)
			CRONTIME="* * * * *" #At every minute
		;;
	esac

	case $MOD_CRON_ACTION in
		create)
		STARTUPLINECOUNT=$(cru l | grep -c "$MOD_CRON_JOB")

		if [ "$STARTUPLINECOUNT" -eq 0 ]; 
		then
			cru a "$MOD_CRON_JOB" "$CRONTIME /jffs/scripts/$SCRIPT_NAME $MOD_CRON_JOB"
		fi
		;;
		delete)
			STARTUPLINECOUNT=$(cru l | grep -c "$MOD_CRON_JOB")

			if [ "$STARTUPLINECOUNT" -gt 0 ]; then
				cru d "$MOD_CRON_JOB"
			fi
		;;
	esac

#defaults:
#1min
# 1 * * * * /mnt/routerUSB/scripts/scripts/asuswrt/metrics2influx/router_client_traffic.sh setup  #TtInit#
# 15 * * * * /mnt/routerUSB/scripts/scripts/asuswrt/metrics2influx/router_TrafficAnalyzer_influx.sh update  #Traffic#
# * * * * * /mnt/routerUSB/scripts/scripts/asuswrt/metrics2influx/routerstats.sh  #routerstats#
# 30 * * * * /mnt/routerUSB/scripts/scripts/asuswrt/metrics2influx/router_spdstats_influx.sh update  #spdstats#
# 45 * * * * /mnt/routerUSB/scripts/scripts/asuswrt/metrics2influx/router_constats_influx.sh update  #connstats#



}


Check_Requirements(){
	CHECKSFAILED="false"
	
	if [ "$(nvram get jffs2_scripts)" -ne 1 ]; then
		nvram set jffs2_scripts=1
		nvram commit
		Print_Output "true" "Custom JFFS Scripts enabled" "$WARN"
	fi

	if [ ! -f "/opt/bin/opkg" ]; then
		Print_Output "true" "Entware not detected!" "$ERR"
		CHECKSFAILED="true"
	fi

	if [ ! -f "/opt/bin/sqlite3" ]; then
		Print_Output "true" "sqlite3 not detected!" "$CRIT"

		while true; do
			printf "\\n\\e[1mWould you like to install sqlite3? (y/n)\\e[0m\\n"
			read -r "confirm"
			case "$confirm" in
				y|Y)
					system_install_opkg sqlite3-cli
					break
				;;
				*)
					CHECKSFAILED="true"
					break
				;;
			esac
		done
	fi

	if [ ! -f "/opt/bin/jq" ]; then
		Print_Output "true" "jq not detected!" "$CRIT"

		while true; do
			printf "\\n\\e[1mWould you like to install jq? (y/n)\\e[0m\\n"
			read -r "confirm"
			case "$confirm" in
				y|Y)
					system_install_opkg jq
					break
				;;
				*)
					CHECKSFAILED="true"
					break
				;;
			esac
		done
	fi

	if [ ! -f "/opt/bin/base64" ]; then
		Print_Output "true" "coreutils-base64 not detected!" "$CRIT"

		while true; do
			printf "\\n\\e[1mWould you like to install coreutils-base64? (y/n)\\e[0m\\n"
			read -r "confirm"
			case "$confirm" in
				y|Y)
					system_install_opkg coreutils-base64
					break
				;;
				*)
					CHECKSFAILED="true"
					break
				;;
			esac
		done
	fi

	if [ ! -f "/opt/bin/python" ]; then
		Print_Output "true" "python not detected!" "$CRIT"

		while true; do
			printf "\\n\\e[1mWould you like to install python? (y/n)\\e[0m\\n"
			read -r "confirm"
			case "$confirm" in
				y|Y)
					system_install_opkg python
					system_install_opkg python-pip
					pip install influxdb
					pip install python-dateutil
					pip install requests
					break
				;;
				*)
					CHECKSFAILED="true"
					break
				;;
			esac
		done
	fi

	pip_influx=$(pip list --disable-pip-version-check | grep influx | wc -l)
	if [ $pip_influx -lt 1 ]; then
		pip install influxdb
		pip install python-dateutil
		pip install requests
	fi

	if [ "$CHECKSFAILED" = "true" ]; then
		Print_Output "true" "Requirements for $SCRIPT_NAME not met, please see above for the reason(s)" "$CRIT"
		return 1
	else
		Print_Output "true" "Requirements for $SCRIPT_NAME passed" "$PASS"
		return 0
	fi
}

system_install_opkg(){
	opkg update
	opkg install $1
}

system_list_opkg(){
	# sqlite3-cli #/opt/bin/sqlite3
	# jq #/opt/bin/jq
	# bc #/opt/bin/jq
	# coreutils-base64 #/opt/bin/base64

	# python #/opt/bin/python
	# python-pip
	# pip install influxdb
	# pip install python-dateutil
	# pip install requests
echo ""

}

system_check_opkg()
{
	if [ ! -f "$1" ]; then
		Print_Output "true" "$1 detected!" "$ERR"
		CHECKSFAILED="true"
		return 0
	else
		return 1
	fi
}


Menu_Install(){
	Print_Output "true" "Welcome to $SCRIPT_NAME $SCRIPT_VERSION, a script by Corgan"
	sleep 1
	Print_Output "true" "Checking your router meets the requirements for $SCRIPT_NAME"
	
	if ! Check_Requirements; then
		Print_Output "true" "Requirements for $SCRIPT_NAME not met, please see above for the reason(s)" "$CRIT"
		PressEnter
		Clear_Lock
		rm -f "/jffs/scripts/$SCRIPT_NAME_LOWER" 2>/dev/null
		exit 1
	fi
	Create_Dirs

	Update_File "export.sh"
	Update_File "export_py.py"
	Update_File "helper_dhcpstaticlist.sh"
	Update_File "mod_basic.sh"
	Update_File "mod_client_traffic.sh"
	Update_File "mod_constats.sh"
	Update_File "mod_ping_ext.sh"
	Update_File "mod_spdstats.sh"
	Update_File "mod_trafficAnalyzer.sh"
	Update_File "mod_vpn_client.sh"
	Update_File "mod_wifi_clients.sh"
	Update_File "mod_versions.sh"

	Conf_Exists
	
	Auto_Startup create 2>/dev/null
	#if AutomaticMode check; then Auto_Cron create 2>/dev/null; else Auto_Cron delete 2>/dev/null; fi
	Auto_ServiceEvent create 2>/dev/null

	Shortcut_EXTS create
	Clear_Lock
	ScriptHeader
	MainMenu
}

Menu_Update(){
	Update_Version
	Clear_Lock
}

Menu_ForceUpdate(){
	Update_Version force
	Clear_Lock
}

Menu_Uninstall(){
	rn_crons
	Print_Output "true" "Removing $SCRIPT_NAME..." "$PASS"
	Shortcut_EXTS delete
	rm -f "/jffs/scripts/$SCRIPT_NAME" 2>/dev/null
	Clear_Lock
	Print_Output "true" "Uninstall completed" "$PASS"
}

if [ -z "$1" ]; then
	ScriptHeader
	MainMenu
	exit 0
fi

rn_crons(){
	cru d cron_mod_basic 2>/dev/null
	cru d cron_mod_wifi_clients 2>/dev/null
	cru d cron_mod_wifi_clients 2>/dev/null
	cru d cron_mod_client_traffic 2>/dev/null
	cru d cron_mod_client_traffic_setup 2>/dev/null
	cru d cron_mod_client_traffic_update 2>/dev/null
	cru d cron_mod_trafficAnalyzer 2>/dev/null
	cru d cron_mod_constats 2>/dev/null
	cru d cron_mod_spdstats 2>/dev/null
	cru d cron_mod_vpn_client 2>/dev/null
	cru d cron_mod_constats 2>/dev/null

}


case "$1" in
	rm_crons)
		rn_crons
		cru l
		exit 0
	;;
	install)
		Check_Lock
		Menu_Install
		exit 0
	;;
	update)
		Check_Lock
		Menu_Update
		exit 0
	;;
	forceupdate)
		Check_Lock
		Menu_ForceUpdate
		exit 0
	;;
	uninstall)
		Check_Lock
		Menu_Uninstall
		exit 0
	;;
	startup)
		#Check_Lock
		Menu_Startup
		exit 0
	;;
	automatic)
		Check_Lock
		Menu_ToggleAutomated
		Clear_Lock
		exit 0
	;;
	cron_mod_basic)
		nice -n -19 $SCRIPT_DIR/mod_basic.sh "false"
		exit 0
	;;
	cron_mod_wifi_clients)
		nice -n -19 $SCRIPT_DIR/mod_wifi_clients.sh "false"
		exit 0
	;;
	cron_mod_client_traffic_setup)
		nice -n -19 $SCRIPT_DIR/mod_client_traffic.sh "setup" "false"
		exit 0
	;;
	cron_mod_client_traffic_update)
		nice -n -19 $SCRIPT_DIR/mod_client_traffic.sh "update" "false"
		exit 0
	;;
	cron_mod_trafficAnalyzer)
		nice -n -19 $SCRIPT_DIR/mod_trafficAnalyzer.sh "update" "false"
		nice -n -19 $SCRIPT_DIR/mod_versions.sh "update" "false"
		exit 0
	;;
	cron_mod_constats)
		nice -n -19 $SCRIPT_DIR/mod_constats.sh "update" "false"
		exit 0
	;;
	cron_mod_spdstats)
		nice -n -19 $SCRIPT_DIR/mod_spdstats.sh "update" "false"
		exit 0
	;;
	cron_mod_vpn_client)
		nice -n -19 $SCRIPT_DIR/mod_vpn_client.sh "false"
		exit 0
	;;
	*)
		Check_Lock
		echo "Command not recognised, please try again"
		Clear_Lock
		exit 1
	;;
esac

#nvram get dhcp_staticlist | sed 's/<//;s/>undefined//;s/>/ /g;s/</ /g'
#nvram get custom_clientlist | sed 's/<//;s/>undefined//;s/>/ /g;s/</ /g'
#awk '{print $0}' /jffs/nvram/dhcp_staticlist | sed 's/<//;s/>undefined//;s/>/ /g;s/</ /g'

# nvram show | grep Lyra
# cfg_device_list=<RT-AX
# cfg_obmodel=Lyra
# nvram get cfg_device_list | sed 's/<//;s/>undefined//;s/>/ /g;s/</ /g'


