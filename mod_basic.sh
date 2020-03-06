#!/bin/sh

[ -z "$(nvram get odmpid)" ] && ROUTER_MODEL=$(nvram get productid) || ROUTER_MODEL=$(nvram get odmpid)
dir=`dirname $0`
readonly SCRIPT_NAME="extstats"
readonly MOD_NAME="mod_basic"
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

mod_cpu(){
    CURDATE=`date +%s`

    name="router.cpu"
    columns="usr sys nic idle io irq sirq"
    points2=`top -bn1 | head -3 | awk '/CPU/ {print $2}' | sed 's/%//g'`
    points4=`top -bn1 | head -3 | awk '/CPU/ {print $4}' | sed 's/%//g'`
    points6=`top -bn1 | head -3 | awk '/CPU/ {print $6}' | sed 's/%//g'`
    points8=`top -bn1 | head -3 | awk '/CPU/ {print $8}' | sed 's/%//g'`
    points10=`top -bn1 | head -3 | awk '/CPU/ {print $10}' | sed 's/%//g'`
    points12=`top -bn1 | head -3 | awk '/CPU/ {print $12}' | sed 's/%//g'`
    points14=`top -bn1 | head -3 | awk '/CPU/ {print $14}' | sed 's/%//g'`

    columns="host=${ROUTER_MODEL}"
    points="usr=$points2,sys=$points4,nic=$points6,idle=$points8,io=$points10,irq=$points12,sirq=$points12"
    mod_cpu_data="$name,$columns $points ${CURDATE}000000000"

    Print_Output "$SCRIPT_debug" "$mod_cpu_data" "$WARN"
    $dir/export.sh "$mod_cpu_data" "$SCRIPT_debug"
}

mod_mem(){
    name="router.mem"
    columns="host=${ROUTER_MODEL}"
    CURDATE=`date +%s`

    used_kb=`top -bn1 | head -3 | awk '/Mem/ {print $2}' | sed 's/K//g'`
    free_kb=`top -bn1 | head -3 | awk '/Mem/ {print $4}' | sed 's/K//g'`
    shrd_kb=`top -bn1 | head -3 | awk '/Mem/ {print $6}' | sed 's/K//g'`
    buff_kb=`top -bn1 | head -3 | awk '/Mem/ {print $8}' | sed 's/K//g'`
    cached_kb=`top -bn1 | head -3 | awk '/Mem/ {print $10}' | sed 's/K//g'`

    #ToDo: how to get rid of the first line
    #size: 78844 bytes (52228 left)
    #sysinfo | grep MemTotal | awk '/Mem/ {print $2}' | head -1

    points="used_kb=${used_kb},free_kb=${free_kb},shrd_kb=${shrd_kb},buff_kb=${buff_kb},cached_kb=${cached_kb}"
    mod_mem_data="$name,$columns $points ${CURDATE}000000000"
    Print_Output "$SCRIPT_debug" "$mod_mem_data" "$WARN"
    $dir/export.sh "$mod_mem_data" "$SCRIPT_debug"
}

mod_temp(){

    name="router.temp"
    CURDATE=`date +%s`
    columns="host=${ROUTER_MODEL}"

    p1=`wl -i eth6 phy_tempsense | awk '{ print $1 * .5 + 20 }'` # 2.4GHz
    p2=`wl -i eth7 phy_tempsense | awk '{ print $1 * .5 + 20 }'` # 5.0GHz
    mod_temp_data="$name,${columns} temp_24=$p1,temp_50=$p2 ${CURDATE}000000000"
    Print_Output "$SCRIPT_debug" "$mod_temp_data" "$WARN"
    $dir/export.sh "$mod_temp_data" "$SCRIPT_debug"
}

mod_net(){
    maxint=4294967295
    
    scriptname=`basename $0`
    old="/tmp/$scriptname.data.old"
    new="/tmp/$scriptname.data.new"
    old_epoch_file="/tmp/$scriptname.epoch.old"
    DATA_TEMP_FILE="/opt/tmp/mod_net.influx"
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
            CURDATE=`date +%s`
            columns="host=${ROUTER_MODEL},interface=${interface}"
            points="recv_mbps=${recv_mbps},recv_errs=${recv_errs},recv_drop=${recv_drop},trans_mbps=${trans_mbps},trans_errs=${trans_errs},trans_drop=${trans_drop}"
            mod_net_data="$name,${columns} ${points} ${CURDATE}000000000"
            echo $mod_net_data >> $DATA_TEMP_FILE

            #$dir/export.sh "$mod_net_data" "$SCRIPT_debug"
            #echo "$mod_net_data"
            #Print_Output "$SCRIPT_debug" "$mod_net_data" "$WARN"

        done
        mv $new $old
    fi

    cat /proc/net/dev | tail +3 | tr ':|' '  ' | awk '{print $1,$2,$4,$5,$10,$12,$13}' > $new
    $dir/export.sh "$DATA_TEMP_FILE" "$SCRIPT_debug" "file"
}

mod_connections(){
    CURDATE=`date +%s`
    active_dhcp_leases=$(cat /var/lib/misc/dnsmasq.leases| wc -l)
    mod_connected_clients=$(arp -a | awk '$4!="<incomplete>"' | wc -l)
    wifi_24=`wl -i eth6 assoclist | awk '{print $2}' | wc -l`
    wifi_5=`wl -i eth7 assoclist | awk '{print $2}' | wc -l`


    name="router.connections"
    columns="host=${ROUTER_MODEL},type=connections"
    mod_active_dhcp_leases_data="$name,$columns dhcp_leases=$active_dhcp_leases,connected_clients=$mod_connected_clients,wifi_24=$wifi_24,wifi_5=$wifi_5 ${CURDATE}000000000"
    Print_Output "${SCRIPT_debug}_mod_connections" "$mod_active_dhcp_leases_data" "$WARN"
    $dir/export.sh "$mod_active_dhcp_leases_data" "$SCRIPT_debug"

}

mod_uptime(){
    CURDATE=`date +%s`
    uptime=$(cat /proc/uptime | cut -d' ' -f1)
    uptime_idle=$(cat /proc/uptime | cut -d' ' -f2)

    name="router.uptime"
    columns="host=${ROUTER_MODEL}"
    uptime_data="$name,$columns uptime=$uptime,uptime_idle=$uptime_idle ${CURDATE}000000000"
    Print_Output "${SCRIPT_debug}" "$uptime_data" "$WARN"
    $dir/export.sh "$uptime_data" "$SCRIPT_debug"    
}

mod_filesystem()
{
    #CURDATE=`date +%F" "%T`
    CURDATE=`date +%s`
    readonly DF_CSV="/opt/tmp/DF.csv"
    readonly DF_CSV_TMP="/opt/tmp/DF_TEMP.csv"
    INFLUX_DB_METRIC_NAME="router.filesystem"

    rm -f $DF_CSV
    #filesystem info, with filter and remove % from used
    df | tr -s ' ' ',' | grep -vE '^Filesystem|tmpfs|cdrom|www' | sed 's/%//' > $DF_CSV

    while read line
    do
        Filesystem=$(echo ${line} | cut -d',' -f1) #Filesystem
        blocks=$(echo ${line} | cut -d',' -f2) #1K-blocks
        Used=$(echo ${line} | cut -d',' -f3) #Used
        Available=$(echo ${line} | cut -d',' -f4) #Available
        Use=$(echo ${line} | cut -d',' -f5) #Use
        Mounted=$(echo ${line} | cut -d',' -f6) #Mounted on

        columns="host=${ROUTER_MODEL},Filesystem=$Filesystem,MountedOn=$Mounted"
        filesystem_data="$INFLUX_DB_METRIC_NAME,$columns blocks=$blocks,Used=$Used,Available=$Available,UsedPercent=$Use ${CURDATE}000000000"

        Print_Output "${SCRIPT_debug}_mod_filesystem" "$filesystem_data" "$WARN"
        $dir/export.sh "$filesystem_data" "$SCRIPT_debug"

    done < $DF_CSV

}

mod_cpu 
mod_mem
mod_temp
mod_net
mod_connections
mod_uptime
mod_filesystem


#    i=0
#     while read line
#     do
#       if [[ $i -gt 0 ]]; then
#            echo "\"${CURDATE}\",${line},0" >> $DF_CSV_TMP
#         else
#            echo "timestamp,${line}" >> $DF_CSV_TMP
#        fi
#        i=$((i+1))
#     done < $DF_CSV

#     #cat $DF_CSV
#     cat $DF_CSV_TMP

    # #call the python script to do the work
    # if [ -f "$DF_CSV_TMP" ]; then
    #     python $dir/export_py.py \
    #         --input $DF_CSV_TMP \
    #         -s "$EXTS_URL" \
    #         -u "$EXTS_USERNAME" \
    #         -p "$EXTS_PASSWORD" \
    #         --port "$EXTS_PORT" \
    #         --dbname "$EXTS_DATABASE" \
    #         $DB_MODE \
    #         $SSL_MODE \
    #         $SSL_VERIFY \
    #         --tagcolumns Filesystem \
    #         --fieldcolumns timestamp \
    #         --metricname $INFLUX_DB_METRIC_NAME \
    #         --batchsize 6000  \
    #         -tc timestamp \
    #         -tf "%Y-%m-%d %H:%M:%S"  -g \
    #     #rm $CSV_TEMP_FILE
    # else
    #     echo "no $DF_CSV_TMP"
    # fi
