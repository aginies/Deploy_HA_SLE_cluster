#!/bin/sh
#########################################################
#
#
#########################################################
## DRBD OSCF2
#########################################################

if [ -f "${PWD}/drbd_common" ] ; then
    . ${PWD}/drbd_common
else
    echo "! functions file drbd_common needed! ; Exiting"
    exit 1
fi

# SOME VARS
DRBD_NAME="drbdo2"
CIBNAME="drbd_ocfs2"
DRBDRESOURCE="${NODENAME}2"
TARGETVD="vdd"

drbd_ocfs2_cib() {
    echo $I "############ START drbd_ocfs2_cib" $O
    exec_on_node ${NODEA} "crm<<EOF
cib new ${CIBNAME}
verify
cib use live
cib commit ${CIBNAME}
exit
EOF"
}

create_drbd_resource() {
    echo $I "############ START create_drbd_resource"
    echo "- Create /etc/drbd.d/${DRBD_NAME}.res file" $O
    check_targetvd_on_node ${NODEA} vdd d > /tmp/check_targetvd_on_node_${NODEA}
    export REALTARGETVDA=`cat /tmp/check_targetvd_on_node_${NODEA} | tail -2 | awk -F "/dev/" '{print $2}'`
    check_targetvd_on_node ${NODEB} vdd d > /tmp/check_targetvd_on_node_${NODEB}
    export REALTARGETVDB=`cat /tmp/check_targetvd_on_node_${NODEB} | tail -2 | awk -F "/dev/" '{print $2}'`
    exec_on_node ${NODEA} "cat >/etc/drbd.d/${DRBD_NAME}.res<<EOF
resource ${DRBD_NAME} {
  startup {
    become-primary-on both;
  }
  net {
    ## allow-two-primaries;
    after-sb-0pri discard-zero-changes;
    after-sb-1pri discard-secondary;
    after-sb-2pri disconnect;
  }

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
}
EOF"
}


format_ocfs2() {
    # need DLM
    echo $I "############ START format_ocfs2" $O
    exec_on_node ${NODEA} "mkfs.ocfs2 --force --cluster-stack pcmk -L 'VMtesting' --cluster-name hacluster ${DRBDDEV}"
}

create_dlm_resource() {
    echo $I "############ START create_dlm_resource" $O
    exec_on_node ${NODEA} "crm configure<<EOF
primitive dlm ocf:pacemaker:controld op monitor interval='60' timeout='60'
group base-group dlm
clone base-clone base-group meta interleave=true target-role=Started
commit
exit
EOF"
}

delete_all_resources() {
    echo $I "############ START delete_all_resources" $O
    echo $W "- stop base-clone base-group dlm" $O
    exec_on_node ${NODEA} "crm resource<<EOF
stop base-clone
stop base-group
stop dlm
status
EOF"
    echo $I "- Sleep 25sec ..." $O
    sleep 25;
    echo $W "- delete base-clone base-group dlm" $O
    exec_on_node ${NODEA} "crm configure<<EOF
delete base-clone
delete base-group
delete dlm
commit
exit
EOF"
    exec_on_node ${NODEB} "crm status"
}


##########################
##########################
### MAIN
##########################
##########################

echo $I "############ DRBD / OSCFS2 SCENARIO #############"
echo "  !! WARNING !! "
echo "  !! WARNING !! " 
#echo " NOT USABLE NOW .... please QUIT or debug :)"
echo
echo " press [ENTER] twice OR Ctrl+C to abort" $O
read
read

install_packages_drbd
#drbd_ocfs2_cib
stop_drbd
umount_mnttest

enable_drbd
create_pool DRBD
create_vol_name ${NODEA} DRBD DRBD${NODEA}
create_vol_name ${NODEB} DRBD DRBD${NODEB}
attach_disk_to_node ${NODEA} DRBD DRBD${NODEA} ${TARGETVD} qcow2
attach_disk_to_node ${NODEB} DRBD DRBD${NODEB} ${TARGETVD} qcow2
create_drbd_resource
create_dlm_resource
drbdconf_csync2

finalize_DRBD_setup ${DRBD_NAME}
format_ocfs2
check_primary_secondary ${DRBD_NAME}
#

echo " press [ENTER] twice TO Restore initial setting" $O
read
read


# restore before runnning the test
back_to_begining ${DRBD_NAME}
stop_drbd
disable_drbd

# restore initial conf
detach_disk_from_node ${NODEA} ${TARGETVD}
detach_disk_from_node ${NODEB} ${TARGETVD}
delete_all_resources
delete_vol_name ${NODEA} DRBD DRBD${NODEA}
delete_vol_name ${NODEB} DRBD DRBD${NODEB}
delete_pool_name DRBD
