#!/bin/sh
#set -x

#how it works:
# 1. get copy of the original /jffs/.sys/TrafficAnalyzer/TrafficAnalyzer.db
# 2. create a new table clients in the copy
# 3. on full: import all data stored in the table
#    on update: import only the latest data (one hour)
# 4. export as csv
# 4. call the python importer to export the csv via line protocoll into influx, 6k points at once

[ -z "$(nvram get odmpid)" ] && ROUTER_MODEL=$(nvram get productid) || ROUTER_MODEL=$(nvram get odmpid)
dir=`dirname $0`
readonly SCRIPT_NAME="extstats"
readonly MOD_NAME="mod_trafficAnalyzer"
readonly SCRIPT_DIR="/jffs/addons/$SCRIPT_NAME.d"
readonly SCRIPT_CONF="$SCRIPT_DIR/config.conf"

#InfluxDB Settings
readonly EXTS_URL=$(grep "EXTS_URL" "$SCRIPT_CONF" | cut -f2 -d"=")
readonly EXTS_DATABASE=$(grep "EXTS_DATABASE" "$SCRIPT_CONF" | cut -f2 -d"=")
readonly EXTS_USERNAME=$(grep "EXTS_USERNAME" "$SCRIPT_CONF" | cut -f2 -d"=")
readonly EXTS_PASSWORD=$(grep "EXTS_PASSWORD" "$SCRIPT_CONF" | cut -f2 -d"=")
readonly EXTS_USESSH=$(grep "EXTS_USESSH" "$SCRIPT_CONF" | cut -f2 -d"=")
readonly EXTS_NOVERIFIY=$(grep "EXTS_NOVERIFIY" "$SCRIPT_CONF" | cut -f2 -d"=")
readonly EXTS_PORT=$(grep "EXTS_PORT" "$SCRIPT_CONF" | cut -f2 -d"=")
readonly INFLUX_DB_METRIC_NAME="router.trafficAnalyzer"

#Script Settings
readonly TEMP_FOLDER="/tmp"
readonly DHCP_HOSTNAMESMAC_CSV="/tmp/dhcp_clients_mac.csv"
readonly DBFILE_ORG="/jffs/.sys/TrafficAnalyzer/TrafficAnalyzer.db"
readonly DBFILE_COPY="$TEMP_FOLDER/$MOD_NAME.db"
readonly CSV_TEMP_FILE="$TEMP_FOLDER/$MOD_NAME.csv"
readonly TABLE="traffic"
readonly SCRIPT_MODE="${1}" #(update or full)
readonly SCRIPT_DEBUG="${2}" #(true/false)
readonly SCRIPT_DEBUG_SYSLOG="${3}" #(true/false)
readonly SCRIPT_DEBUG_FULL="${4}" #(true/false)

#generate new clientlist
$SCRIPT_DIR/helper_dhcpstaticlist.sh >/dev/null 2>&1

#########################################################################################################

 if [ -z "${SCRIPT_MODE}" ]; then
      echo "Usage: ./$MOD_NAME.sh [update | full] [debug true/false] [send debug to syslog true/false] "
      echo "like Usage: ./$MOD_NAME.sh update true false"
      echo "update gets the data from the last hour"
      echo "full imports all data"
      return 1
  fi


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

#delete old temp data if something went wrong the last run, we dont want to have old stuff
if [ -f "$CSV_TEMP_FILE" ]; then
	rm -f "$CSV_TEMP_FILE"
fi

if [ -f "$DBFILE_COPY" ]; then
	rm -f "$DBFILE_COPY"
fi

lock()
{
	while [ -f /tmp/$MOD_NAME.lock ]; do
		if [ ! -d /proc/$(cat /$TEMP_FOLDER/$MOD_NAME.lock) ]; then
			echo "WARNING : Lockfile detected but process $(cat /tmp/$MOD_NAME.lock) does not exist !"
			rm -f /$TEMP_FOLDER/$MOD_NAME.lock
		fi
		sleep 1
	done
	echo $$ > /$TEMP_FOLDER/$MOD_NAME.lock
}

unlock()
{
	rm -f /$TEMP_FOLDER/$MOD_NAME.lock
}

CURDATE=`date +%s`
STARTDATE=`expr $CURDATE - 3600`

if [ ! -r "$DBFILE_ORG" ]; then
	Print_Output "$DBFILE_ORG not readable. TrafficAnalyser inactiv?" true true
	exit 1
fi

#only working on a copy
cp $DBFILE_ORG $DBFILE_COPY	
if [ ! -r "$DBFILE_COPY" ]; then
	Print_Output "$DBFILE_COPY not readable" true true
	exit 1
fi

#get the traffic data
#sqlite3  /opt/tmp/mod_trafficAnalyzer.db "select * from clients;"
sqlite3 $DBFILE_COPY <<!
CREATE TABLE clients(
  hostname TEXT NOT NULL,
  mac TEXT NOT NULL
);
!

#inject the hostnames to the mac adresses
sqlite3 $DBFILE_COPY <<!
.mode csv
.import $DHCP_HOSTNAMESMAC_CSV clients
!

if [ "$SCRIPT_DEBUG_FULL" = "true" ]; then
Print_Output "Clientlist from $DHCP_HOSTNAMESMAC_CSV imported into $DBFILE_COPY:"
#debug
sqlite3 $DBFILE_COPY <<!
SELECT * from clients;
!
fi
#sql statement for manual use 
#select mac,app_name,cat_name, strftime('%Y-%m-%d %H:%M:%S', datetime(timestamp, 'unixepoch')) as timestamp,tx,rx from  $TABLE   ;
#sqlite3  /opt/tmp/mod_trafficAnalyzer.db "select clients.hostname, traffic.mac,app_name,cat_name, strftime('%Y-%m-%d %H:%M:%S', datetime(timestamp, 'unixepoch')) as timestamp,tx,rx from traffic left join clients on traffic.mac = clients.mac;"

#import all historical data
if [ "$1" = "full" ]; then
Print_Output "Full import, this can take some time"

sqlite3 $DBFILE_COPY <<!
.headers on
.mode csv
.output $CSV_TEMP_FILE
select clients.hostname, traffic.mac,app_name,cat_name, strftime('%Y-%m-%d %H:%M:%S', datetime(timestamp, 'unixepoch')) as timestamp,tx,rx from $TABLE left join clients on traffic.mac = clients.mac;
!
fi

#import only the data from last hour
if [ "$1" = "update" ]; then
Print_Output "Update import"
Print_Output "date: $CURDATE"
Print_Output "startdate: $STARTDATE"
#last hour

sqlite3 $DBFILE_COPY <<!
.headers on
.mode csv
.output $CSV_TEMP_FILE
select clients.hostname, traffic.mac,app_name,cat_name, strftime('%Y-%m-%d %H:%M:%S', datetime(timestamp, 'unixepoch')) as timestamp,tx,rx from $TABLE left join clients on traffic.mac = clients.mac WHERE timestamp >= $STARTDATE ;
!

fi

if [ "$SCRIPT_DEBUG_FULL" = "true" ]; then
	Print_Output "Debug $CSV_TEMP_FILE:"
	cat $CSV_TEMP_FILE
fi

#create new table
if [ "$2" = "create" ]; then
	DB_MODE="--create"
fi

if [ "$EXTS_USESSH" = "true" ]; then
	SSL_MODE="--ssl"
fi

if [ "$EXTS_NOVERIFIY" = "true" ]; then
	SSL_VERIFY="--verify_ssl"
fi

if [ ! -r "$CSV_TEMP_FILE" ]; then
	Print_Output "$CSV_TEMP_FILE not readable." true true
	exit 1
else
	lines=$(cat $CSV_TEMP_FILE | wc -l)
	Print_Output "Export Traffic Analyser into InfluxDB. $lines entrys" true true
fi

#call the python script to do the work
if [ -f "$CSV_TEMP_FILE" ]; then
	python $dir/export_py.py \
		--input $CSV_TEMP_FILE \
		-s "$EXTS_URL" \
		-u "$EXTS_USERNAME" \
		-p "$EXTS_PASSWORD" \
		--port "$EXTS_PORT" \
		--dbname "$EXTS_DATABASE" \
		$DB_MODE \
		$SSL_MODE \
		$SSL_VERIFY \
		--tagcolumns hostname,mac,app_name,cat_name \
		--fieldcolumns mac,app_name,cat_name,timestamp,tx,rx,hostname \
		--metricname $INFLUX_DB_METRIC_NAME \
		--batchsize 6000  \
		-tc timestamp \
		-tf "%Y-%m-%d %H:%M:%S"  -g \
	#rm $CSV_TEMP_FILE
else
	echo "no $CSV_TEMP_FILE"
fi

#cleanup
# Free some memory
unlock
rm -f $CSV_TEMP_FILE
rm -f $DBFILE_COPY


#cru a trafA "15 * * * * /mnt/routerUSB/scripts/scripts/asuswrt/metrics2influx/router_TrafficAnalyzer_influx.sh update "
