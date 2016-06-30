#!/bin/sh
#########################################################
#
#
#########################################################
## failover IP
#########################################################

if [ -f ../functions ] ; then
    . ../functions
else
    echo "! need functions in current path; Exiting"
    exit 1
fi
check_load_config_file other

# IP address of the vip
IPEND="222"
CIBNAME="failoverip-cib"

failover_ip_cib() {
    echo "############ START failover_ip_cib"
    exec_on_node ha1 "crm<<EOF
cib new ${CIBNAME}
configure primitive failover-ip ocf:heartbeat:IPaddr2 params ip=${NETWORK}.${IPEND} cidr_netmask=32 op monitor interval=1s
verify
end
cib use live
cib commit ${CIBNAME}
exit
EOF"
}

test_failoverip() {
    echo "############ START test_failoverip"
    exec_on_node ha1 "crm status"
}

delete_cib_resource() {
    echo "############ START delete_cib_resource"
    exec_on_node ha1 "crm cib list | grep ${CIBNAME}"
    if [ $? -eq 0 ]; then
	echo "- Deleting cib and resource ${CIBNAME}"
	exec_on_node ha1 "crm<<EOF
resource stop failover-ip
EOF"
echo "- Wait stop/clear/delete resource (10s)"
       sleep 10
       exec_on_node ha1 "crm<<EOF
resource clear failover-ip
configure delete failover-ip
cib delete failoverip-cib
verify
configure commit
exit
EOF"
    else
	echo "- cib ${CIBNAME} doesnt exist "
    fi
    echo "- Show status"
    exec_on_node ha1 "crm status"
}

ping_virtual_ip() {
    echo "############ START ping_virtual_ip"
    ping -c 2 ${NETWORK}.${IPEND}
    if [ $? -eq 0 ]; then
	echo "- ping ${NETWORK}.${IPEND} OK"
    else
	echo "- ! ping ${NETWORK}.${IPEND} FAILED"
    fi
}

##########################
##########################
### MAIN
##########################
##########################

delete_cib_resource
failover_ip_cib
ping_virtual_ip
test_failoverip
delete_cib_resource
