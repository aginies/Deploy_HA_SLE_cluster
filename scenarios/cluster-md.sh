#!/bin/sh
#########################################################
#
#
#########################################################
## CLUSTER-MD OCFS2
#########################################################

# SOME VARS
CIBNAME="cluster-md_ocfs2"
CLUSTERMDDEV1="vdd"
CLUSTERMDDEV2="vdc"
CLUSTERMDDEV3="vde"


cluster-md_ocfs2_cib() {
    echo "############ START cluster-md_ocfs2_cib"
    exec_on_node ${NODEA} "crm<<EOF
cib new ${CIBNAME}
verify
cib use live
cib commit ${CIBNAME}
exit
EOF"
}

install_packages_cluster() {
	echo "############ START install_packages_cluster"
	pssh -h /etc/hanodes "zypper in -y cluster-md-kmp-default"
}

create_cluster-md_resource() {
    echo "############ START check_cluster-md_resource"
    check_targetvd_on_node ${NODEA} > /tmp/check_targetvd_on_node_${NODEA}
    REALTARGETVDA=`cat /tmp/check_targetvd_on_node_${NODEA} | tail -1 | awk -F "/dev/" '{print $2}'`
    check_targetvd_on_node ${NODEB} > /tmp/check_targetvd_on_node_${NODEB}
    REALTARGETVDB=`cat /tmp/check_targetvd_on_node_${NODEB} | tail -1 | awk -F "/dev/" '{print $2}'`
}

cluster-md_csync2() {
    echo "############ START drbdconf_csync2"
    echo "- Corosync2 drbd conf"
    exec_on_node ${NODEA} "perl -pi -e 's|usage-count.*|usage-count no;|' /etc/drbd.d/global_common.conf"
    exec_on_node ${NODEA} "grep /etc/mdadm.conf /etc/csync2/csync2.cfg"
    if [ $? -eq 1 ]; then
    	exec_on_node ${NODEA} "perl -pi -e 's|}|\tinclude /etc/mdadm.conf;}|' /etc/csync2/csync2.cfg"
    else
        echo "- /etc/csync2/csync2.cfg already contains drbd files to sync"
    fi
    exec_on_node ${NODEA} "csync2 -xv"
}

format_ocfs2() {
    # need DLM
    echo "############ START format_ocfs2"
    exec_on_node ${NODEA} "mkfs.ocfs2 --force --cluster-stack pcmk -L 'VMtesting' --cluster-name hacluster ${CLUSTERMDDEV1}"
}

umount_mnttest() {
    echo "############ START umount_mnttest"
    exec_on_node ${NODEA} "umount ${MNTTEST}"
    exec_on_node ${NODEB} "umount ${MNTTEST}"
}

check_cluster-md() {
    echo "############ START check_cluster-md"
    echo "- Create ${MNTTEST} directory"
    exec_on_node ${NODEA} "mkdir ${MNTTEST}"
    exec_on_node ${NODEB} "mkdir ${MNTTEST}"
    echo "- Mount on node ${NODEA} ${CLUSTERMDDEV1}"
    exec_on_node ${NODEA} "mount ${CLUSTERMDDEV1} ${MNTTEST}"
    exec_on_node ${NODEA} "df -h ${MNTTEST}"
    echo "- Create a file in the FS"
    exec_on_node ${NODEA} "dd if=/dev/zero of=${MNTTEST}/testing bs=1M count=24"
    exec_on_node ${NODEA} "dd if=/dev/random of=${MNTTEST}/random count=20240"
    exec_on_node ${NODEA} "s${NODENAME}1sum  ${MNTTEST}/testing ${MNTTEST}/random > ${MNTTEST}/sha1sum"
    exec_on_node ${NODEA} "mdadm --detail --scan"
    exec_on_node ${NODEA} "umount ${MNTTEST}"
    exec_on_node ${NODEB} "cat ${MNTTEST}/s${NODENAME}1sum"
    exec_on_node ${NODEB} "s${NODENAME}1sum ${MNTTEST}/testing ${MNTTEST}/random > /mnt/testing_from_${NODEB}"
    exec_on_node ${NODEB} "dd if=/dev/zero of=${MNTTEST}/testing2 bs=1M count=24"
    exec_on_node ${NODEA} "touch ${MNTTEST}/bspl{0001..10001}.c"
    #exec_on_node ${NODEA} "ls ${MNTTEST}/*.c"
    exec_on_node ${NODEA} "chmod -R 775 ${MNTTEST}/" 
}

back_to_begining() {
    echo "############ START back_to_begining"
    umount_mnttest
    exec_on_node ${NODEA} "rm -rf ${MNTTEST}"
    exec_on_node ${NODEB} "rm -rf ${MNTTEST}"
    exec_on_node ${NODEA} "csync2 -xv"
}

create_dlm_resource() {
	echo "############ START create_dlm_resource"
    exec_on_node ${NODEA} "crm configure<<EOF
primitive dlm ocf:pacemaker:controld op monitor interval='60' timeout='60'
group base-group dlm
clone base-clone base-group meta interleave=true target-role=Started
commit
exit
EOF"
}

delete_all_resources() {
    echo "############ START delete_all_resources"
    exec_on_node ${NODEA} "crm resource<<EOF
stop base-clone
stop base-group
stop dlm
status
EOF"
    sleep 25;
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

echo "############ CLUSTER-mD / OSCFS2 SCENARIO #############"
echo "  !! WARNING !! "
echo "  !! WARNING !! "
#echo " NOT USABLE NOW .... please QUIT or debug :)"
echo
echo " press [ENTER] twice OR Ctrl+C to abort"
read
read

install_packages_cluster-md
stop_cluster-md
umount_mnttest

enable_clustermd
create_vol_name CLUSTERMD
attach_disk_to_node CLUSTERMD
create_cluster-md_resource
create_dlm_resource
cluster-md_csync2
finalize_cluster-md_setup
format_ocfs2

# restore before runnning the test
back_to_begining
read
stop_cluster-md
disable_cluster-md

# restore initial conf
detach_disk_from_node
delete_all_resources
delete_vol_name CLUSTERMD
delete_pool_name CLUSTERMD
