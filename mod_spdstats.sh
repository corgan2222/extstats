#!/bin/sh

	[ -z "$(nvram get odmpid)" ] && ROUTER_MODEL=$(nvram get productid) || ROUTER_MODEL=$(nvram get odmpid)
	dir=`dirname $0`
	readonly SCRIPT_NAME="extstats"
	readonly MOD_NAME="mod_spdstats"
	readonly SCRIPT_DIR="/jffs/addons/$SCRIPT_NAME.d"
	readonly SCRIPT_CONF="$SCRIPT_DIR/config.conf"

	#########################################################################################
	#InfluxDB Settings
	EXTS_URL=$(grep "EXTS_URL" "$SCRIPT_CONF" | cut -f2 -d"=")
	EXTS_DATABASE=$(grep "EXTS_DATABASE" "$SCRIPT_CONF" | cut -f2 -d"=")	
	readonly EXTS_USERNAME=$(grep "EXTS_USERNAME" "$SCRIPT_CONF" | cut -f2 -d"=")
	readonly EXTS_PASSWORD=$(grep "EXTS_PASSWORD" "$SCRIPT_CONF" | cut -f2 -d"=")
	readonly EXTS_USESSH=$(grep "EXTS_USESSH" "$SCRIPT_CONF" | cut -f2 -d"=")
	readonly EXTS_NOVERIFIY=$(grep "EXTS_NOVERIFIY" "$SCRIPT_CONF" | cut -f2 -d"=")
	readonly EXTS_PORT=$(grep "EXTS_PORT" "$SCRIPT_CONF" | cut -f2 -d"=")

	#Script Settings
	readonly TEMP_FOLDER="/opt/tmp"
	readonly DBFILE_ORG="/jffs/addons/spdmerlin.d/spdstats.db"
	readonly DBFILE_COPY="$TEMP_FOLDER/$MOD_NAME.db"
	readonly CSV_TEMP_FILE="$TEMP_FOLDER/$MOD_NAME.csv"
	readonly TABLE="spdstats_WAN"
	readonly SCRIPT_MODE="${1}" #(update or full)
	readonly SCRIPT_DEBUG="${2}" #(true/false)
	readonly SCRIPT_DEBUG_SYSLOG="${3}" #(true/false)
	readonly SCRIPT_DEBUG_FULL="${4}" #(true/false)
	readonly LOCK_FILE="/tmp/$MOD_NAME.lock"
	readonly INFLUX_DB_METRIC_NAME="router.spdstats"

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
	rm -f $CSV_TEMP_FILE
fi

if [ -f "$DBFILE_COPY" ]; then
	rm $DBFILE_COPY
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

    #echo $CURDATE
    #echo $STARTDATE 

	if [ ! -r "$DBFILE_ORG" ]; then
		Print_Output "$DBFILE_ORG not readable. spdStats not activ?" true true
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
select StatID,strftime('%Y-%m-%d %H:%M:%S', datetime(Timestamp, 'unixepoch')) as Timestamp,Download,Upload from $TABLE;
!

fi

if [ "$1" = "update" ]; then
#last hour
sqlite3 $DBFILE_COPY <<!
.headers on
.mode csv
.output $CSV_TEMP_FILE
select  StatID,strftime('%Y-%m-%d %H:%M:%S', datetime(Timestamp, 'unixepoch')) as Timestamp,Download,Upload from $TABLE WHERE Timestamp >= $STARTDATE ;
!
fi

if [ "$SCRIPT_DEBUG_FULL" = "true" ]; then
Print_Output "data from $DBFILE_COPY $TABLE:"
#debug
sqlite3 $DBFILE_COPY <<!
SELECT * from $TABLE;
!

Print_Output "Debug $CSV_TEMP_FILE:"
cat $CSV_TEMP_FILE
fi

if [ ! -r "$CSV_TEMP_FILE" ]; then
	Print_Output "$CSV_TEMP_FILE not readable." true true
	exit 1
else
	lines=$(cat $CSV_TEMP_FILE | wc -l)
	Print_Output "Export Speedtest data into InfluxDB. $lines entrys" true true
fi


if [ "$EXTS_USESSH" = "true" ]; then
	SSL_MODE="--ssl"
fi

if [ "$EXTS_NOVERIFIY" = "true" ]; then
	SSL_VERIFY="--verify_ssl"
fi

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
		--fieldcolumns StatID,Timestamp,Download,Upload \
		--metricname $INFLUX_DB_METRIC_NAME \
		--batchsize 6000 \
		-tc Timestamp \
		-tf "%Y-%m-%d %H:%M:%S"  -g \
		-tz "UTC"

	rm -f $CSV_TEMP_FILE
fi

#cleanup
# Free some memory
unlock
rm -f $DBFILE_COPY


