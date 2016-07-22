#!/bin/sh
#########################################################
#
#
#########################################################
## DRBD OSCF2
#########################################################

if [ -f ../functions ] ; then
    . ../functions
else
    echo "! functions file needed! ; Exiting"
    exit 1
fi
check_load_config_file other

# SOME VARS
CIBNAME="drbd_ocfs2"
DRBDRESOURCE="ha2"
DRBDDEV="/dev/drbd0"
POOLDRBD="DRBD"
TARGETVD="vdd"
NODEA="ha1"
NODEB="ha2"
MNTTEST="/mnt/test"
IPA=`grep ${NODEA} /var/lib/libvirt/dnsmasq/${NETWORKNAME}.hostsfile | cut -d , -f 2`
IPB=`grep ${NODEB} /var/lib/libvirt/dnsmasq/${NETWORKNAME}.hostsfile | cut -d , -f 2`

install_packages() {
    echo "############ START finstall_packages"
    pssh -h /etc/hanodes "zypper in -y drbd-kmp-default drbd drbd-utils"
}

drbd_ocfs2_cib() {
    echo "############ START drbd_ocfs2_cib"
    exec_on_node ${NODEA} "crm<<EOF
cib new ${CIBNAME}
verify
cib use live
cib commit ${CIBNAME}
exit
EOF"
}

disable_drbd() {
    echo "############ START disable_drbd"
    echo "- Disable drbd service on node"
    exec_on_node ${NODEA} "systemctl disable drbd"
    exec_on_node ${NODEB} "systemctl disable drbd"
}

enable_drbd() {
    echo "############ START enable_drbd"
    echo "- Enable drbd service on node"
    exec_on_node ${NODEA} "systemctl enable drbd"
    exec_on_node ${NODEB} "systemctl enable drbd"
}

stop_drbd() {
    echo "############ START stop_drbd"
    echo "- Stop drbd service on node"
    exec_on_node ${NODEA} "systemctl stop drbd"
    exec_on_node ${NODEB} "systemctl stop drbd"
}

start_drbd() {
    echo "############ START start_drbd"
    echo "- Start drbd service on node"
    exec_on_node ${NODEA} "systemctl start drbd"
    exec_on_node ${NODEB} "systemctl start drbd"
}


create_vol_drbd() {
    echo "############ START create_vol_drbd"
    echo "- Create volume for DRBD device"
    virsh vol-create-as --pool ${POOLDRBD} --name ${POOLDRBD}A.qcow2 --format qcow2 --capacity 1G --allocation 1G --prealloc-metadata
    virsh vol-create-as --pool ${POOLDRBD} --name ${POOLDRBD}B.qcow2 --format qcow2 --capacity 1G --allocation 1G --prealloc-metadata
    virsh vol-list ${POOLDRBD} --details
    virsh pool-refresh --pool ${POOLDRBD}
}

delete_vol_drbd() {
    echo "############ START delete_vol_drbd"
    virsh vol-delete --pool ${POOLDRBD} ${POOLDRBD}A.qcow2
    virsh vol-delete --pool ${POOLDRBD} ${POOLDRBD}B.qcow2
}

delete_pool_drbd() {
    if [ $# -ne 1 ]; then echo "- delete_pool_drbd need one arg: POOL_NAME" ; exit 1; fi
    POOL="$1"
    echo "############ START delete_pool_drbd"
    virsh pool-destroy ${POOL}
    virsh pool-undefine ${POOL}
    echo "- Delete path to volume"
    rm -rf ${STORAGEP}/DRBD
}

attach_disk_to_node() {
    echo "############ START attach_disk_to_node"
    echo "- Attach volume to node"
    virsh attach-disk ${DISTRO}HA1 --live --cache none --type disk ${STORAGEP}/${POOLDRBD}/${POOLDRBD}A.qcow2 --target ${TARGETVD}
    virsh attach-disk ${DISTRO}HA2 --live --cache none --type disk ${STORAGEP}/${POOLDRBD}/${POOLDRBD}B.qcow2 --target ${TARGETVD}
}

check_targetvd_on_node() {
    # workaround as this is not possible to garantee target device on VM guest
    if [ $# -ne 1 ]; then echo "- check_targetvd_on_node need one arg: NODE_NAME" ; exit 1; fi
    NODE=$1
    exec_on_node ${NODE} "ls -la /dev/${TARGETVD}"
    if [ $? -eq 0 ]; then
	return REALTARGETVD=${TARGETVD}
    else
	for LETTER in {e..z}; do
	    #echo "- Testing /dev/vd${LETTER}"
	    export REALTARGETVD="vd${LETTER}"
	    exec_on_node ${NODE} "ls -la /dev/vd${LETTER}"
	    if [ $? -eq 0 ]; then
		#echo "- Switching target on HA node to vd${LETTER}"
		return REALTARGETVD="vd${LETTER}"
		break
	    #else
	    #echo "- Trying another letter..."
	    fi
	done
    fi
}

detach_disk_from_node() {
    echo "############ START detach_disk_from_node"
    echo "- Detach volume from node"
    virsh detach-disk ${DISTRO}HA1 ${TARGETVD}
    virsh detach-disk ${DISTRO}HA2 ${TARGETVD}
}

create_drbd_resource() {
    echo "############ START create_drbd_resource"
    echo "- Create /etc/drbd.d/drbd.res file"
    check_targetvd_on_node ${NODEA} > /tmp/check_targetvd_on_node_${NODEA}
    REALTARGETVDA=`cat /tmp/check_targetvd_on_node_${NODEA} | tail -1 | awk -F "/dev/" '{print $2}'`
    check_targetvd_on_node ${NODEB} > /tmp/check_targetvd_on_node_${NODEB}
    REALTARGETVDB=`cat /tmp/check_targetvd_on_node_${NODEB} | tail -1 | awk -F "/dev/" '{print $2}'`
    exec_on_node ${NODEA} "cat >/etc/drbd.d/drbd.res<<EOF
resource drbd {
    device ${DRBDDEV};
    meta-disk internal;
    on ${NODEA} {
      address ${IPA}:7790;
      disk /dev/${REALTARGETVDA};
    }
    on ${NODEB} {
      address ${IPB}:7790;
      disk /dev/${REALTARGETVDB};
    }
EOF"
}

drbdconf_csync2() {
    echo "############ START drbdconf_csync2"
    echo "- Corosync2 drbd conf"
    exec_on_node ${NODEA} "perl -pi -e 's|usage-count.*|usage-count no;|' /etc/drbd.d/global_common.conf"
    exec_on_node ${NODEA} "grep /etc/drbd.conf /etc/csync2/csync2.cfg"
    if [ $? -eq 1 ]; then
    	exec_on_node ${NODEA} "perl -pi -e 's|}|\tinclude /etc/drbd.conf;\n\tinclude /etc/drbd.d;\n}|' /et
c/csync2/csync2.cfg"
    else
        echo "- /etc/csync2/csync2.cfg already contains drbd files to sync"
    fi
    exec_on_node ${NODEA} "csync2 -xv"
}

finalize_DRBD_setup() {
    echo "############ START finalize_DRBD_setup"
    echo "- Initializes the metadata storage"
    exec_on_node ${NODEA} "yes yes | drbdadm create-md drbd"
    exec_on_node ${NODEB} "yes yes | drbdadm create-md drbd"
    echo "- Create the /dev/drbd"
    exec_on_node ${NODEA} "drbdadm up drbd"
    exec_on_node ${NODEB} "drbdadm up drbd"
    echo "- Create a new UUID to shorten the initial resynchronization of the DRBD resource"
    exec_on_node ${NODEA} "drbdadm new-current-uuid drbd/0"
    echo "- Make ${NODEA} primary"
    exec_on_node ${NODEA} "drbdadm primary drbd"
    echo "- Check the DRBD status"
    exec_on_node ${NODEA} "cat /proc/drbd"
    echo "- Start the resynchronization process on your intended primary node"
    exec_on_node ${NODEA} "drbdadm -- --overwrite-data-of-peer primary drbd"
}

format_ext3() {
    echo "############ START format_ext3"
    exec_on_node ${NODEA} "mkfs.ext3 -F ${DRBDDEV}"
}

format_ocfs2() {
    # need DLM
    echo "############ START format_ocfs2"
    exec_on_node ${NODEA} "mkfs.ocfs2 ${DRBDDEV}"
}

umount_mnttest() {
    echo "############ START umount_mnttest"
    exec_on_node ${NODEA} "umount ${MNTTEST}"
    exec_on_node ${NODEB} "umount ${MNTTEST}"
}

check_primary_secondary() {
    echo "############ START check_primary_secondary"
    echo "- Create ${MNTTEST} directory"
    exec_on_node ${NODEA} "mkdir ${MNTTEST}"
    exec_on_node ${NODEB} "mkdir ${MNTTEST}"
    echo "- Mount /dev/drbd0"
    exec_on_node ${NODEA} "mount ${DRBDDEV} ${MNTTEST}"
    exec_on_node ${NODEA} "df -h ${MNTTEST}"
    echo "- Create a file in the FS"
    exec_on_node ${NODEA} "dd if=/dev/zero of=${MNTTEST}/testing bs=1M count=24"
    exec_on_node ${NODEA} "dd if=/dev/random of=${MNTTEST}/random count=20240"
    exec_on_node ${NODEA} "sha1sum  ${MNTTEST}/testing ${MNTTEST}/random > ${MNTTEST}/sha1sum"
    exec_on_node ${NODEA} "drbdadm status"
    exec_on_node ${NODEA} "drbdadm dstate drbd"
    echo "- Wait to get drbd sync"
    exec_on_node ${NODEA} "while (drbdadm status | grep Inconsistent); do sleep 5s; done"
    exec_on_node ${NODEA} "drbdadm status"
    exec_on_node ${NODEA} "umount ${MNTTEST}"
    echo "- Switch ${NODEA} to secondary"
    exec_on_node ${NODEA} "drbdadm secondary drbd"
    exec_on_node ${NODEB} "drbdadm primary drbd"
    exec_on_node ${NODEB} "mount /dev/drbd0 ${MNTTEST}"
    exec_on_node ${NODEB} "cat ${MNTTEST}/sha1sum"
    exec_on_node ${NODEB} "sha1sum ${MNTTEST}/testing ${MNTTEST}/random > /mnt/testing_from_${NODEB}"
    exec_on_node ${NODEB} "diff -au ${MNTTEST}/sha1sum /mnt/testing_from_${NODEB}"
    if [ $? -eq 1 ]; then 
	echo "- ! Warning; Corruption in FILES detected: sha1 are different"
    else
	echo "- Same Sha1 from ${NODEA} and ${NODEB}: TEST OK"
    fi
    echo "- Test pause/resume sync "
    exec_on_node ${NODEB} "drbdadm pause-sync drbd"
    exec_on_node ${NODEB} "dd if=/dev/zero of=${MNTTEST}/testing2 bs=1M count=24"
    exec_on_node ${NODEB} "drbdadm status"
    exec_on_node ${NODEB} "drbdadm resume-sync drbd"
    exec_on_node ${NODEB} "drbdadm status"
}

back_to_begining() {
    echo "############ START back_to_begining"
    umount_mnttest
    exec_on_node ${NODEA} "rm -rf ${MNTTEST}"
    exec_on_node ${NODEB} "rm -rf ${MNTTEST}"
    exec_on_node ${NODEB} "drbdadm secondary drbd"
    exec_on_node ${NODEA} "drbdadm down drbd"
    exec_on_node ${NODEB} "drbdadm down drbd"
    exec_on_node ${NODEA} "drbdadm disconnect drbd"
    exec_on_node ${NODEA} "rm -vf /etc/drbd.d/drbd.res"
    exec_on_node ${NODEA} "csync2 -xv"
}

configure_resources() {
    echo "############ START configure_resources"
    echo "- dual primary DRBD"
    exec_on_node ${NODEA} "crm<<EOF
configure primitive resDRBD ocf:linbit:drbd params drbd_resource=${DRBDRESOURCE} operations \$id='resDRBD-operations op monitor interval='20' role='Master' timeout='20' op monitor interval='30' role='Slave' timeout='20' 
configure ms msDRBD resDRBD configure meta resource-stickines='100' notify='true' master-max='2' interleave='true'
EOF"
    exec_on_node ${NODEB} "crm status"
}


##########################
##########################
### MAIN
##########################
##########################

echo "############ DRBD / OSCFS2 SCENARIO #############"
echo "  !! WARNING !! "
echo "  !! WARNING !! "
echo
echo " press [ENTER] twice OR Ctrl+C to abort"
read
read

install_packages
#drbd_ocfs2_cib
stop_drbd
umount_mnttest

enable_drbd
create_pool DRBD
create_vol_drbd
attach_disk_to_node
create_drbd_resource
drbdconf_csync2
#start_drbd
finalize_DRBD_setup
format_ext3
check_primary_secondary

#format_ocfs2
#configure_resources

# restore before runnning the test
back_to_begining
stop_drbd
disable_drbd

# restore initial conf
detach_disk_from_node
delete_vol_drbd
delete_pool_drbd DRBD
