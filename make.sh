#!/bin/bash

# Prevent script from running as root (root-related actions will prompt for the needed credentials)
[[ $EUID -eq 0 ]] && echo "Do not run with sudo / as root." && exit 1

# Remove corrupt php.ini folder, if existing.
[[ -d './config/php.ini' ]] && rm -rf './config/php.ini'

cp -n config/php.ini.default config/php.ini
cp -n config/config.sh.default config/config.sh
chmod u+x config/config.sh

kill_port_80_usage () {
    echo "Checking if port 80 is free to use"
    if lsof -nP +c 15 | grep LISTEN | grep -s -E "[0-9]:80 "; then
        select yn in "Stop apachectl to use docker" "Leave it (I will fix it myself!)"; do
           case $yn in
                "Stop apachectl so we can use docker" )  
                    echo "Need sudo to STOP apachectl"
                        sudo apachectl stop
                    break
                ;;
                "Leave it (I will fix it myself!)" ) break;;
            esac
        done
    else
        echo "OK"
    fi
}

find_hostfile () {
    #try mac first
    local hostfile = /etc/hosts
    if [ ! -f "$hostfile" ]; then
        read "Found hostfile at ${hostfile}"
        return hostfile;
    fi
    
	#try windows next
    hostfile = /windows/system32/drivers/etc/hosts
    if [ ! -f "$hostfile" ]; then
        read "Found hostfile at ${hostfile}"
        return hostfile
    fi
    read "host file not found!"
    exit 404
}

change_hostfile () {
    local URL=$1
    echo -n "Checking hostfile entry for: ${URL}... "

    local hostfile = find_hostfile

    if grep -q -E "^([0-9]{1,3}[\.]){3}[0-9]{1,3}[[:space:]]+$URL" $hostfile then
        if grep -q -E "^127\.0\.0\.1[[:space:]]+$URL" $hostfile; then
            echo "OK"
        else
            echo "Found this entry:"
            grep -E "^([0-9]{1,3}[\.]){3}[0-9]{1,3}[[:space:]]+$URL" $hostfile;
            select yn in "Change it to use docker" "Leave it"; do
                case $yn in
                    "Change it to use docker" )
                        echo "Need sudo to edit hostfile"
                        check_hosts_newline
                        grep -v -E "^([0-9]{1,3}[\.]){3}[0-9]{1,3}[[:space:]]+$URL" $hostfile | sudo tee $hostfile > /dev/null
                        echo "127.0.0.1 $URL" | sudo tee -a $hostfile > /dev/null
                        break
                    ;;
                    "Leave it" ) break;;
                esac
            done
        fi
    else
        echo "Adding, need sudo"
        check_hosts_newline
        echo "127.0.0.1       $URL" | sudo tee -a $hostfile > /dev/null
    fi
}

function check_hosts_newline () {
    hosts_lastchar=$(tail -c 1 $hostfile)
    [[ "$hosts_lastchar" != "" ]] && echo '' | sudo tee -a $hostfile
}

source ./config/config.sh

change_hostfile ${BASIC_HOST:-basic.wordpress.test}
change_hostfile ${WOOCOMMERCE_HOST:-woocommerce.wordpress.test}
change_hostfile ${MULTISITE_HOST:-multisite.wordpress.test}
change_hostfile test.${MULTISITE_HOST:-multisite.wordpress.test}
change_hostfile translate.${MULTISITE_HOST:-multisite.wordpress.test}
change_hostfile ${STANDALONE_HOST:-standalone.wordpress.test}
change_hostfile ${BASIC_DATABASE_HOST:-basic-database.wordpress.test}
change_hostfile ${WOOCOMMERCE_DATABASE_HOST:-woocommerce-database.wordpress.test}
change_hostfile ${MULTISITE_DATABASE_HOST:-multisite-database.wordpress.test}
change_hostfile ${STANDALONE_DATABASE_HOST:-standalone-database.wordpress.test}

kill_port_80_usage
