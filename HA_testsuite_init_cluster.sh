#!/bin/sh
#########################################################
#
#
#########################################################
## INIT HA / SOME CHECKS
#########################################################
# all is done from the Host


if [ -f `pwd`/functions ] ; then
    . `pwd`/functions
else
    echo "! need functions in current path; Exiting"; exit 1
fi
check_load_config_file


# ON ${NODENAME}1 NODE
# Create an SBD device
create_sbd_dev() {
    echo "############ START create SBD device"
    exec_on_node ${NODENAME}1 "modprobe softdog"
    exec_on_node ${NODENAME}1 "echo softdog > /etc/modules-load.d/watchdog.conf"
    exec_on_node ${NODENAME}2 "echo softdog > /etc/modules-load.d/watchdog.conf"
    exec_on_node ${NODENAME}3 "echo softdog > /etc/modules-load.d/watchdog.conf"
    exec_on_node ${NODENAME}1 "sbd -d /dev/vdb create"
    exec_on_node ${NODENAME}1 "sbd -d /dev/vdb dump"
}

# Enable SBD on all HA nodes
enable_sbd_all_nodes() {
    echo "############ START enable SBD on all HA nodes"
    exec_pssh "systemctl enable sbd"
}

fix_hostname() {
    echo "############ START fix_hostname"
    exec_pssh "hostname > /etc/hostname"
}


# Check cluster Active
check_cluster_status() {
    echo "############ START check_cluster_status"
    if [ "$1" != "force" ]; then
	exec_on_node ${NODENAME}1 "systemctl -q is-active corosync.service" IGNORE
	if [ "$?" -ne "0" ]; then
            echo
            echo "! Cluster is active, need to stop it and reboot !"
            echo " This can not been done automatically"
            echo
            echo "- Login on each node and disable pacemaker and corosync service"
            echo "- Reboot all nodes"
            echo
            echo "IE: on all nodes ${NODENAME}1 ${NODENAME}2 ${NODENAME}3, do:"
            echo "systemctl disable pacemaker"
            echo "systemctl disable corosync"
            echo "reboot"
            echo
            echo "- Then relaunch this script"
            echo "- or use the [force] option to bypass this check"
            exit 1
	fi
    else
	echo "- Bypassing cluster check (corosync is running)"
    fi
}

# Init the cluster on node ${NODENAME}1
init_ha_cluster() {
    echo "############ START init the cluster"
    echo "- run ha-cluster-init on node ${DISTRO}${NODENAME}1"
    exec_on_node ${NODENAME}1 "ha-cluster-init -s /dev/vdb -y"
}

copy_ssh_key_on_nodes() {
    echo "############ START copy_ssh_key_on_nodes"
    echo "- Copy ssh root key from node ${NODENAME}1 to all nodes"
    scp -o StrictHostKeyChecking=no root@${NODENAME}1:~/.ssh/id_rsa.pub /tmp/
    scp -o StrictHostKeyChecking=no root@${NODENAME}1:~/.ssh/id_rsa /tmp/
    scp_on_node "/tmp/id_rsa*" "${NODENAME}2:/root/.ssh/"
    scp_on_node "/tmp/id_rsa*" "${NODENAME}3:/root/.ssh/"
    rm -vf /tmp/id_rsa*
    exec_on_node ${NODENAME}2 "grep 'Cluster Internal' /root/.ssh/authorized_keys || cat /root/.ssh/id_rsa.pub >> /root/.ssh/authorized_keys"
    exec_on_node ${NODENAME}3 "grep 'Cluster Internal' /root/.ssh/authorized_keys || cat /root/.ssh/id_rsa.pub >> /root/.ssh/authorized_keys"
}

# ADD all other NODES (from HOST)
add_remove_node_test() {
    echo "############ START other HA nodes join the cluster"
    echo "- Add Node ${NODENAME}2 ${NODENAME}3 to cluster"
    exec_on_node ${NODENAME}2 "ha-cluster-join -y -c ${NETWORK}.101"
    exec_on_node ${NODENAME}3 "ha-cluster-join -y -c ${NETWORK}.101"
    coroysnc2_test
    echo "############ START remove node ${DISTRO}${NODENAME}3 from cluster"
    echo "- Remove ${NODENAME}3 from cluster (from node ${NODENAME}1)"
    exec_on_node ${NODENAME}1 "ha-cluster-remove -c ${NODENAME}3"
    crm_status
    echo "############ START re-add node ${DISTRO}${NODENAME}3 to cluster"
    echo "- Add ${NODENAME}3 back to cluster"
    exec_on_node ${NODENAME}3 "ha-cluster-join -y -c ${NETWORK}.101"
    crm_status
}

# Test if SBD is usable (from an HA node)
sbd_test() {
    echo "############ START test SBD on ${NODENAME}1 (from ${NODENAME}2), reset ${NODENAME}3"
    echo "- Send a test message from ${NODENAME}2 to ${NODENAME}1"
    exec_on_node ${NODENAME}2 "sbd -d /dev/vdb message ${DISTRO}${NODENAME}1 test"
    exec_on_node ${NODENAME}1 "journalctl -u sbd --lines 10"
    echo "- Reset node ${NODENAME}3 from node ${NODENAME}1"
    exec_on_node ${NODENAME}1 "sbd -d /dev/vdb message ${DISTRO}${NODENAME}3 reset"
    echo "- Waiting node back (30s) ...."
    sleep 30
}

# list stonith ra available
list_ra_stonith() {
    echo "############ START list stonith RA available"
    exec_on_node ${NODENAME}1 "crm ra list stonith"
}

# Test HAWK2
# HAWK2 i sonly available on node ${NODENAME}1
#firefox https://${NETWORK}.101:7630

# CRMshell test (from any nodes)
crm_status() {
    echo "############ START crm status"
    exec_on_node ${NODENAME}2 "crm status"
}

# Check corosync2 sync (from any node)
coroysnc2_test() {
    echo "############ START corosync2 test"
    exec_on_node ${NODENAME}2 "csync2 -xv"
}

# OCF check (from any node)
ocf_check() {
    echo "############ START OCF check"
    exec_on_node ${NODENAME}2 "OCF_ROOT=/usr/lib/ocf /usr/lib/ocf/resource.d/heartbeat/IPaddr meta-data"
}

# Check maintenance mode works (from any node)
maintenance_mode_check() {
    echo "############ START try Maintenance on node ${NODENAME}1"
    echo "- Switch ${NODENAME}1 in maintenance mode"
    exec_on_node ${NODENAME}2 "crm node maintenance ${DISTRO}${NODENAME}1"
    crm_status
    echo "- Switch ${NODENAME}1 in ready mode"
    exec_on_node ${NODENAME}2 "crm node ready ${DISTRO}${NODENAME}1"
    crm_status
}

health_test() {
# Check health
    echo "############ START Check health"
    exec_on_node ${NODENAME}2 "crm script describe health"
    exec_on_node ${NODENAME}2 "crm script run health"
}


# Check crm history
crm_history() {
    echo "############ START crm history"
    exec_on_node ${NODENAME}2 "crm history info"
}

##########################
##########################
### MAIN
##########################
##########################


case "$1" in
    status)
	check_cluster_status $2
	;;
    hostname)
	fix_hostname
	;;
    sbd)
	create_sbd_dev
	enable_sbd_all_nodes
        ;;
    init)
	init_ha_cluster
	;;
    sshkeynode)
	copy_ssh_key_on_nodes
	;;
    addremove)
	add_remove_node_test
	;;
    sbdtest)
	sbd_test
	;;
    somechecks)
	list_ra_stonith
	ocf_check
	health_test
	coroysnc2_test
	;;
    maintenance)
	maintenance_mode_check
	;;
    crmhist)
	crm_history
	;;
    all)
    check_cluster_status $2
	fix_hostname
	create_sbd_dev
	enable_sbd_all_nodes
	init_ha_cluster
	copy_ssh_key_on_nodes
	add_remove_node_test
	sbd_test
	list_ra_stonith
	coroysnc2_test
	ocf_check
	maintenance_mode_check
	health_test
	crm_history
	;;
    *)
        echo "
     Usage: $0 {status|hostname|sbd|init|sshkeynode|addremove|sbdtest|somechecks|maintenance|crmhist|all} [force]

 status
    Check that the cluster is not running before config

 hostname
    fix /etc/hostname on all nodes

 sbd
    Create an SBD device
    Enable SBD on all HA nodes

 init
    Init the cluster on node ${NODENAME}1

 sshkeynode
    Copy Cluster Internal key (from ${NODENAME}1) to all other HA nodes

 addremove
    ADD all other NODES (you need to enter root password for all nodes)
    Remove node ${NODENAME}3
    Re-add node ${NODENAME}3

 sbdtest
    Test if SBD is usable
    Kill one node

 somechecks
    List stonith ra available
    OCF check IPaddr
    Check health
    Check corosync2 sync

 maintenance
    Check maintenance mode works

 crmhist
    Check crm history

 all 
    run all in this order

 [force]
    use force option to bypass cluster check (dangerous)
"
        exit 1
esac


