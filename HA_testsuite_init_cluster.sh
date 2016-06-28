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
check_config_file


# ON HA1 NODE
# Create an SBD device
create_sbd_dev() {
    echo "############ START create SBD device"
    exec_on_node ha1 "modprobe softdog"
    exec_on_node ha1 "sbd -d /dev/vdb create"
    exec_on_node ha1 "sbd -d /dev/vdb dump"
}

# Enable SBD on all HA nodes
enable_sbd_all_nodes() {
    echo "############ START enable SBD on all HA nodes"
    pssh -h /etc/hanodes -P "systemctl enable sbd"
}

# Check cluster Active
check_cluster_status() {
    echo "############ START check_cluster_status"
    if [ "$1" != "force" ]; then
	exec_on_node ha1 "systemctl -q is-active corosync.service"
	if [ $? -eq 0 ]; then
            echo
            echo "! Cluster is active, need to stop it and reboot !"
            echo " This can not been done automatically"
            echo
            echo "- Login on each node and disable pacemaker and corosync service"
            echo "- Reboot all nodes"
            echo
            echo "IE: on all nodes ha1 ha2 ha3 ha4, do:"
            echo "systemctl disable pacemaker"
            echo "systemctl disable corosync"
            echo "reboot"
            echo
            echo "- Then relaunch this script"
            exit 1
	fi
    else
	echo "- Bypassing cluster check (corosync is running)"
    fi
}

# Init the cluster on node HA1
init_ha_cluster() {
    echo "############ START init the cluster"
    exec_on_node ha1 "ha-cluster-init -s /dev/vdb -y"
}

copy_ssh_key_on_nodes() {
    echo "############ START copy_ssh_key_on_nodes"
    scp -o StrictHostKeyChecking=no root@ha1:~/.ssh/id_rsa.pub /tmp/
    scp -o StrictHostKeyChecking=no root@ha1:~/.ssh/id_rsa /tmp/
    scp_on_node "/tmp/id_rsa*" "ha2:/root/.ssh/"
    scp_on_node "/tmp/id_rsa*" "ha3:/root/.ssh/"
    scp_on_node "/tmp/id_rsa*" "ha4:/root/.ssh/"
    rm -vf /tmp/id_rsa*
    exec_on_node ha2 "grep 'Cluster Internal' /root/.ssh/authorized_keys || cat /tmp/id_rsa.pub >> /root/.ssh/authorized_keys"
    exec_on_node ha3 "grep 'Cluster Internal' /root/.ssh/authorized_keys || cat /tmp/id_rsa.pub >> /root/.ssh/authorized_keys"
    exec_on_node ha4 "grep 'Cluster Internal' /root/.ssh/authorized_keys || cat /tmp/id_rsa.pub >> /root/.ssh/authorized_keys"
}

# ADD all other NODES (from HOST)
add_remove_node_test() {
    echo "############ START other HA nodes join the cluster"
    exec_on_node ha2 "ha-cluster-join -y -c ${NETWORK}.101"
    exec_on_node ha3 "ha-cluster-join -y -c ${NETWORK}.101"
    exec_on_node ha4 "ha-cluster-join -y -c ${NETWORK}.101"
    echo "############ START remove node HA3 from cluster"
    exec_on_node ha1 "ha-cluster-remove -c ${NETWORK}.103"
    crm_status
    echo "############ START re-add node HA3 to cluster"
    exec_on_node ha3 "ha-cluster-join -y -c ${NETWORK}.101"
    crm_status
}

# Test if SBD is usable (from an HA node)
sbd_test() {
    echo "############ START test SBD on HA1 (from HA2), reset HA3"
    exec_on_node ha2 "sbd -d /dev/vdb message ha1 test"
    exec_on_node ha1 "journalctl -u sbd --lines 10"
    exec_on_node ha1 "sbd -d /dev/vdb message ha3 reset"
    echo "- Waiting node back (30s) ...."
    sleep 30
}

# list stonith ra available
list_ra_stonith() {
    echo "############ START list stonith RA available"
    exec_on_node ha1 "crm ra list stonith"
}

# Test HAWK2
# HAWK2 i sonly available on node HA1
#firefox https://${NETWORK}.101:7630

# CRMshell test (from any nodes)
crm_status() {
    echo "############ START crm status"
    exec_on_node ha2 "crm status"
}

# Check corosync2 sync (from any node)
coroysnc2_test() {
    echo "############ START corosync2 test"
    exec_on_node ha2 "csync2 -xv"
}

# OCF check (from any node)
ocf_check() {
    echo "############ START OCF check"
    exec_on_node ha2 "OCF_ROOT=/usr/lib/ocf /usr/lib/ocf/resource.d/heartbeat/IPaddr meta-data"
}

# Check maintenance mode works (from any node)
maintenance_mode_check() {
    echo "############ START try Maintenance on node HA1"
    exec_on_node ha2 "crm node maintenance ha1"
    exec_on_node ha2 "crm status"
    exec_on_node ha2 "crm node ready ha1"
    exec_on_node ha2 "crm status"
}

health_test() {
# Check health
    echo "############ START Check health"
    exec_on_node ha2 "crm script describe health"
    exec_on_node ha2 "crm script run health"
}


# Check crm history
crm_history() {
    echo "############ START crm history"
    exec_on_node ha2 "crm history info"
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
     Usage: $0 {status|sbd|init|sshkeynode|addremove|sbdtest|somechecks|maintenance|crmhist|all} [force]

 status
	Check that the cluster is not running before config

 sbd
    Create an SBD device
    Enable SBD on all HA nodes

 init
    Init the cluster on node HA1

 sshkeynode
    Copy Cluster Internal key (from HA1) to all other HA nodes

 addremove
    ADD all other NODES (you need to enter root password for all nodes)
    Remove node HA3
    Re-add node HA3

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


