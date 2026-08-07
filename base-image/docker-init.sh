#!/bin/sh
#-------------------------------------------------------------------------------------------------------------
# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT License. See https://go.microsoft.com/fwlink/?linkid=2090316 for license information.
#-------------------------------------------------------------------------------------------------------------
#
# Docker-in-Docker startup script. Starts the Docker (and containerd) daemon
# inside the container, then executes whatever command was passed in.
# Based on the devcontainers/features docker-in-docker init script:
# https://github.com/devcontainers/features/blob/main/src/docker-in-docker/install.sh

set -e

export AZURE_DNS_AUTO_DETECTION=true
export DOCKER_DEFAULT_ADDRESS_POOL=
export DOCKER_DEFAULT_IP6_TABLES=

# Prefer legacy iptables only when the ip_tables kernel module is actually present.
# (Do NOT call `iptables-legacy -L/-nL` to test this — it auto-modprobes ip_tables
# and would defeat hosts/scenarios where the module is intentionally absent
# such as the newer kernels which leaves out ip_tables legacy.)
if type iptables-legacy > /dev/null 2>&1 \
   && { grep -qE '^(ip_tables)\b' /proc/modules \
        || [ -d /sys/module/ip_tables ]; } \
   && update-alternatives --list iptables 2>/dev/null | grep -q '/usr/sbin/iptables-legacy'; then
    update-alternatives --set iptables  /usr/sbin/iptables-legacy || true
    update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy || true
elif type iptables-nft > /dev/null 2>&1 \
     && update-alternatives --list iptables 2>/dev/null | grep -q '/usr/sbin/iptables-nft'; then
    update-alternatives --set iptables  /usr/sbin/iptables-nft  || true
    update-alternatives --set ip6tables /usr/sbin/ip6tables-nft || true
fi

dockerd_start="AZURE_DNS_AUTO_DETECTION=${AZURE_DNS_AUTO_DETECTION} DOCKER_DEFAULT_ADDRESS_POOL=${DOCKER_DEFAULT_ADDRESS_POOL} DOCKER_DEFAULT_IP6_TABLES=${DOCKER_DEFAULT_IP6_TABLES} $(cat << 'INNEREOF'
    # explicitly remove dockerd and containerd PID file to ensure that it can start properly if it was stopped uncleanly
    find /run /var/run -iname 'docker*.pid' -delete || :
    find /run /var/run -iname 'container*.pid' -delete || :

    # -- Start: dind wrapper script --
    # Maintained: https://github.com/moby/moby/blob/master/hack/dind

    export container=docker

    if [ -d /sys/kernel/security ] && ! mountpoint -q /sys/kernel/security; then
        mount -t securityfs none /sys/kernel/security || {
            echo >&2 'Could not mount /sys/kernel/security.'
            echo >&2 'AppArmor detection and --privileged mode might break.'
        }
    fi

    # Mount /tmp (conditionally)
    if ! mountpoint -q /tmp; then
        mount -t tmpfs none /tmp
    fi

    set_cgroup_nesting()
    {
        # cgroup v2: enable nesting
        if [ -f /sys/fs/cgroup/cgroup.controllers ]; then
            # move the processes from the root group to the /init group,
            # otherwise writing subtree_control fails with EBUSY.
            # An error during moving non-existent process (i.e., "cat") is ignored.
            mkdir -p /sys/fs/cgroup/init
            xargs -rn1 < /sys/fs/cgroup/cgroup.procs > /sys/fs/cgroup/init/cgroup.procs || :
            # enable controllers
            sed -e 's/ / +/g' -e 's/^/+/' < /sys/fs/cgroup/cgroup.controllers \
                > /sys/fs/cgroup/cgroup.subtree_control
        fi
    }

    # Set cgroup nesting, retrying if necessary
    retry_cgroup_nesting=0

    until [ "${retry_cgroup_nesting}" -eq "5" ];
    do
        set +e
            set_cgroup_nesting

            if [ $? -ne 0 ]; then
                echo "(*) cgroup v2: Failed to enable nesting, retrying..."
            else
                break
            fi

            retry_cgroup_nesting=`expr $retry_cgroup_nesting + 1`
        set -e
    done

    # -- End: dind wrapper script --

    # Handle DNS
    set +e
        cat /etc/resolv.conf | grep -i 'internal.cloudapp.net' > /dev/null 2>&1
        if [ $? -eq 0 ] && [ "${AZURE_DNS_AUTO_DETECTION}" = "true" ]
        then
            echo "Setting dockerd Azure DNS."
            CUSTOMDNS="--dns 168.63.129.16"
        else
            echo "Not setting dockerd DNS manually."
            CUSTOMDNS=""
        fi
    set -e

    if [ -z "$DOCKER_DEFAULT_ADDRESS_POOL" ]
    then
        DEFAULT_ADDRESS_POOL=""
    else
        DEFAULT_ADDRESS_POOL="--default-address-pool $DOCKER_DEFAULT_ADDRESS_POOL"
    fi

    # Start our own containerd so it picks up /etc/containerd/config.toml
    # (notably the disabled_plugins entry for the erofs snapshotter, see
    # https://github.com/devcontainers/features/issues/1642). dockerd's
    # built-in containerd child uses an auto-generated config that ignores
    # /etc/containerd/config.toml, so we must run containerd ourselves and
    # point dockerd at it via --containerd.
    CONTAINERD_SOCK="/run/containerd/containerd.sock"
    CONTAINERD_BIN=""
    for candidate in /usr/local/bin/containerd /usr/bin/containerd /usr/sbin/containerd; do
        if [ -x "$candidate" ]; then
            CONTAINERD_BIN="$candidate"
            break
        fi
    done
    DOCKERD_CONTAINERD_ARG=""
    if [ -n "$CONTAINERD_BIN" ] && [ -f /etc/containerd/config.toml ]; then
        mkdir -p /run/containerd
        if ! pgrep -x containerd > /dev/null 2>&1; then
            ( "$CONTAINERD_BIN" --config /etc/containerd/config.toml > /tmp/containerd.log 2>&1 ) &
        fi
        # Wait up to ~5s for the socket to appear
        i=0
        while [ $i -lt 50 ] && [ ! -S "$CONTAINERD_SOCK" ]; do
            sleep 0.1
            i=$((i + 1))
        done
        if [ -S "$CONTAINERD_SOCK" ]; then
            DOCKERD_CONTAINERD_ARG="--containerd $CONTAINERD_SOCK"
        else
            echo "(*) containerd socket not ready; letting dockerd spawn its own containerd."
        fi
    fi

    # Start docker/moby engine
    ( dockerd $DOCKERD_CONTAINERD_ARG $CUSTOMDNS $DEFAULT_ADDRESS_POOL $DOCKER_DEFAULT_IP6_TABLES > /tmp/dockerd.log 2>&1 ) &
INNEREOF
)"

sudo_if() {
    COMMAND="$*"

    if [ "$(id -u)" -ne 0 ]; then
        sudo $COMMAND
    else
        $COMMAND
    fi
}

retry_docker_start_count=0
docker_ok="false"

until [ "${docker_ok}" = "true"  ] || [ "${retry_docker_start_count}" -eq "5" ];
do
    # Start using sudo if not invoked as root
    if [ "$(id -u)" -ne 0 ]; then
        sudo /bin/sh -c "${dockerd_start}"
    else
        eval "${dockerd_start}"
    fi

    retry_count=0
    until [ "${docker_ok}" = "true"  ] || [ "${retry_count}" -eq "5" ];
    do
        sleep 1s
        set +e
            docker info > /dev/null 2>&1 && docker_ok="true"
        set -e

        retry_count=`expr $retry_count + 1`
    done

    if [ "${docker_ok}" != "true" ] && [ "${retry_docker_start_count}" != "4" ]; then
        echo "(*) Failed to start docker, retrying..."
        set +e
            sudo_if pkill dockerd
            sudo_if pkill containerd
        set -e
    fi

    retry_docker_start_count=`expr $retry_docker_start_count + 1`
done

# Execute whatever commands were passed in (if any). This allows us
# to set this script to ENTRYPOINT while still executing the default CMD.
exec "$@"
