#!/bin/sh
#########################################################
#
#
#########################################################
## HA SCENARIO
## NFS + DRBD
#########################################################

if [ -f `pwd`/functions ] ; then
    . `pwd`/functions
else
    echo "! need functions in current path; Exiting"
    exit 1
fi
check_config_file

NODEA="ha1"
NODEB="ha2"
POOLVDD="VDD"
IPA=`grep ${NODEA} /var/lib/libvirt/dnsmasq/${NETWORK}.hostsfile | cut -d , -f 2`
IPB=`grep ${NODEB} /var/lib/libvirt/dnsmasq/${NETWORK}.hostsfile | cut -d , -f 2`

install_packages() {
	echo "############ START install_packages"yy
    # ADD VIP on ha2 (will be used later for HAproxy)
    echo "- Install on ${NODEA} ${NODEB} drbd-kmp-default nfs-kernel-server"
    exec_on_node ${NODEA} "zypper in -y drbd-kmp-default nfs-kernel-server"
    exec_on_node ${NODEB} "zypper in -y drbd-kmp-default nfs-kernel-server"
}

pacemaker_configuration() {
	echo "############ START pacemaker_configuration"
    # adjust the global cluster options no-quorum-policy and resource-stickiness
    exec_on_node ${NODEA} "crm configure property no-quorum-policy=\"ignore\""
    exec_on_node ${NODEA} "crm configure rsc_defaults resource-stickiness=\"200\""
}

disable_drbd() {
	echo "############ START disable_drbd"
    exec_on_node ${NODEA} "systemctl disable drbd"
    exec_on_node ${NODEB} "systemctl disable drbd"
}

create_vol_vdd() {
    echo "############ START create_vol_vdd"
    cat >/etc/libvirt/storage/drbda.xml<<EOF
<disk type='file' device='disk'>
  <driver name='qemu' type='qcow2' cache='none'/>
  <source file='${STORAGEP}/${POOLVDD}/${POOLVDD}A.qcow2'/>
  <target dev='vdd'/>
</disk>
EOF
    cat >/etc/libvirt/storage/drbdb.xml<<EOF
<disk type='file' device='disk'>
  <driver name='qemu' type='qcow2' cache='none'/>
  <source file='${STORAGEP}/${POOLVDD}/${POOLVDD}B.qcow2'/>
  <target dev='vdd'/>
</disk>
EOF
    qemu-img create ${STORAGEP}/${POOLVDD}/${POOLVDD}A.qcow2 1G -f qcow2
    qemu-img create ${STORAGEP}/${POOLVDD}/${POOLVDD}B.qcow2 1G -f qcow2
    virsh vol-create-as --pool ${POOLVDD} --name ${POOLVDD}A.qcow2 --format qcow2 --capacity 1G --allocation 1G
    virsh vol-create-as --pool ${POOLVDD} --name ${POOLVDD}B.qcow2 --format qcow2 --capacity 1G --allocation 1G
    virsh pool-refresh --pool ${POOLVDD}
}


attach_storage_to_node() {
    echo "############ START attach_storage_to_node"
    #virsh attach-device --config ${DISTRO}HA1 /etc/libvirt/storage/drbda.xml
    #virsh attach-device --config ${DISTRO}HA2 /etc/libvirt/storage/drbdb.xml
    echo "- Detach and attach the vdd disk to HA nodes"
    virsh detach-disk ${DISTRO}HA1 vdd
    virsh detach-disk ${DISTRO}HA2 vdd
    virsh attach-disk ${DISTRO}HA1 ${STORAGEP}/${POOLVDD}/${POOLVDD}A.qcow2 vdd --cache none
    virsh attach-disk ${DISTRO}HA2 ${STORAGEP}/${POOLVDD}/${POOLVDD}B.qcow2 vdd --cache none
}

create_nfs_resource() {
	echo "############ START create_nfs_resource"
    cat >/tmp/nfs.res<<EOF
resource nfs {
    device /dev/drbd0;
    disk /dev/vdd;
    meta-disk internal;
    on ${NODEA} {
      address ${IPA}:7790;
    }
    on ${NODEB} {
      address ${IPB}:7790;
    }
}
EOF
    scp_on_node "/tmp/nfs.res" "${NODEA}:/etc/drbd.d/"
}

update_csync2() {
	echo "############ START update_csync2"
    exec_on_node ${NODEA} "grep /etc/drbd.conf /etc/csync2/csync2.cfg"
    if [ $? -eq 1 ]; then
    	exec_on_node ${NODEA} "perl -pi -e 's|}|\tinclude /etc/drbd.conf;\n\tinclude /etc/drbd.d;\n}|' /etc/csync2/csync2.cfg"
    	exec_on_node ${NODEA} "csync2 -f /etc/haproxy/haproxy.cfg"
    	exec_on_node ${NODEA} "csync2 -xv"
    else
        echo "- /etc/csync2/csync2.cfg already contains drbd files to sync"
    fi
}

finalize_DRBD_setup() {
	echo "############ START finalize_DRBD_setup"
    echo "- Initializes the metadata storage"
	exec_on_node ${NODEA} "drbdadm create-md nfs"
	exec_on_node ${NODEB} "drbdadm create-md nfs"
    echo "- Create the /dev/drb"
	exec_on_node ${NODEA} "drbdadm up nfs"
	exec_on_node ${NODEB} "drbdadm up nfs"
    echo "- Create a new UUID to shorten the initial resynchronization of the DRBD resource"
	exec_on_node ${NODEA} "drbdadm new-current-uuid nfs/0"
    echo "- Make ${NODEA} primary"
	exec_on_node ${NODEA} "drbdadm primary nfs"
    echo "- Check the DRBD status"
	exec_on_node ${NODEA} "cat /proc/drbd"
    echo "- Start the resynchronization process on your intended primary node"
	exec_on_node ${NODEA} "drbdadm -- --overwrite-data-of-peer primary nfs"
}


create_lvm_on_drbd() {
    echo "############ START create_lvm_on_drbd"
    echo "- adjust /etc/lvm/lvm.conf"
    exec_on_node ${NODEA} "perl -pi -e 's|write_cache_state.*|write_cache_state = 0|' /etc/lvm/lvm.conf"
    exec_on_node ${NODEA} "perl -pi -e 's|filter.*|filter = \[ \"a\|\/dev\/drbd\.\*\|\", \"r\|\.\*\|\" \]|' /etc/lvm/lvm.conf"
    echo "- corosync2 on all nodes"
    exec_on_node ${NODEA} "csync2 -xv"
    echo "- Create an LVM volume group by initializing the DRBD resource as an LVM physical volume"
    exec_on_node ${NODEA} "pvcreate /dev/drbd/by-res/nfs/0"
    echo "- Create an LVM Volume Group nfs that includes this physical volume"
    exec_on_node ${NODEA} "vgcreate nfs /dev/drbd/by-res/nfs/0"
    echo "- Create logical volumes in the volume group"
    exec_on_node ${NODEA} "lvcreate -n sales -L 512M nfs"
    exec_on_node ${NODEA} "lvcreate -n devel -L 500M nfs"
    echo "- Activate the volume groups"
    exec_on_node ${NODEA} "vgchange -ay nfs"
    echo "- Create file systems on the new logical volumes"
    exec_on_node ${NODEA} "mkfs.ext3 /dev/nfs/sales"
    exec_on_node ${NODEA} "mkfs.ext3 /dev/nfs/devel"
}

##########################
##########################
### MAIN
##########################
##########################

echo "############ NFS / DRBD SCENARIO #############"
echo "  !! WARNING !! "
echo "  !! WARNING !! "
echo
echo " press [ENTER] twice OR Ctrl+C to abort"
read
read


install_packages
create_pool ${POOLVDD}
create_vol_vdd
attach_storage_to_node
pacemaker_configuration
disable_drbd
create_nfs_resource
update_csync2
finalize_DRBD_setup
create_lvm_on_drbd
