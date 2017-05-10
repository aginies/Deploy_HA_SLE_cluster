#!/bin/sh
#########################################################
#
#
#########################################################
## DRBD EXT3
#########################################################

if [ -f "${PWD}/drbd_common" ] ; then
    . ${PWD}/drbd_common
else
    echo "! functions file drbd_common needed! ; Exiting"
    exit 1
fi

# SOME VARS
CIBNAME="drbd_ext3"
DRBDRESOURCE="${NODENAME}2"
TARGETVD="vdd"

create_drbd_resource() {
    echo $I "############ START create_drbd_resource"
    echo "- Create /etc/drbd.d/drbd.res file" $O
    check_targetvd_on_node ${NODEA} vdd e > /tmp/check_targetvd_on_node_${NODEA}
    export REALTARGETVDA=`cat /tmp/check_targetvd_on_node_${NODEA} | tail -2 | awk -F "/dev/" '{print $2}'`
    check_targetvd_on_node ${NODEB} vdd e > /tmp/check_targetvd_on_node_${NODEB}
    export REALTARGETVDB=`cat /tmp/check_targetvd_on_node_${NODEB} | tail -2 | awk -F "/dev/" '{print $2}'`
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

finalize_DRBD_setup() {
    echo $I "############ START finalize_DRBD_setup"
    echo "- Initializes the metadata storage" $O
    exec_on_node ${NODEA} "yes yes | drbdadm create-md drbd"
    exec_on_node ${NODEB} "yes yes | drbdadm create-md drbd"
    echo $I "- Create the /dev/drbd" $O
    exec_on_node ${NODEA} "drbdadm up drbd"
    exec_on_node ${NODEB} "drbdadm up drbd"
    #echo "- Create a new UUID to shorten the initial resynchronization of the DRBD resource"
    #exec_on_node ${NODEA} "drbdadm new-current-uuid drbd/0"
    echo $I "- Make ${NODEA} primary" $O
    exec_on_node ${NODEA} "drbdadm primary --force drbd"
    echo $I "- Check the DRBD status" $O
    exec_on_node ${NODEA} "cat /proc/drbd"
    #echo "- Start the resynchronization process on your intended primary node"
    #exec_on_node ${NODEA} "drbdadm -- --overwrite-data-of-peer primary drbd"
}

format_ext3() {
    echo $I "############ START format_ext3" $O
    exec_on_node ${NODEA} "mkfs.ext3 -F ${DRBDDEV}"
}

back_to_begining() {
    echo $I "############ START back_to_begining" $O
    umount_mnttest
    exec_on_node ${NODEA} "rm -rf ${MNTTEST}"
    exec_on_node ${NODEB} "rm -rf ${MNTTEST}"
    exec_on_node ${NODEB} "drbdadm secondary drbd"
    exec_on_node ${NODEA} "drbdadm down drbd"
    exec_on_node ${NODEB} "drbdadm down drbd"
    exec_on_node ${NODEA} "drbdadm disconnect drbd" IGNORE
    exec_on_node ${NODEA} "rm -vf /etc/drbd.d/drbd.res"
    exec_on_node ${NODEA} "csync2 -xv"
}

##########################
##########################
### MAIN
##########################
##########################

echo $I "############ DRBD / EXT3 SCENARIO #############"
echo "  !! WARNING !! "
echo "  !! WARNING !! "
echo
echo " press [ENTER] twice OR Ctrl+C to abort" $O
read
read

install_packages_drbd
stop_drbd
umount_mnttest

enable_drbd
create_pool DRBD
create_vol_name ${NODEA} DRBD DRBD${NODEA}
create_vol_name ${NODEB} DRBD DRBD${NODEB}
attach_disk_to_node ${NODEA} DRBD DRBD${NODEA} ${TARGETVD} qcow2
attach_disk_to_node ${NODEB} DRBD DRBD${NODEB} ${TARGETVD} qcow2
create_drbd_resource
drbdconf_csync2
finalize_DRBD_setup
format_ext3
check_primary_secondary

# restore before runnning the test
back_to_begining
stop_drbd
disable_drbd

# restore initial conf
detach_disk_from_node ${NODEA} ${TARGETVD}
detach_disk_from_node ${NODEB} ${TARGETVD}
delete_vol_name ${NODEA} DRBD DRBD${NODEA}
delete_vol_name ${NODEB} DRBD DRBD${NODEB}
delete_pool_name DRBD
