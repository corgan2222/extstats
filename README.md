# extstats
Export Metrics from Asus RT-AX88U Router into influxDB

# ALPHA Version! Dont use in production yet!

## Features

* Grafana Template
* Installer and Update Script
* Shell "GUI" Database Setup, works with SSH auth and without password
* Debug and Test Functions
* Dependency Test 

* **Export these Metrics from AsusWRT-Merlin into InfluxDB**
* Basis Stats like CPU, Memory, Processes, Network, uptime, Filesystem, Swap
* Extended WiFi Informations for each Client
* Traffic Analyser per Client
* Export the Asus internal Traffic Analyser Data
* VPN Statistics
* Support for Conmon Stats (Uptime Monitoring) [connmon | Jack Yaz](https://www.snbforums.com/threads/connmon-internet-connection-monitoring.56163/)
* Support for spdMerlin Stats (Speedtest Data) [spdMerlin | Jack Yaz](https://www.snbforums.com/threads/spdmerlin-automated-speedtests-with-graphs.55904/)

## Install
`/usr/sbin/curl --retry 3 "https://raw.githubusercontent.com/corgan2222/extstats/master/extstats.sh" -o "/jffs/scripts/extstats" && chmod 0755 /jffs/scripts/extstats && /jffs/scripts/extstats install`
