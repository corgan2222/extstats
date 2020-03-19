# extstats
Export Metrics from Asus RT-AX88U Router into influxDB

[![extstats](https://raw.githubusercontent.com/corgan2222/extstats/master/images_thumbs/extstats.jpg)](https://raw.githubusercontent.com/corgan2222/extstats/master/images/extstats.jpg)

# ALPHA Version! Dont use in production yet!

## [Install ](https://github.com/corgan2222/extstats/wiki/Setup)
`/usr/sbin/curl --retry 3 "https://raw.githubusercontent.com/corgan2222/extstats/master/extstats.sh" -o "/jffs/scripts/extstats" && chmod 0755 /jffs/scripts/extstats && /jffs/scripts/extstats install`

## Requirements

* running influxDB

## Features

* Installer and Update Script
* Shell "GUI" Database Setup
* Debug and Test Functions
* Dependency Test 

* **Export these Metrics from AsusWRT-Merlin into InfluxDB**
* Basis Stats like CPU, Memory, Processes, Network, uptime, Filesystem, Swap
https://github.com/corgan2222/extstats/wiki/mod_basic
* Extended WiFi Informations for each Client https://github.com/corgan2222/extstats/wiki/mod_wifi_clients
* Traffic Analyser per Client https://github.com/corgan2222/extstats/wiki/mod_client_traffic
* Export the Asus internal Traffic Analyser Data https://github.com/corgan2222/extstats/wiki/mod_trafficAnalyzer
* VPN Statistics https://github.com/corgan2222/extstats/wiki/mod_vpn_client
* Support for Conmon Stats (Uptime Monitoring) [connmon | Jack Yaz](https://www.snbforums.com/threads/connmon-internet-connection-monitoring.56163/) https://github.com/corgan2222/extstats/wiki/mod_constats-(Uptime-Monitoring)
* Support for spdMerlin Stats (Speedtest Data) [spdMerlin | Jack Yaz](https://www.snbforums.com/threads/spdmerlin-automated-speedtests-with-graphs.55904/) https://github.com/corgan2222/extstats/wiki/mod_spdstats-(Speedtest-Monitoring)

# Known Bugs
1. no autostart atm (u have to reinstall on reboot)
2. if you running aiMesh, the WiFi Clients are not shown

# ToDos
1. autostart service
2. make it compatible with other asusWRT routers
3. integrate with Conmon and spdStats, that the plugins can share there data easy, without parsing the database
4. import Diversion Data
5. make a template for user, to easy integrate there informations
6. show database infos, like MEASUREMENTS counts
7. database management, move and delete data from database
8. show database infos in the asus webui
9. refactor code, remove redundant code

# Help needed
1. if you are an advanced user or developer, please helpt o port this on other asus routers. I only have the RT-AX88U.
2. how to get the wifi client informations, like rssi and antenna data if using aimesh
3. how to get cpu temperature
4. is there any nvram, asusWRT developer documentation that are not public? couldnt found any asuswrt specific docs.

# disclamer
Im not a linux guru and i have done this for my personal use and put a lot of work into this script to make it public availible. For shure are there better, performanter or easyier ways to do some task. So if you have tips how to improve this script, im more than happy if you let me know. stefan [@] knaak.org


[![extstats](https://raw.githubusercontent.com/corgan2222/extstats/master/images_thumbs/extstats.jpg)](https://raw.githubusercontent.com/corgan2222/extstats/master/images/extstats.jpg)

[![extstats](https://raw.githubusercontent.com/corgan2222/extstats/master/images_thumbs/extstats_fs.jpg)](https://raw.githubusercontent.com/corgan2222/extstats/master/images/extstats_fs.jpg)

[![extstats](https://raw.githubusercontent.com/corgan2222/extstats/master/images_thumbs/extstats_network.jpg)](https://raw.githubusercontent.com/corgan2222/extstats/master/images/extstats_network.jpg)

[![extstats](https://raw.githubusercontent.com/corgan2222/extstats/master/images_thumbs/extstats_client_traffic.jpg)](https://raw.githubusercontent.com/corgan2222/extstats/master/images/extstats_client_traffic.jpg)

[![extstats](https://raw.githubusercontent.com/corgan2222/extstats/master/images_thumbs/extstats_trafficbyclient.jpg)](https://raw.githubusercontent.com/corgan2222/extstats/master/images/extstats_trafficbyclient.jpg)

[![extstats](https://raw.githubusercontent.com/corgan2222/extstats/master/images_thumbs/extstats_speedtest.jpg)](https://raw.githubusercontent.com/corgan2222/extstats/master/images/extstats_speedtest.jpg)

[![extstats](https://raw.githubusercontent.com/corgan2222/extstats/master/images_thumbs/extstats_asus_ta.jpg)](https://raw.githubusercontent.com/corgan2222/extstats/master/images/extstats_asus_ta.jpg)

[![extstats](https://raw.githubusercontent.com/corgan2222/extstats/master/images_thumbs/extstats_wifi.jpg)](https://raw.githubusercontent.com/corgan2222/extstats/master/images/extstats_wifi.jpg)

[![extstats](https://raw.githubusercontent.com/corgan2222/extstats/master/images_thumbs/extstats_wifi2.jpg)](https://raw.githubusercontent.com/corgan2222/extstats/master/images/extstats_wifi2.jpg)

[![extstats](https://raw.githubusercontent.com/corgan2222/extstats/master/images_thumbs/extstats_wifi3.jpg)](https://raw.githubusercontent.com/corgan2222/extstats/master/images/extstats_wifi3.jpg)



## Thanks to Jack Yaz,  thelonelycoder and all the other developers! The install and update functions are based on there work!

