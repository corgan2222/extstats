#!/bin/sh
####################################################################################################
# Original Script: dhcpstaticlist.sh
# Original Author: Xentrk
# Last Updated Date: 4-January-2019
# Compatible with 384.15

# modified by Corgan
####################################################################################################

# Uncomment for debugging
#set -x

readonly DHCP_HOSTNAMESMAC="/opt/tmp/dhcp_clients_mac.txt"
readonly DHCP_HOSTNAMESMAC_CSV="/opt/tmp/dhcp_clients_mac.csv"
readonly DHCP_HOSTNAMESMAC_SB_IP="/opt/tmp/dhcp_clients_mac_sb_ip.txt"
readonly DHCP_HOSTNAMESMAC_SB_MAC="/opt/tmp/dhcp_clients_mac_sb_mac.txt"
readonly DHCP_HOSTNAMESMAC_SB_HOST="/opt/tmp/dhcp_clients_mac_sb_host.txt"

Parse_Hostnames() {

  true >/tmp/hostnames.$$
  OLDIFS=$IFS
  IFS="<"

  for ENTRY in $HOSTNAME_LIST; do
    if [ "$ENTRY" = "" ]; then
      continue
    fi
    MACID=$(echo "$ENTRY" | cut -d ">" -f 1)
    HOSTNAME=$(echo "$ENTRY" | cut -d ">" -f 2)
    echo "$MACID $HOSTNAME" >>/tmp/hostnames.$$
  done

  IFS=$OLDIFS
}

Save_Dnsmasq_Format() {

  # Obtain MAC and IP address from dhcp_staticlist and exclude DNS field by filtering using the first three octets of the lan_ipaddr
  if [ -s /jffs/nvram/dhcp_staticlist ]; then #HND Routers store dhcp_staticlist in a file
    awk '{print $0}' /jffs/nvram/dhcp_staticlist | grep -oE "((([0-9a-fA-F]{2})[ :-]){5}[0-9a-fA-F]{2})|(([0-9a-fA-F]){6}[:-]([0-9a-fA-F]){6})|([0-9a-fA-F]{12})" >/tmp/static_mac.$$
    awk '{print $0}' /jffs/nvram/dhcp_staticlist | grep -oE "(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)" | grep "$(nvram get lan_ipaddr | grep -Eo '([0-9]{1,3}\.[0-9]{1,3}(\.[0-9]{1,3}))')" >/tmp/static_ip.$$
  else # non-HND Routers store dhcp_staticlist in nvram
    nvram get dhcp_staticlist | grep -oE "((([0-9a-fA-F]{2})[ :-]){5}[0-9a-fA-F]{2})|(([0-9a-fA-F]){6}[:-]([0-9a-fA-F]){6})|([0-9a-fA-F]{12})" >/tmp/static_mac.$$
    #nvram get custom_clientlist | grep -oE "((([0-9a-fA-F]{2})[ :-]){5}[0-9a-fA-F]{2})|(([0-9a-fA-F]){6}[:-]([0-9a-fA-F]){6})|([0-9a-fA-F]{12})" >/tmp/static_mac.$$
    nvram get dhcp_staticlist | grep -oE "(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)" | grep "$(nvram get lan_ipaddr | grep -Eo '([0-9]{1,3}\.[0-9]{1,3}(\.[0-9]{1,3}))')" >/tmp/static_ip.$$
    #nvram get custom_clientlist | grep -oE "(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)" | grep "$(nvram get lan_ipaddr | grep -Eo '([0-9]{1,3}\.[0-9]{1,3}(\.[0-9]{1,3}))')" >/tmp/static_ip.$$
  fi

  # output /tmp/static_mac.$$ and /tmp/static_ip.$$ to /tmp/staticlist.$$ in two columns side by side
  #https://www.unix.com/shell-programming-and-scripting/161826-how-combine-2-files-into-1-file-2-columns.html
  awk 'NR==FNR{a[i++]=$0};{b[x++]=$0;};{k=x-i};END{for(j=0;j<i;) print a[j++],b[k++]}' /tmp/static_mac.$$ /tmp/static_ip.$$ >/tmp/staticlist.$$

  # some users reported <undefined in nvram..need to remove
  if [ -s /jffs/nvram/dhcp_hostnames ]; then #HND Routers store hostnames in a file
    HOSTNAME_LIST=$(awk '{print $0}' /jffs/nvram/dhcp_hostnames | sed 's/>undefined//')
  else
    HOSTNAME_LIST=$(nvram get dhcp_hostnames | sed 's/>undefined//')
  fi

  # Have to parse by internal field separator since hostnames are not required
  Parse_Hostnames

  # Join the /tmp/hostnames.$$ and /tmp/staticlist.$$ files together to form one file containing MAC, IP, HOSTNAME
  awk '
    NR==FNR { k[$1]=$2; next }
    { print $0, k[$1] }
  ' /tmp/hostnames.$$ /tmp/staticlist.$$ >/tmp/MACIPHOSTNAMES.$$

  # write dhcp-host entry in /jffs/configs/dnsmasq.conf.add format
  #sort -t . -k 3,3n -k 4,4n /tmp/MACIPHOSTNAMES.$$ | awk '{ print "dhcp-host="$1","$2","$3""; }' | sed 's/,$//'
  sort -t . -k 3,3n -k 4,4n /tmp/MACIPHOSTNAMES.$$ | awk '{ print ""$3" "$1" "$2""; }' | sed 's/,$//'
  sort -t . -k 3,3n -k 4,4n /tmp/MACIPHOSTNAMES.$$ | awk '{ print ""$3" "$1" "$2""; }' | sed 's/,$//' >  $DHCP_HOSTNAMESMAC

  #CSV
  rm $DHCP_HOSTNAMESMAC_CSV
  #header needed
  echo "hostname,mac" > $DHCP_HOSTNAMESMAC_CSV
  sort -t . -k 3,3n -k 4,4n /tmp/MACIPHOSTNAMES.$$ | awk '{ print ""$3","$1""; }' | sed 's/,$//'
  sort -t . -k 3,3n -k 4,4n /tmp/MACIPHOSTNAMES.$$ | awk '{ print ""$3","$1""; }' | sed 's/,$//' >>  $DHCP_HOSTNAMESMAC_CSV

  #cleanup
  rm -rf /tmp/static_mac.$$
  rm -rf /tmp/static_ip.$$
  rm -rf /tmp/staticlist.$$
  rm -rf /tmp/hostnames.$$
  rm -rf /tmp/MACIPHOSTNAMES.$$

  #save copys sorted
  sort -k 1,1 -s $DHCP_HOSTNAMESMAC > $DHCP_HOSTNAMESMAC_SB_HOST
  sort -k 2,2 -s $DHCP_HOSTNAMESMAC > $DHCP_HOSTNAMESMAC_SB_MAC
  sort -k 3,3 -s $DHCP_HOSTNAMESMAC > $DHCP_HOSTNAMESMAC_SB_IP

}

Save_Dnsmasq_Format


# nvram get custom_clientlist
# cat /var/lib/misc/dnsmasq.leases

