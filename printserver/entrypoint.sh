#!/bin/bash -ex

fHeader() {
    echo '
#######################################################################
# AirPrint Server Startup
#######################################################################'
    date
    echo -e '\n\n'
}

fAdminUserSetup() {
    if [ -f "${CUPSADMIN_FILE}" ] ; then
        echo "Get Admin username from file"
        CUPSADMIN=$(head -1 "${CUPSADMIN_FILE}")
    else
        echo "ERROR: CUPSADMIN_FILE not found at ${CUPSADMIN_FILE}" >&2
        exit 1
    fi

    if [ -z "${CUPSADMIN}" ]; then
        echo "ERROR: CUPSADMIN is empty in ${CUPSADMIN_FILE}" >&2
        exit 1
    fi

    # Add user to lpadmin if needed
    if [ $(grep -ci "${CUPSADMIN}" /etc/shadow) -eq 0 ]; then
        echo "Add Admin user to lpadmin"
        useradd -r -G lpadmin -M "${CUPSADMIN}"
    fi

    if [ -f "${CUPSPASSWORD_FILE}" ]; then
        echo "Get Admin user password from file"
        CUPSPASSWORD=$(head -1 "${CUPSPASSWORD_FILE}")
    else
        echo "ERROR: CUPSPASSWORD_FILE not found at ${CUPSPASSWORD_FILE}" >&2
        exit 1
    fi

    if [ -z "${CUPSPASSWORD}" ]; then
        echo "ERROR: CUPSPASSWORD is empty in ${CUPSPASSWORD_FILE}" >&2
        exit 1
    fi

    echo "Update Admin User Password"
    echo "${CUPSADMIN}:${CUPSPASSWORD}" | chpasswd
    echo -e '\n\n'
}

(set +x; fHeader ; fAdminUserSetup)

# Flush stale process IDs
rm -f /var/run/avahi-daemon/pid /var/run/cups/cupsd.pid

# Set system timezone via symlink
if [ -n "${TZ}" ] && [ -f "/usr/share/zoneinfo/${TZ}" ]; then
    ln -fs "/usr/share/zoneinfo/${TZ}" /etc/localtime
fi

# Restore default cups config if empty
if [ ! -f /etc/cups/cupsd.conf ]; then
    cp -rpn /etc/cups-bak/* /etc/cups/
fi

# Launch background discovery daemon
/usr/sbin/avahi-daemon &

# Launch foreground printer scheduler daemon (Blocks container execution loop)
exec /usr/sbin/cupsd -f



### End of File
