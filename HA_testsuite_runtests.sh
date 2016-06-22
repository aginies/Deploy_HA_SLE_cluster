#!/bin/sh
#########################################################
#
#
#########################################################
## TEST HA
#########################################################
# all is done from the Host

# execute a command on a NODE
exec_on_node() {
    # first arg is NODE name, second arg is command
    NODE="$1"
    CMD="$2"
    # avoid: No pseudo-tty detected! Use -t option to ssh if calling remotely
    echo "${NODE}: ssh -t -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no ${NODE} ${CMD}"
    ssh -t -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no ${NODE} ${CMD}
}

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
    pssh -h hanodes -P "systemctl enable sbd"
}


# Init the cluster on node HA1
init_ha_cluster() {
    echo "############ START init the cluster"
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
    exec_on_node ha1 "ha-cluster-init -s /dev/vdb -y"
}

# ADD all other NODES (from HOST)
add_remove_node_test() {
    echo "############ START other HA nodes join the cluster"
    exec_on_node ha2 "ha-cluster-join -y -c 192.168.12.101"
    exec_on_node ha3 "ha-cluster-join -y -c 192.168.12.101"
    exec_on_node ha4 "ha-cluster-join -y -c 192.168.12.101"
    echo "############ START remove node HA3 from cluster"
    exec_on_node ha1 "ha-cluster-remove -c 192.168.12.103"
    crm_status
    echo "############ START re-add node HA3 to cluster"
    exec_on_node ha3 "ha-cluster-join -y -c 192.168.12.101"
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
#firefox https://192.168.12.101:7630

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

vip_test() {
    # ADD VIP on ha2 (will be used later for HAproxy)
    exec_on_node ha1 "crm configure primitive vip1 ocf:heartbeat:IPaddr2 params ip=192.168.12.222"
    exec_on_node ha1 "crm configure primitive vip2 ocf:heartbeat:IPaddr2 params ip=192.168.12.223"
    exec_on_node ha1 "crm configure location loc-ha2 { vip1 vip2 } inf: ha2"
    crm_status
    exec_on_node ha1 "crm resource list"
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

proxy_test() {
# HA proxy conf, load balancer HA1/HA2, web server: HA3/HA4
# command from HOST
    ssh ha1 zypper in -y haproxy
    ssh ha2 zypper in -y haproxy
    ssh ha3 zypper in -y apache2
    ssh ha4 zypper in -y apache2
    ssh ha1 systemctl disable haproxy
    ssh ha2 systemctl disable haproxy
    
# Configure haproxy.cfg on HA1 or HA2
# change /etc/haproxy/haproxy.cfg
perl -pi -e "s/bind.*/bind 192.168.12.222:80/" /etc/haproxy/haproxy.cfg
cat >> /etc/haproxy/haproxy.cfg <EOF
server ha3 192.168.1.103:80 cookie A check
server ha4 192.168.1.104:80 cookie B check
EOF

# Check the configuration is valid
haproxy -f /etc/haproxy/haproxy.cfg -c
# Add this configuration to corosync2 and deploy on all nodes
perl -pi -e "s|}|\tinclude /etc/haproxy/haproxy.cfg;\n}|" /etc/csync2/csync2.cfg
csync2 -f /etc/haproxy/haproxy.cfg
csync2 -xv

crm configure cib new haproxy-config
crm cib use haproxy-config
crm configure primitive haproxy systemd:haproxy op monitor interval=10s
crm configure primitive vip-www1 IPaddr2 params ip=192.168.1.101
crm configure primitive vip-www2 IPaddr2 params ip=192.168.1.102
crm configure group g-haproxy vip-www1 vip-www2 haproxy
}

##########################
##########################
### MAIN
##########################
##########################


case "$1" in
    sbd)
    create_sbd_dev
	enable_sbd_all_nodes
        ;;
    init)
	init_ha_cluster
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
    vip)
	vip_test
	;;
    crmhist)
	crm_history
	;;
    all)
	create_sbd_dev
	enable_sbd_all_nodes
	init_ha_cluster
	add_remove_node_test
	sbd_test
	list_ra_stonith
	coroysnc2_test
	ocf_check
	maintenance_mode_check
	#vip_test
	health_test
	crm_history
	;;
    *)
        echo "
     Usage: $0 {sbd|init|addremove|sbdtest|somechecks|maintenance|vip|crmhist|all}

 sbd
    Create an SBD device
    Enable SBD on all HA nodes

 init
    Init the cluster on node HA1

 addremove
    ADD all other NODES
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

 vip
    ADD VIP on ha2

 crmhist
    Check crm history

 all 
    run all in this order
"
        exit 1
esac


