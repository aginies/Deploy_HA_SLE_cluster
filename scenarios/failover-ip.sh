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
    echo "! functions file needed! ; Exiting"
    exit 1
fi
check_load_config_file other

# IP address of the vip
IPEND="222"
CIBNAME="failoverip-cib"
RESOURCEID="failover-ip"

failover_ip_cib() {
    echo "############ START failover_ip_cib"
    exec_on_node ${NODENAME}1 "crm<<EOF
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
    exec_on_node ${NODENAME}1 "crm_resource -r ${RESOURCEID} -W"
    exec_on_node ${NODENAME}1 "crm status"
}

standby_node_running_resource() {
    echo "############ START standby_node_running_resource"
    exec_on_node ${NODENAME}1 "crm_resource -r ${RESOURCEID} -W" > /tmp/result
    # use one line, and remove \r
    RNODE=`cat /tmp/result | tail -1 | cut -d ':' -f 2 | sed -e "s/\r//"`
    echo "- Standby ${RNODE} from node ${NODENAME}1"
    exec_on_node ${NODENAME}1 "crm node standby ${RNODE}"
}

put_node_maintenance() {
    echo "############ START put_node_maintenance"
    exec_on_node ${NODENAME}1 "crm node maintenance ${NODENAME}2"
}

restore_node_in_maintenance() {
    echo "############ START restore_node_in_maintenance"
    exec_on_node ${NODENAME}1 "crm node ready ${NODENAME}2"
}

online_rnode() {
    echo "############ START online_rnode"
    RNODE=`cat /tmp/result | tail -1 | cut -d ':' -f 2 | sed -e "s/\r//"`
    echo "- Restore online ${RNODE}"
    exec_on_node ${NODENAME}1 "crm node online ${RNODE}"
}

delete_cib_resource() {
    echo "############ START delete_cib_resource"
    exec_on_node ${NODENAME}1 "crm cib list | grep ${CIBNAME}"
    if [ $? -eq 0 ]; then
	echo "- Deleting cib and resource ${RESOURCEID}"
	exec_on_node ${NODENAME}1 "crm<<EOF
resource stop ${RESOURCEID}
EOF"
echo "- Wait stop/clear/delete resource (10s)"
       sleep 10
       exec_on_node ${NODENAME}1 "crm<<EOF
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
    exec_on_node ${NODENAME}1 "crm status"
}

ping_virtual_ip() {
    echo "############ START ping_virtual_ip"
    echo "- Flush ARP table for ${NETWORK}.${IPEND}"
    ip -s -s neigh flush ${NETWORK}.${IPEND}
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

echo "############ FAILOVER IP SCENARIO #############"
echo
echo " One node will be in maintenance (${NODENAME}2)"
echo " The one running the resource will be put in standby mode"
echo " The IP address must be reachable: ${NETWORK}.${IPEND}"
echo " (if manual debug, please check arp table!)"
echo
echo " press [ENTER] twice OR Ctrl+C to abort"
read
read


delete_cib_resource
failover_ip_cib
check_failoverip_resource
ping_virtual_ip
standby_node_running_resource
put_node_maintenance
check_failoverip_resource
ping_virtual_ip
online_rnode
restore_node_in_maintenance
delete_cib_resource ${NODEA} ${CIBNAME} ${RESOURCEID}
