#!/bin/bash

USAGE="usage: $0 xenserver_ip nova_path glance_path <nova_packager_url>"

if [ $# -ne 3 ]; then
    echo $USAGE;
    exit 1;
fi

XENSERVER_IP="$1"
NOVA="$2"
GLANCE="$3"
DEB_PACKAGER_URL="lp:~rackspace-titan/nova/ubuntu-nova-vpc"
XENSERVER_NAME="xen1"

function create_group {
    rake group:create
    rake group:poll
}

function chef_install {
    # NOTE: we build packages right now because the PPA won't work on
    # Cloud Servers. There are a couple show stoppers:
    #
    # - libvirt 0.8.8 doesn't quite: https://bugs.launchpad.net/bugs/790837
    # - Additionally the init script for nova-compute modprobes 'nbd'
    #
    # Until we fix these issues building packages is required.

    rake nova:build_packages SOURCE_DIR=$NOVA DEB_PACKAGER_URL=$DEB_PACKAGER_URL
    rake nova:build_rpms SOURCE_DIR=$NOVA
    rake glance:build_packages SOURCE_DIR=$GLANCE
    rake chef:push_repos
    rake chef:install
}

function xen_bootstrap {
    rake xen:bootstrap XENSERVER_IP=$XENSERVER_IP SERVER_NAME=$XENSERVER_NAME
}

function chef_install_xenserver {
    rake chef:install SERVER_NAME=$XENSERVER_NAME
    rake chef:poll_clients SERVER_NAME=$XENSERVER_NAME
}

function compute1_bootstrap {
    rake ssh bash <<EOF_BASH
    if ! grep -c "compute1.vpc" /etc/hosts &> /dev/null; then
    echo "172.19.0.101     compute1.vpc compute1" >> /etc/hosts
    fi
EOF_BASH

    rake chef:install SERVER_NAME=compute1

    # NOTE: use full hostname here because nova-agent sets hostname as
    # hostname.domain (will talk to Chris to see if we want to add this as
    # an agent feature)
    rake chef:poll_clients SERVER_NAME=compute1.vpc
}

create_group
chef_install
xen_bootstrap
chef_install_xenserver
compute1_bootstrap
