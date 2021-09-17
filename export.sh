#/bin/sh

#####################################################
##                                                 ##
##                __  _____  __          __        ##
##   ___   _  __ / /_/ ___/ / /_ ____ _ / /_ _____ ##
##  / _ \ | |/_// __/\__ \ / __// __ `// __// ___/ ##
## /  __/_>  < / /_ ___/ // /_ / /_/ // /_ (__  )  ##
## \___//_/|_| \__//____/ \__/ \__,_/ \__//____/   ##
##                                                 ##
##      Stefan Knaak 2020                          ##
##                                                 ##
#####################################################
##                                                 ##
##      https://github.com/corgan2222/extstats     ##
##                                                 ##
#####################################################

    readonly SCRIPT_NAME="extstats"
    readonly SCRIPT_DIR="/jffs/addons/$SCRIPT_NAME.d"
    readonly SCRIPT_CONF="$SCRIPT_DIR/config.conf"
    EXTS_URL=$(grep "EXTS_URL" "$SCRIPT_CONF" | cut -f2 -d"=")
    EXTS_DATABASE=$(grep "EXTS_DATABASE" "$SCRIPT_CONF" | cut -f2 -d"=")
#    EXTS_DATABASE="extstats_test2020"
    EXTS_USERNAME=$(grep "EXTS_USERNAME" "$SCRIPT_CONF" | cut -f2 -d"=")
    EXTS_PASSWORD=$(grep "EXTS_PASSWORD" "$SCRIPT_CONF" | cut -f2 -d"=")
    EXTS_USESSH=$(grep "EXTS_USESSH" "$SCRIPT_CONF" | cut -f2 -d"=")
    EXTS_NOVERIFIY=$(grep "EXTS_NOVERIFIY" "$SCRIPT_CONF" | cut -f2 -d"=")
    EXTS_PORT=$(grep "EXTS_PORT" "$SCRIPT_CONF" | cut -f2 -d"=")

    if [ "$EXTS_USESSH" != "false" ]; then HTTP="https"; else HTTP="http"; fi
    if [ "$EXTS_NOVERIFIY" = "true" ]; then VERIFIY="-k"; fi #ignore ssl error

    CURL_OPTIONS="${VERIFIY}" #get is deprecated
    CURL_USER="-u ${EXTS_USERNAME}:${EXTS_PASSWORD}"
    FULL_DB_URL="${HTTP}://${EXTS_URL}:${EXTS_PORT}"

    SCRIPT_payload="$1"
    SCRIPT_debug="$2"
    SCRIPT_DATA_MODE="$3"

    Print_Output(){
        #$1 = print to syslog, $2 = message to print, $3 = log level
        if [ "$1" = "true" ]; then
            logger -t "$SCRIPT_NAME" "$2"
            printf "\\e[1m$3%s: $2\\e[0m\\n\\n" "$SCRIPT_NAME"
        else
            printf "\\e[1m$3%s: $2\\e[0m\\n\\n" "$SCRIPT_NAME"
        fi
    }

    check_influx_response()
    {

        response_header=$(echo "${1}" | head -1)
        response_header_int=$(echo "${1}" | head -1 | awk '{print $2}' )
        response_header_msg=$(echo "${1}" | head -1 | awk '{print $3}')

        case "$response_header_int" in
			100) # extstats: HTTP/1.1 204 No Content
				#Print_Output "true" "100 extStats:fileexport True [${2}]" "$WARN"
				break
			;;
			204) # extstats: HTTP/1.1 204 No Content
				#Print_Output "true" "204 extStats:export True [${2}]" "$WARN"
				#break
			;;
			400) # HTTP/1.1 400 Bad Request
				Print_Output "true" "extStats:export Error ${response_header} - maybe there is something wrong with the query" "$WARN"
				Print_Output "true" "query [${2}]" "$WARN"
				break
			;;
			401) #HTTP/1.1 401 Unauthorized
				Print_Output "true" "extStats:export Error [${curl_response}] - wrong username/password?" "$WARN"
				Print_Output "true" "extStats:on query ${2}" "$WARN"
				Print_Output "true" "extStats:url ${FULL_DB_URL}/write?db=${EXTS_DATABASE}&u=${EXTS_USERNAME}&p=${EXTS_PASSWORD}" "$WARN"
				break
			;;
			404) #HTTP/1.1 404 Not Found
				Print_Output "true" "extStats:export Error [${curl_response}] - wrong database?" "$WARN"
				Print_Output "true" "extStats:on query ${2}" "$WARN"
				Print_Output "true" "extStats:url ${FULL_DB_URL}/write?db=${EXTS_DATABASE}&u=${EXTS_USERNAME}&p=${EXTS_PASSWORD}" "$WARN"
				break
			;;
			*)
				#printf "\\nPlease choose a valid option\\n\\n"
			;;
        esac
    }

    if [ "$SCRIPT_DATA_MODE" = "file" ]; 
    then
        #if file is give
        if [ -r "$SCRIPT_payload" ]; then
            curl_response=$(curl -is ${CURL_OPTIONS} -XPOST "${FULL_DB_URL}/write?db=${EXTS_DATABASE}&u=${EXTS_USERNAME}&p=${EXTS_PASSWORD}" --data-binary "@${SCRIPT_payload}")
        else
            Print_Output "true" "extStats:export error, cant find given file $SCRIPT_payload" "$WARN"
        fi
    elif [ "$SCRIPT_DATA_MODE" = "newDB" ]; then
        curl_response=$(curl -is ${CURL_OPTIONS}  ${FULL_DB_URL}/query ${CURL_USER} --data-urlencode "q=CREATE DATABASE ${SCRIPT_payload}")
    else #normal single datapoint
        curl_response=$(curl -is ${CURL_OPTIONS} -XPOST "${FULL_DB_URL}/write?db=${EXTS_DATABASE}&u=${EXTS_USERNAME}&p=${EXTS_PASSWORD}" --data-binary "${SCRIPT_payload}")
    fi

    #curl -is -XPOST "${FULL_DB_URL}/write?db=extstats_test2020&u=${EXTS_USERNAME}&p=${EXTS_PASSWORD}" --data-binary "${SCRIPT_payload}"
    #curl_response=$(curl -is -XPOST "${FULL_DB_URL}/write?db=${EXTS_DATABASE}&u=${EXTS_USERNAME}&p=${EXTS_PASSWORD}" --data-binary "${SCRIPT_payload}")
    check_influx_response "${curl_response}" "${SCRIPT_payload}"

#cat $SCRIPT_payload

#curl
# -I, --head
# (HTTP FTP FILE) Fetch the headers only! HTTP-servers feature the command HEAD which this uses to get nothing but the header of a document. When used on an FTP or FILE file, curl displays the file size and last modification time only. 

# -i, --include
# Include the HTTP response headers in the output. The HTTP response headers can include things like server name, cookies, date of the document, HTTP version and more... 

# -k, --insecure
# (TLS) By default, every SSL connection curl makes is verified to be secure. This option allows curl to proceed and operate even for server connections otherwise considered insecure.
# The server connection is verified by making sure the server's certificate contains the right name and verifies successfully using the cert store. 

# -S, --show-error
# When used with -s, --silent, it makes curl show an error message if it fails. 

# -s, --silent
# Silent or quiet mode. Don't show progress meter or error messages. Makes Curl mute. It will still output the data you ask for, potentially even to the terminal/stdout unless you redirect it.
# Use -S, --show-error in addition to this option to disable progress meter but still show error messages. 