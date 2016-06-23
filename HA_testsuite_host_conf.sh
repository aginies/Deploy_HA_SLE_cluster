#!/bin/sh
#########################################################
#
#
#########################################################
## HOST CONFIGURATION
#########################################################


# Install all needed Hypervisors tools
install_virtualization_stack() {
    echo "############ START install_virtualization_stack #############"
    echo "- patterns-sles-kvm_server patterns-sles-kvm_tools and restart libvirtd"
    zypper in -y patterns-sles-kvm_server
    zypper in -y patterns-sles-kvm_tools
    systemctl restart libvirtd
}

# ssh root key on host
# should be without password to speed up command on HA NODE
ssh_root_key() {
    echo "############ START ssh_root_key #############"
    ssh-keygen -t rsa -f ~/.ssh/${IDRSAHA} -N ""
    cat > .ssh/config<<EOF
host ha1 ha2 ha3 ha4
IdentityFile /root/.ssh/${IDRSAHA}
EOF
}

# Connect as root in VMguest without Password, copy root host key
# pssh will be used
# Command from Host
prepare_remote_pssh() {
    echo "############ START prepare_remote_pssh #############"
    echo "- pssh and network /etc/hanodes"
    zypper in -y pssh
    cat > /etc/hanodes<<EOF
ha1
ha2
ha3
ha4
EOF
}

# ADD node to /etc/hosts (hosts)
prepare_etc_hosts() {
    echo "############ START prepare_etc_hosts #############"
    grep ha1.testing.com /etc/hosts
    if [ $? == "1" ]; then
        echo "- Prepare /etc/hosts (adding HA nodes)"
    cat >> /etc/hosts <<EOF
192.168.12.101  ha1.testing.com ha1
192.168.12.102  ha2.testing.com ha2
192.168.12.103  ha3.testing.com ha3
192.168.12.104  ha4.testing.com ha4
EOF
    else
        echo "- /etc/hosts already ok"
    fi
}

# Define HAnet private HA network (NAT)
# NETWORK will be 192.168.12.0/24 gw/dns 192.168.12.1
prepare_virtual_HAnetwork() {
    echo "############ START prepare_virtual_HAnetwork #############"
    echo "- Prepare virtual HAnetwork"
    cat > /etc/libvirt/qemu/networks/${NETWORK}.xml << EOF
<network>
  <name>${NETWORK}</name>
  <uuid>851e50f1-db72-475a-895f-28304baf8e8c</uuid>
  <forward mode='nat'/>
  <bridge name='virbr1' stp='on' delay='0'/>
  <mac address='52:54:00:89:a0:b9'/>
  <domain name='${NETWORK}'/>
  <ip address='192.168.12.1' netmask='255.255.255.0'>
    <dhcp>
      <range start='192.168.12.128' end='192.168.12.254'/>
      <host mac="52:54:00:c7:92:da" name="ha1.testing.com" ip="192.168.12.101" />
      <host mac="52:54:00:c7:92:db" name="ha2.testing.com" ip="192.168.12.102" />
      <host mac="52:54:00:c7:92:dc" name="ha3.testing.com" ip="192.168.12.103" />
      <host mac="52:54:00:c7:92:dd" name="ha4.testing.com" ip="192.168.12.104" />
    </dhcp>
  </ip>
</network>
EOF

    echo "- Start ${NETWORK}"
    systemctl restart libvirtd
    virsh net-autostart ${NETWORK}
    virsh net-start ${NETWORK}
}

# Create an SBD pool on the host 
prepare_SBD_pool() {
    echo "############ START prepare_SBD_pool"
# Create a pool SBD
    virsh pool-list --all | grep ${SBDNAME} > /dev/null
    if [ $? == "0" ]; then
    	echo "- Destroy current pool ${SBDNAME}"
    	virsh pool-destroy ${SBDNAME}
    	echo "- Undefine current pool ${SBDNAME}"
    	virsh pool-undefine ${SBDNAME}
        rm -vf ${SBDDISK}
    else
        echo "- ${SBDNAME} pool is not present"
    fi
    echo "- Define pool ${SBDNAME}"
    virsh pool-define-as --name ${SBDNAME} --type dir --target ${STORAGEP}/${SBDNAME}
    virsh pool-start ${SBDNAME}
    virsh pool-autostart ${SBDNAME}

# Create the VOLUME SBD.img
    echo "- Create ${SBDNAME}.img"
    virsh vol-create-as --pool ${SBDNAME} --name ${SBDNAME}.img --format raw --allocation 10M --capacity 10M
}

# Create a RAW file which contains auto install file for deployment
prepare_auto_deploy_image() {
    echo "############ START prepare_auto_deploy_image #############"
    echo "- Prepare the autoyast image for VM guest installation"
    WDIR=`pwd`
    WDIRMOUNT="/mnt/tmp_ha"
    cd ${STORAGEP}
    qemu-img create havm_xml.raw -f raw 64K
    mkfs.ext3 havm_xml.raw
    mkdir ${WDIRMOUNT}
    mount havm_xml.raw ${WDIRMOUNT}
    cp -v ${WDIR}/havm.xml ${WDIRMOUNT}
    cp -v ${WDIR}/havm_mini.xml ${WDIRMOUNT}
    umount ${WDIRMOUNT}
    rm -rf ${WDIRMOUNT}
}

check_host_config() {
    echo "############ START check_host_config #############"
    virsh net-list
    virsh pool-list
    virsh vol-list ${SBDNAME}
}

###########################
###########################
#### MAIN
###########################
###########################

echo "############ PREPARE HOST #############"
echo "  !! WARNING !! "
echo "  !! WARNING !! "
echo 
echo "  This will remove any previous Host configuration for HA VM guests and testing"
echo
echo " press [ENTER] twice OR Ctrl+C to abort"
read
read

install_virtualization_stack
prepare_remote_pssh
prepare_etc_hosts
prepare_virtual_HAnetwork
prepare_SBD_pool
prepare_auto_deploy_image
check_host_config
