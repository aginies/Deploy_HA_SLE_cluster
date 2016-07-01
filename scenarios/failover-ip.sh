#!/bin/sh
#########################################################
#
#
#########################################################
## Failover IP
#########################################################

if [ -f ../functions ] ; then
    . ../functions
else
    echo "! need functions file ! ; Exiting"
    exit 1
fi
check_load_config_file other

# IP address of the vip
IPEND="222"
CIBNAME="failoverip-cib"
RESOURCEID="failover-ip"

failover_ip_cib() {
    echo "############ START failover_ip_cib"
    exec_on_node ha1 "crm<<EOF
cib new ${CIBNAME}
configure primitive ${RESOURCEID} ocf:heartbeat:IPaddr2 params ip=${NETWORK}.${IPEND} cidr_netmask=32 op monitor interval=1s
verify
end
cib use live
cib commit ${CIBNAME}
exit
EOF"
}

check_failoverip_resource() {
    echo "############ START check_failoverip_resource"
    exec_on_node ha1 "crm_resource -r ${RESOURCEID} -W"
}

delete_cib_resource() {
    echo "############ START delete_cib_resource"
    exec_on_node ha1 "crm cib list | grep ${CIBNAME}"
    if [ $? -eq 0 ]; then
	echo "- Deleting cib and resource ${RESOURCEID}"
	exec_on_node ha1 "crm<<EOF
resource stop ${RESOURCEID}
EOF"
echo "- Wait stop/clear/delete resource (10s)"
       sleep 10
       exec_on_node ha1 "crm<<EOF
resource clear ${RESOURCEID}
configure delete ${RESOURCEID}
cib delete ${CIBNAME}
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
check_failoverip_resource
test_failoverip
delete_cib_resource
