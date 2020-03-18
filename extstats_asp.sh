#!/bin/sh

source /usr/sbin/helper.sh

# Does the firmware support addons?
nvram get rc_support | grep -q am_addons
if [ $? != 0 ]
then
    logger "MyPage" "This firmware does not support addons!"
    exit 5
fi


# Obtain the first available mount point in $am_webui_page
am_get_webui_page /jffs/addons/extstats.d/extstats_www.asp

if [ "$am_webui_page" = "none" ]
then
    logger "extstats" "Unable to install Mypage"
    exit 5
fi
logger "extstats" "Mounting MyPage as $am_webui_page"

# Copy custom page
cp /jffs/addons/extstats.d/extstats_www.asp /www/user/$am_webui_page

# Copy menuTree (if no other script has done it yet) so we can modify it
if [ ! -f /tmp/menuTree.js ]
then
    cp /www/require/modules/menuTree.js /tmp/
    mount -o bind /tmp/menuTree.js /www/require/modules/menuTree.js
fi

# Set correct return URL within your copied page
sed -i "s/extstats_www.asp/$am_webui_page/g" /www/user/$am_webui_page

# Insert link at the end of the Tools menu.  Match partial string, since tabname can change between builds (if using an AS tag)
sed -i "/url: \"Tools_OtherSettings.asp\", tabName:/a {url: \"$am_webui_page\", tabName: \"extstats\"}," /tmp/menuTree.js

# sed and binding mounts don't work well together, so remount modified file
umount /www/require/modules/menuTree.js && mount -o bind /tmp/menuTree.js /www/require/modules/menuTree.js