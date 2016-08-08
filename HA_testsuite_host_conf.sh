#!/bin/sh
#########################################################
#
#
#########################################################
## HOST CONFIGURATION
#########################################################

# ie: ISO as source of RPM:
#zypper addrepo "iso:/?iso=SLE-12-SP2-Server-DVD-x86_64-Buildxxxx-Media1.iso&url=nfs://10.0.1.99/volume1/install/ISO/SP2devel/" ISOSLE
#zypper addrepo "iso:/?iso=SLE-12-SP2-HA-DVD-x86_64-Buildxxxx-Media1.iso&url=nfs://10.0.1.99/volume1/install/ISO/SP2devel/" ISOHA

if [ -f `pwd`/functions ] ; then
    . `pwd`/functions
else
    echo "! need functions in current path; Exiting"; exit 1
fi
check_load_config_file


# Install all needed Hypervisors tools
install_virtualization_stack() {
    echo "############ START install_virtualization_stack #############"
    echo "- patterns-sles-${HYPERVISOR}_server patterns-sles-${HYPERVISOR}_tools and restart libvirtd"
    zypper in -y patterns-sles-${HYPERVISOR}_server
    zypper in -y patterns-sles-${HYPERVISOR}_tools
    echo "- Restart libvirtd"
    systemctl restart libvirtd
}

# ssh root key on host
# should be without password to speed up command on HA NODE
ssh_root_key() {
    echo "############ START ssh_root_key #############"
    echo "- Generate ~/.ssh/${IDRSAHA} without password"
    ssh-keygen -t rsa -f ~/.ssh/${IDRSAHA} -N ""
    echo "- Create /root/.ssh/config for HA nodes access"
    cat > /root/.ssh/config<<EOF
host ha1 ha2 ha3 ha4
IdentityFile /root/.ssh/${IDRSAHA}
EOF
}

# Connect as root in VMguest without Password, copy root host key
# pssh will be used
# Command from Host
prepare_remote_pssh() {
    echo "############ START prepare_remote_pssh #############"
    echo "- Install pssh and create /etc/hanodes"
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
${NETWORK}.101  ha1.testing.com ha1
${NETWORK}.102  ha2.testing.com ha2
${NETWORK}.103  ha3.testing.com ha3
${NETWORK}.104  ha4.testing.com ha4
EOF
    else
        echo "- /etc/hosts already ok"
    fi
}

# Define HAnet private HA network (NAT)
# NETWORK will be ${NETWORK}.0/24 gw/dns ${NETWORK}.1
prepare_virtual_HAnetwork() {
    echo "############ START prepare_virtual_HAnetwork #############"
    echo "- Prepare virtual HAnetwork (/etc/libvirt/qemu/networks/${NETWORKNAME}.xml)"
    cat > /etc/libvirt/qemu/networks/${NETWORKNAME}.xml << EOF
<network>
  <name>${NETWORKNAME}</name>
  <uuid>851e50f1-db72-475a-895f-28304baf8e8c</uuid>
  <forward mode='nat'/>
  <bridge name='virbr1' stp='on' delay='0'/>
  <mac address='52:54:00:89:a0:b9'/>
  <domain name='${NETWORKNAME}'/>
  <ip address='${NETWORK}.1' netmask='255.255.255.0'>
    <dhcp>
      <range start='${NETWORK}.128' end='${NETWORK}.254'/>
      <host mac="52:54:00:c7:92:da" name="ha1.testing.com" ip="${NETWORK}.101" />
      <host mac="52:54:00:c7:92:db" name="ha2.testing.com" ip="${NETWORK}.102" />
      <host mac="52:54:00:c7:92:dc" name="ha3.testing.com" ip="${NETWORK}.103" />
      <host mac="52:54:00:c7:92:dd" name="ha4.testing.com" ip="${NETWORK}.104" />
    </dhcp>
  </ip>
</network>
EOF

    echo "- Start ${NETWORKNAME}"
    systemctl restart libvirtd
    virsh net-autostart ${NETWORKNAME}
    virsh net-start ${NETWORKNAME}
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
    mkdir ${STORAGEP}/${SBDNAME}
    virsh pool-define-as --name ${SBDNAME} --type dir --target ${STORAGEP}/${SBDNAME}
    echo "- Start and Autostart the pool"
    virsh pool-start ${SBDNAME}
    virsh pool-autostart ${SBDNAME}

# Create the VOLUME SBD.img
    echo "- Create ${SBDNAME}.img"
    virsh vol-create-as --pool ${SBDNAME} --name ${SBDNAME}.img --format raw --allocation 10M --capacity 10M
}

# Create a RAW file which contains auto install file for deployment
prepare_auto_deploy_image() {
    echo "############ START prepare_auto_deploy_image #############"
    echo "- Prepare the autoyast image for VM guest installation (havm_xml.raw)"
    WDIR=`pwd`
    WDIR2="/tmp/tmp_ha"
    WDIRMOUNT="/mnt/tmp_ha"
    mkdir ${WDIRMOUNT} ${WDIR2}
    cd ${STORAGEP}
    cp -avf ${WDIR}/havm*.xml ${WDIR2}
    sleep 1
    perl -pi -e "s/NETWORK/${NETWORK}/g" ${WDIR2}/havm.xml
    perl -pi -e "s/NETWORK/${NETWORK}/g" ${WDIR2}/havm_mini.xml
    qemu-img create havm_xml.raw -f raw 2M
    mkfs.ext3 havm_xml.raw
    mount havm_xml.raw ${WDIRMOUNT}
    cp -v ${WDIR2}/havm.xml ${WDIRMOUNT}
    cp -v ${WDIR2}/havm_mini.xml ${WDIRMOUNT}
    umount ${WDIRMOUNT}
    rm -rf ${WDIRMOUNT} ${WDIR2}
}

check_host_config() {
    echo "############ START check_host_config #############"
    echo "- Show net-list"
    virsh net-list
    echo "- Display pool available"
    virsh pool-list
    echo "- List volume available in ${SBDNAME}"
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

ssh_root_key
install_virtualization_stack
prepare_remote_pssh
prepare_etc_hosts
prepare_virtual_HAnetwork
prepare_SBD_pool
prepare_auto_deploy_image
check_host_config
