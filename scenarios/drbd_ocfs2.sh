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
    echo "- Create /etc/drbd.d/drbdo2.res file" $O
    check_targetvd_on_node ${NODEA} vdd d > /tmp/check_targetvd_on_node_${NODEA}
    export REALTARGETVDA=`cat /tmp/check_targetvd_on_node_${NODEA} | tail -2 | awk -F "/dev/" '{print $2}'`
    check_targetvd_on_node ${NODEB} vdd d > /tmp/check_targetvd_on_node_${NODEB}
    export REALTARGETVDB=`cat /tmp/check_targetvd_on_node_${NODEB} | tail -2 | awk -F "/dev/" '{print $2}'`
    exec_on_node ${NODEA} "cat >/etc/drbd.d/drbdo2.res<<EOF
resource drbdo2 {
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

drbdconf_csync2() {
    echo $I "###########²# START drbdconf_csync2"
    echo "- Corosync2 drbd conf" $O
    exec_on_node ${NODEA} "perl -pi -e 's|usage-count.*|usage-count no;|' /etc/drbd.d/global_common.conf"
    exec_on_node ${NODEA} "grep /etc/drbd.conf /etc/csync2/csync2.cfg"
    if [ $? -eq 1 ]; then
    	exec_on_node ${NODEA} "perl -pi -e 's|}|\tinclude /etc/drbd.conf;\n\tinclude /etc/drbd.d;\n}|' /etc/csync2/csync2.cfg"
    else
        echo $F "- /etc/csync2/csync2.cfg already contains drbd files to sync" $O
    fi
    exec_on_node ${NODEA} "csync2 -xv"
}

finalize_DRBD_setup() {
    echo $I "############ START finalize_DRBD_setup"
    echo "- Initializes the metadata storage" $O
    exec_on_node ${NODEA} "yes yes | drbdadm create-md drbdo2"
    exec_on_node ${NODEB} "yes yes | drbdadm create-md drbdo2"
    echo $I "- Create the /dev/drbd" $O
    exec_on_node ${NODEA} "drbdadm up drbdo2"
    exec_on_node ${NODEB} "drbdadm up drbdo2"
#    echo "- Create a new UUID to shorten the initial resynchronization of the DRBD resource"
    exec_on_node ${NODEA} "drbdadm new-current-uuid drbdo2/0"
    echo $I "- Make ${NODEA} primary" $O
    exec_on_node ${NODEA} "drbdadm primary --force drbdo2"
    echo $I "- Check the DRBD status" $O
    exec_on_node ${NODEA} "cat /proc/drbd"
    #echo "- Start the resynchronization process on your intended primary node"
    #exec_on_node ${NODEA} "drbdadm -- --overwrite-data-of-peer primary drbdo2"
}

format_ocfs2() {
    # need DLM
    echo $I "############ START format_ocfs2" $O
    exec_on_node ${NODEA} "mkfs.ocfs2 --force --cluster-stack pcmk -L 'VMtesting' --cluster-name hacluster ${DRBDDEV}"
}

umount_mnttest() {
    echo $I "############ START umount_mnttest" $O
    exec_on_node ${NODEA} "umount ${MNTTEST}"
    exec_on_node ${NODEB} "umount ${MNTTEST}"
}

check_primary_secondary() {
    echo $I "############ START check_primary_secondary"
    echo "- Create ${MNTTEST} directory" $O
    exec_on_node ${NODEA} "mkdir ${MNTTEST}"
    exec_on_node ${NODEB} "mkdir ${MNTTEST}"
    echo $I "- Mount /dev/drbd0" $O
    exec_on_node ${NODEA} "mount ${DRBDDEV} ${MNTTEST}"
    exec_on_node ${NODEA} "df -h ${MNTTEST}"
    echo $I "- Create a file in the FS" $O
    exec_on_node ${NODEA} "dd if=/dev/zero of=${MNTTEST}/testing bs=1M count=24"
    exec_on_node ${NODEA} "dd if=/dev/random of=${MNTTEST}/random count=20240"
    exec_on_node ${NODEA} "s${NODENAME}1sum  ${MNTTEST}/testing ${MNTTEST}/random > ${MNTTEST}/sha1sum"
    exec_on_node ${NODEA} "drbdadm status"
    exec_on_node ${NODEA} "drbdadm dstate drbdo2"
    echo $I "- Wait to get drbd sync" $O
    exec_on_node ${NODEA} "while (drbdadm status | grep Inconsistent); do sleep 5s; done"
    exec_on_node ${NODEA} "drbdadm status"
    exec_on_node ${NODEA} "umount ${MNTTEST}"
    echo $I "- Switch ${NODEA} to secondary" $O
    exec_on_node ${NODEA} "drbdadm secondary drbdo2"
    exec_on_node ${NODEB} "drbdadm primary drbdo2"
    exec_on_node ${NODEB} "mount /dev/drbd0 ${MNTTEST}"
    exec_on_node ${NODEB} "cat ${MNTTEST}/s${NODENAME}1sum"
    exec_on_node ${NODEB} "s${NODENAME}1sum ${MNTTEST}/testing ${MNTTEST}/random > /mnt/testing_from_${NODEB}"
    exec_on_node ${NODEB} "diff -au ${MNTTEST}/s${NODENAME}1sum /mnt/testing_from_${NODEB}"
    if [ $? -eq 1 ]; then 
	echo $W "- ! Warning; Corruption in FILES detected: s${NODENAME}1 are different" $O
    else
	echo $S "- Same S${NODENAME}1 from ${NODEA} and ${NODEB}: TEST OK" $O
    fi
    echo $I "- Test pause/resume sync " $O
    exec_on_node ${NODEB} "drbdadm pause-sync drbdo2"
    exec_on_node ${NODEB} "dd if=/dev/zero of=${MNTTEST}/testing2 bs=1M count=24"
    exec_on_node ${NODEA} "touch ${MNTTEST}/bspl{0001..10001}.c"
    #exec_on_node ${NODEA} "ls ${MNTTEST}/*.c"
    exec_on_node ${NODEB} "chmod -R 777 ${MNTTEST}/" 
    exec_on_node ${NODEA} "chmod -R 775 ${MNTTEST}/" 
    exec_on_node ${NODEB} "drbdadm status"
    exec_on_node ${NODEB} "drbdadm resume-sync drbdo2"
    exec_on_node ${NODEB} "drbdadm status"
}

back_to_begining() {
    echo $I "############ START back_to_begining" $O
    umount_mnttest
    exec_on_node ${NODEA} "rm -rf ${MNTTEST}"
    exec_on_node ${NODEB} "rm -rf ${MNTTEST}"
    exec_on_node ${NODEB} "drbdadm secondary drbdo2"
    exec_on_node ${NODEA} "drbdadm down drbdo2"
    exec_on_node ${NODEB} "drbdadm down drbdo2"
    exec_on_node ${NODEA} "drbdadm disconnect drbdo2"
    exec_on_node ${NODEA} "rm -vf /etc/drbd.d/drbdo2.res"
    exec_on_node ${NODEA} "csync2 -xv"
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
#start_drbd
finalize_DRBD_setup
format_ocfs2

check_primary_secondary

# restore before runnning the test
back_to_begining
stop_drbd
disable_drbd

# restore initial conf
detach_disk_from_node ${NODEA} ${TARGETVD}
detach_disk_from_node ${NODEB} ${TARGETVD}
delete_all_resources
delete_vol_name ${NODEA} DRBD DRBD${NODEA}
delete_vol_name ${NODEB} DRBD DRBD${NODEB}
delete_pool_name DRBD
