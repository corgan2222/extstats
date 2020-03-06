#!/bin/sh
#./router_constats_influx.sh full create
#./router_constats_influx.sh update
#cru a connstats "45 * * * * /mnt/routerUSB/scripts/scripts/asuswrt/metrics2influx/router_constats_influx.sh update "

	[ -z "$(nvram get odmpid)" ] && ROUTER_MODEL=$(nvram get productid) || ROUTER_MODEL=$(nvram get odmpid)
	dir=`dirname $0`
	readonly SCRIPT_NAME="extstats"
	readonly MOD_NAME="mod_constats"
	readonly SCRIPT_DIR="/jffs/addons/$SCRIPT_NAME.d"
	readonly SCRIPT_CONF="$SCRIPT_DIR/config.conf"

	#########################################################################################
	#InfluxDB Settings
	readonly EXTS_URL=$(grep "EXTS_URL" "$SCRIPT_CONF" | cut -f2 -d"=")
	readonly EXTS_DATABASE=$(grep "EXTS_DATABASE" "$SCRIPT_CONF" | cut -f2 -d"=")	
	readonly EXTS_USERNAME=$(grep "EXTS_USERNAME" "$SCRIPT_CONF" | cut -f2 -d"=")
	readonly EXTS_PASSWORD=$(grep "EXTS_PASSWORD" "$SCRIPT_CONF" | cut -f2 -d"=")
	readonly EXTS_USESSH=$(grep "EXTS_USESSH" "$SCRIPT_CONF" | cut -f2 -d"=")
	readonly EXTS_NOVERIFIY=$(grep "EXTS_NOVERIFIY" "$SCRIPT_CONF" | cut -f2 -d"=")
	readonly EXTS_PORT=$(grep "EXTS_PORT" "$SCRIPT_CONF" | cut -f2 -d"=")

	#Script Settings
	readonly TEMP_FOLDER="/opt/tmp"
	readonly DBFILE_ORG="/jffs/addons/connmon.d/connstats.db"
	readonly DBFILE_COPY="$TEMP_FOLDER/$MOD_NAME.db"
	readonly CSV_TEMP_FILE="$TEMP_FOLDER/$MOD_NAME.csv"
	readonly TABLE="connstats"
	readonly SCRIPT_MODE="${1}" #(update or full)
	readonly SCRIPT_DEBUG="${2}" #(true/false)
	readonly SCRIPT_DEBUG_SYSLOG="${3}" #(true/false)
	readonly SCRIPT_DEBUG_FULL="${4}" #(true/false)
	readonly LOCK_FILE="/tmp/$MOD_NAME.lock"
	INFLUX_DB_METRIC_NAME="router.uptime"

    #INFLUX_DB_NAME="router.office"
 	#OUT_FOLDER="/mnt/routerUSB/exports"
	#DBFILE="/jffs/addons/connmon.d/connstats.db"
	#DBFILE_tmp="/mnt/routerUSB/tmp/connstats_tmp.db"
    #TABLE="connstats"
    #CSV_FILE="/mnt/routerUSB/exports/connstats.csv"

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


if [ -f "$CSV_TEMP_FILE" ]; then
	rm -f $CSV_FILE
fi

if [ -f "$DBFILE_COPY" ]; then
	rm -f $DBFILE_tmp
fi
	lock()
	{
		while [ -f $LOCK_FILE ]; do
			if [ ! -d /proc/$(cat $LOCK_FILE) ]; then
				echo "WARNING : Lockfile detected but process $(cat $LOCK_FILE) does not exist !"
				rm -f $LOCK_FILE
			fi
			sleep 1
		done
		echo $$ > $LOCK_FILE
	}

	unlock()
	{
		rm -f $LOCK_FILE
	}

    lock
    CURDATE=`date +%s`
    STARTDATE=`expr $CURDATE - 3600`

	if [ ! -r "$DBFILE_ORG" ]; then
		Print_Output "$DBFILE_ORG not readable. Connmon not activ?" true true
		exit 1
	fi

	cp $DBFILE_ORG $DBFILE_COPY

	if [ ! -r "$DBFILE_COPY" ]; then
		Print_Output "$DBFILE_COPY not readable" true true
		exit 1
	fi

#select mac,app_name,cat_name, strftime('%Y-%m-%d %H:%M:%S', datetime(timestamp, 'unixepoch')) as timestamp,tx,rx from  $TABLE   ;
#all data
if [ "$1" = "full" ]; then

sqlite3 $DBFILE_COPY <<!
.headers on
.mode csv
.output $CSV_TEMP_FILE
select StatID,strftime('%Y-%m-%d %H:%M:%S', datetime(Timestamp, 'unixepoch')) as Timestamp,Ping,Jitter,Packet_Loss from $TABLE;
!

fi


if [ "$1" = "update" ]; then
#last hour

sqlite3 $DBFILE_COPY <<!
.headers on
.mode csv
.output $CSV_TEMP_FILE
select  StatID,strftime('%Y-%m-%d %H:%M:%S', datetime(Timestamp, 'unixepoch')) as Timestamp,Ping,Jitter,Packet_Loss from $TABLE WHERE Timestamp >= $STARTDATE ;
!

fi

if [ "$SCRIPT_DEBUG_FULL" = "true" ]; then
Print_Output "data from $DBFILE_COPY:"
#debug
sqlite3 $DBFILE_COPY <<!
SELECT * from $TABLE;
!
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
	Print_Output "Export Uptime data into InfluxDB. $lines entrys" true true
fi

if [ "$2" = "create" ]; then
	createDB="--create"
fi

if [ "$SCRIPT_DEBUG_FULL" = "true" ]; then
	Print_Output "Debug $CSV_TEMP_FILE:"
	cat $CSV_TEMP_FILE
fi

if [ -f "$CSV_TEMP_FILE" ]; then
	#python $dir/csv2influx.py --input /mnt/routerUSB/exports/connstats.csv --dbname router.office $createDB --tagcolumns hostname,mac,app_name,cat_name --fieldcolumns mac,app_name,cat_name,timestamp,tx,rx,hostname --metricname router.traffic --batchsize 6000  -tc timestamp -tf "%Y-%m-%d %H:%M:%S"  -g 
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
		--fieldcolumns Timestamp,Ping,Jitter,Packet_Loss \
		--metricname $INFLUX_DB_METRIC_NAME \
		--batchsize 6000  \
		-tc Timestamp \
		-tf "%Y-%m-%d %H:%M:%S"  -g \
	
	rm -f $CSV_TEMP_FILE
fi

#cleanup
# Free some memory
rm -f $DBFILE_COPY
unlock



#cru a trafA "15 * * * * /mnt/routerUSB/scripts/scripts/asuswrt/metrics2influx/router_TrafficAnalyzer_influx.sh update "
