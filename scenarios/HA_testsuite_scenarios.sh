#!/bin/sh
#########################################################
#
#
#########################################################
## HA SCENARIO
#########################################################

if [ -f `pwd`/functions ] ; then
    . `pwd`/functions
else
    echo "! need functions in current path; Exiting"
    exit 1
fi
check_load_config_file

vip_test() {
    # ADD VIP on ${NODENAME}2 (will be used later for HAproxy)
    exec_on_node ${NODENAME}1 "crm configure primitive vip1 ocf:heartbeat:IPaddr2 params ip=${NETWORK}.222"
    exec_on_node ${NODENAME}1 "crm configure primitive vip2 ocf:heartbeat:IPaddr2 params ip=${NETWORK}.223"
    exec_on_node ${NODENAME}1 "crm configure location loc-${NODENAME}2 { vip1 vip2 } inf: ${NODENAME}2"
    crm_status
    exec_on_node ${NODENAME}1 "crm resource list"
}

proxy_test() {
# HA proxy conf, load balancer ${NODENAME}1/${NODENAME}2, web server: ${NODENAME}3/HA4
# command from HOST
    ssh ${NODENAME}1 zypper in -y haproxy
    ssh ${NODENAME}2 zypper in -y haproxy
    ssh ${NODENAME}3 zypper in -y apache2
    ssh ha4 zypper in -y apache2
    ssh ${NODENAME}1 systemctl disable haproxy
    ssh ${NODENAME}2 systemctl disable haproxy

# Configure haproxy.cfg on ${NODENAME}1 or ${NODENAME}2
# change /etc/haproxy/haproxy.cfg
perl -pi -e "s/bind.*/bind ${NETWORK}.222:80/" /etc/haproxy/haproxy.cfg
cat >> /etc/haproxy/haproxy.cfg <EOF
server ${NODENAME}3 ${NETWORK}.103:80 cookie A check
server ha4 ${NETWORK}.104:80 cookie B check
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
crm configure primitive vip-www1 IPaddr2 params ip=${NETWORK}.101
crm configure primitive vip-www2 IPaddr2 params ip=${NETWORK}.102
crm configure group g-haproxy vip-www1 vip-www2 haproxy
}

##########################
##########################
### MAIN
##########################
##########################

