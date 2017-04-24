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
    echo $I "############ START failover_ip_cib" $O
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
    echo $I "############ START check_failoverip_resource" $O
    exec_on_node ${NODENAME}1 "crm_resource -r ${RESOURCEID} -W"
    exec_on_node ${NODENAME}1 "crm status"
}

standby_node_running_resource() {
    echo $I "############ START standby_node_running_resource" $O
    exec_on_node ${NODENAME}1 "crm_resource -r ${RESOURCEID} -W" > /tmp/result
    # use one line, and remove \r
    RNODE=`cat /tmp/result | tail -2 | cut -d ':' -f 2 | sed -e "s/\r//" | head -1`
    echo $I "- Standby ${RNODE} from node ${NODENAME}1" $O
    exec_on_node ${NODENAME}1 "crm node standby ${RNODE}"
}

put_node_maintenance() {
    echo $I "############ START put_node_maintenance" $O
    exec_on_node ${NODENAME}1 "crm node maintenance ${NODENAME}2"
}

restore_node_in_maintenance() {
    echo $I "############ START restore_node_in_maintenance" $O
    exec_on_node ${NODENAME}1 "crm node ready ${NODENAME}2"
}

online_rnode() {
    echo $I "############ START online_rnode" $O
    RNODE=`cat /tmp/result | tail -2 | cut -d ':' -f 2 | sed -e "s/\r//" | head -1`
    echo $I "- Restore online ${RNODE}" $O
    exec_on_node ${NODENAME}1 "crm node online ${RNODE}"
}

delete_cib_resource() {
    echo $I "############ START delete_cib_resource" $O
    exec_on_node ${NODENAME}1 "crm cib list | grep ${CIBNAME}"
    if [ $? -eq 0 ]; then
	echo $W "- Deleting cib and resource ${RESOURCEID}" $O
	exec_on_node ${NODENAME}1 "crm<<EOF
resource stop ${RESOURCEID}
EOF"
	echo $W "- Wait stop/clear/delete resource (10s)" $O
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
	echo $F "- cib ${CIBNAME} doesnt exist " $O
    fi
    echo $I "- Show status" $O
    exec_on_node ${NODENAME}1 "crm status"
}

ping_virtual_ip() {
    echo $I "############ START ping_virtual_ip" $O
    echo $I "- Flush ARP table for ${NETWORK}.${IPEND}" $O
    ip -s -s neigh flush ${NETWORK}.${IPEND}
    ping -c 2 ${NETWORK}.${IPEND}
    if [ $? -eq 0 ]; then
	echo $S "- ping ${NETWORK}.${IPEND} OK" $O
    else
	echo $F "- ! ping ${NETWORK}.${IPEND} FAILED" $O
    fi
}

##########################
##########################
### MAIN
##########################
##########################

echo $I "############ FAILOVER IP SCENARIO #############"
echo
echo " One node will be in maintenance (${NODENAME}2)"
echo " The one running the resource will be put in standby mode"
echo " The IP address must be reachable: ${NETWORK}.${IPEND}"
echo " (if manual debug, please check arp table!)"
echo
echo " press [ENTER] twice OR Ctrl+C to abort" $O
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
