#!/bin/sh
#########################################################
#
#
#########################################################
## HA SCENARIO
## NFS + DRBD
#########################################################

if [ -f `pwd`/functions ] ; then
    . `pwd`/functions
else
    echo "! need functions in current path; Exiting"
    exit 1
fi

NODEA=ha1
NODEB=ha2
IPA=`host ${NODEA} | awk -F "address " '{print $2}' | head -1`
IPB=`host ${NODEB} | awk -F "address " '{print $2}' | head -1`


install_packages() {
	echo "############ START install_packages"yy
    # ADD VIP on ha2 (will be used later for HAproxy)
    exec_on_node ${NODEA} "zypper -y in drbd-kmp-default nfs-kernel-server"
    exec_on_node ${NODEB} "zypper -y in drbd-kmp-default nfs-kernel-server"
}

pacemaker_configuration() {
	echo "############ START pacemaker_configuration"
    # adjust the global cluster options no-quorum-policy and resource-stickiness
    exec_on_node ${NODEA} "crm configure property no-quorum-policy=\"ignore\""
    exec_on_node ${NODEA} "crm configure rsc_defaults resource-stickiness=\"200\""
}

disable_drbd() {
	echo "############ START disable_drbd"
    exec_on_node ${NODEA} "systemctl disable drbd"
    exec_on_node ${NODEB} "systemctl disable drbd"
}

create_nfs_resource() {
	echo "############ START create_nfs_resource"
    exec_on_node ${NODEA} "cat >/etc/drbd.d/nfs.res<<EOF
resource nfs {
    device /dev/drbd0;
    disk /dev/vdd;
    meta-disk internal;
    on ${NODEA} {
      address ${IPA}:7790;
    }
    on ${NODEB} {
      address ${IPB}:7790;
    }
}
EOF"
}

update_csync2() {
	echo "############ START update_csync2"
	exec_on_node ${NODEA} "perl -pi -e 's|}|\tinclude include /etc/drbd.conf;\n\tinclude /etc/drbd.d;
;\n}|' /etc/csync2/csync2.cfg"
	exec_on_node ${NODEA} "csync2 -f /etc/haproxy/haproxy.cfg"
	exec_on_node ${NODEA} "csync2 -xv"
}

finalize_DRBD_setup() {
	echo "############ START finalize_DRBD_setup"
	exec_on_node ${NODEA} "drbdadm create-md nfs"
	exec_on_node ${NODEB} "drbdadm create-md nfs"
	exec_on_node ${NODEA} "drbdadm up nfs"
	exec_on_node ${NODEB} "drbdadm up nfs"
	exec_on_node ${NODEA} "drbdadm new-current-uuid --zeroout-devices nfs/0"
	exec_on_node ${NODEA} "drbdadm primary nfs"
	exec_on_node ${NODEA} "cat /proc/drbd"
	exec_on_node ${NODEA} "drbdadm -- --overwrite-data-of-peer primary nfs"
}


##########################
##########################
### MAIN
##########################
##########################

install_packages
pacemaker_configuration
disable_drbd
create_nfs_resource
update_csync2
finalize_DRBD_setup
