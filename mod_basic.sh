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
    #http://www.linuxhowtos.org/System/procstat.htm

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

    load1=`top -bn1 | head -3 | awk '/Load average:/ {print $3}' | sed 's/%//g'`
    load5=`top -bn1 | head -3 | awk '/Load average:/ {print $4}' | sed 's/%//g'`
    load15=`top -bn1 | head -3 | awk '/Load average:/ {print $5}' | sed 's/%//g'`

    processes=$(ps | wc -l)

    columns="host=${ROUTER_MODEL}"
    points="usr=$points2,sys=$points4,nic=$points6,idle=$points8,io=$points10,irq=$points12,sirq=$points12,load1=$load1,load5=$load5,load15=$load15,processes=$processes"
    mod_cpu_data="$name,$columns $points ${CURDATE}000000000"

    Print_Output "$SCRIPT_debug" "$mod_cpu_data" "$WARN"
    $dir/export.sh "$mod_cpu_data" "$SCRIPT_debug"
}

mod_mem(){
    name="router.mem"
    columns="host=${ROUTER_MODEL}"
    CURDATE=`date +%s`

    total=$(free -h | grep "Mem:" | awk '{print $2}')
    used_kb=`top -bn1 | head -3 | awk '/Mem/ {print $2}' | sed 's/K//g'`
    free_kb=`top -bn1 | head -3 | awk '/Mem/ {print $4}' | sed 's/K//g'`
    shrd_kb=`top -bn1 | head -3 | awk '/Mem/ {print $6}' | sed 's/K//g'`
    buff_kb=`top -bn1 | head -3 | awk '/Mem/ {print $8}' | sed 's/K//g'`
    cached_kb=`top -bn1 | head -3 | awk '/Mem/ {print $10}' | sed 's/K//g'`

    #ToDo: how to get rid of the first line
    #size: 78844 bytes (52228 left)
    #sysinfo | grep MemTotal | awk '/Mem/ {print $2}' | head -1

    points="total=$total,used_kb=${used_kb},free_kb=${free_kb},shrd_kb=${shrd_kb},buff_kb=${buff_kb},cached_kb=${cached_kb}"
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
    DATA_TEMP_FILE="/tmp/mod_net.influx"
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
            Print_Output "$SCRIPT_debug" "$mod_net_data" "$WARN"

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
    df | tr -s ' ' ',' | grep -vE '^Filesystem|cdrom|www' | sed 's/%//' > $DF_CSV

    while read line
    do
        Filesystem=$(echo ${line} | cut -d',' -f1) #Filesystem
        blocks=$(echo ${line} | cut -d',' -f2) #1K-blocks
        Used=$(echo ${line} | cut -d',' -f3) #Used
        Available=$(echo ${line} | cut -d',' -f4) #Available
        Use=$(echo ${line} | cut -d',' -f5) #Use
        Free=$(echo "scale=0;(100-$Use)" | bc) 
        Mounted=$(echo ${line} | cut -d',' -f6) #Mounted on



        columns="host=${ROUTER_MODEL},Filesystem=$Filesystem,MountedOn=$Mounted"
        filesystem_data="$INFLUX_DB_METRIC_NAME,$columns blocks=$blocks,Used=$Used,Available=$Available,UsedPercent=$Use,FreePercent=$Free ${CURDATE}000000000"

        Print_Output "${SCRIPT_debug}_mod_filesystem" "$filesystem_data" "$WARN"
        $dir/export.sh "$filesystem_data" "$SCRIPT_debug"

    done < $DF_CSV

}

mod_swap()
{
    CURDATE=`date +%s`
    INFLUX_DB_METRIC_NAME="router.swap"
    

    if [ "$(wc -l < /proc/swaps)" -ge "2" ]; then 
        swap_filename=$(cat "/proc/swaps" | grep "file" | awk '{print $1}')
        swap_total=$(free -h | grep "Swap" | awk '{print $2}')
        swap_used=$(free -h | grep "Swap" | awk '{print $3}')
        swap_free=$(free -h | grep "Swap" | awk '{print $4}')

        if [ $swap_total -gt 0 ]; then
            swap_used_percent=$(echo "scale=2;(($swap_used/$swap_total)*100)" | bc) 
            swap_free_percent=$(echo "scale=2;(($swap_free/$swap_total)*100)" | bc) 
            swap_per=",swap_used_percent=$swap_used_percent,swap_free_percent=$swap_free_percent"
        fi

        columns="host=${ROUTER_MODEL},MountedOn=$swap_filename"
        filesystem_data="$INFLUX_DB_METRIC_NAME,$columns swap_total=$swap_total,swap_used=$swap_used,swap_free=$swap_free${swap_per} ${CURDATE}000000000"

        Print_Output "${SCRIPT_debug}_mod_swap" "$filesystem_data" "$WARN"
        $dir/export.sh "$filesystem_data" "$SCRIPT_debug"
    fi
}

mod_divstats(){
    uidivstats="/jffs/addons/uiDivStats.d/uidivstats.txt"

     if [ -r "$divstats" ]; then
        CURDATE=`date +%s`

        TOTAL_D_BL=$(cat $divstats | grep "domains in total are blocked" | awk '{print $1}' | sed "s/,//g" )
        BLOCKED_BL=$(cat $divstats | grep "blocked by blocking list" | awk '{print $1}' | sed "s/,//g")
        BLOCKED_BLACKLIST=$(cat $divstats | grep "blocked by blacklist" | awk '{print $1}' | sed "s/,//g" )
        BLOCKED_WILDCARD=$(cat $divstats | grep "blocked by wildcard blacklist" | awk '{print $1}' | sed "s/,//g" )
        ADS_TOTAL_BL=$(cat $divstats | grep "ads in total blocked" | awk '{print $1}' | sed "s/,//g" )
        ADS_THIS_WEEK=$(cat $divstats | grep "ads this week, since last Monday" | awk '{print $1}' | sed "s/,//g" )
        NEW_ADDS=$(cat $divstats | grep "new ads, since" | awk '{print $1}' | sed "s/,//g" )

        name="router.uidivstats"
        columns="host=${ROUTER_MODEL}"
        divstats_data="$name,$columns domain_total_blocked=$TOTAL_D_BL,blocked_by_blocking_list=$BLOCKED_BL,blocked_by_blacklist=$BLOCKED_BLACKLIST,blocked_by_wildcard_blacklist=$BLOCKED_WILDCARD,ads_total_blocked=$ADS_TOTAL_BL,ads_this_week=$ADS_THIS_WEEK,new_ads=$NEW_ADDS ${CURDATE}000000000"
        Print_Output "${SCRIPT_debug}" "$divstats_data" "$WARN"
        $dir/export.sh "$divstats_data" "$SCRIPT_debug"    
    fi    
}

mod_skynet(){
    EXT_skynetloc="$(grep -ow "skynetloc=.* # Skynet" /jffs/scripts/firewall-start 2>/dev/null | grep -vE "^#" | awk '{print $1}' | cut -c 11-)"
    EXT_skynetipset="${EXT_skynetloc}/skynet.ipset"

    if [ -r "$EXT_skynetloc" ]; then
        CURDATE=`date +%s`

	    EXT_blacklist1count="$(grep -Foc "add Skynet-Black" "$EXT_skynetipset" 2> /dev/null)"
	    EXT_blacklist2count="$(grep -Foc "add Skynet-Block" "$EXT_skynetipset" 2> /dev/null)"

        name="router.skynet"
        columns="host=${ROUTER_MODEL}"
        skynet_data="$name,$columns IPs_blocked=$EXT_blacklist1count,IPs_ranged_blocked=$EXT_blacklist2count ${CURDATE}000000000"
        Print_Output "${SCRIPT_debug}" "$skynet_data" "$WARN"
        $dir/export.sh "$skynet_data" "$SCRIPT_debug"
    fi
}


mod_cpu 
mod_mem
mod_temp
mod_net
mod_connections
mod_uptime
mod_filesystem
mod_swap
mod_uidivstats
mod_skynet

