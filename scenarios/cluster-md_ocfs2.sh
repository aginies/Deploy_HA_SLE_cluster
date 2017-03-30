#!/bin/sh
#########################################################
#
#
#########################################################
## CLUSTER-MD OCFS2
#########################################################

if [ -f ../functions ] ; then
    . ../functions
else
    echo "! functions file needed! ; Exiting"
    exit 1
fi
if [ -f "${PWD}/nodes_ressources" ] ; then
    . ${PWD}/nodes_ressources
else
    echo "! functions file nodes_ressources needed! ; Exiting"
    exit 1
fi

check_load_config_file other

# SOME VARS
CIBNAME="cluster_md_ocfs2"
RESOURCEID="raider"
CLUSTERMDDEV1="vdd"
CLUSTERMDDEV2="vde"
CLUSTERMDDEV3="vdf"

cluster_md_ocfs2_cib() {
    echo "############ START cluster_md_ocfs2_cib"
    exec_on_node ${NODEA} "crm<<EOF
cib new ${CIBNAME}
verify
cib use live
cib commit ${CIBNAME}
exit
EOF"
}

install_packages_cluster_md() {
    echo "############ START install_packages_cluster"
    pssh -h /etc/hanodes "zypper in -y cluster-md-kmp-default mdadm"
}

check_cluster_md_resource() {
    echo "############ START check_cluster_md_resource"
    check_targetvd_on_node ${NODEA} > /tmp/check_targetvd_on_node_${NODEA}
    REALTARGETVDA=`cat /tmp/check_targetvd_on_node_${NODEA} | tail -1 | awk -F "/dev/" '{print $2}'`
    check_targetvd_on_node ${NODEB} > /tmp/check_targetvd_on_node_${NODEB}
    REALTARGETVDB=`cat /tmp/check_targetvd_on_node_${NODEB} | tail -1 | awk -F "/dev/" '{print $2}'`
}

cluster_md_csync2() {
    echo "############ START cluster_md_csync2"
    echo "- Corosync2 /etc/mdadm.conf"
    exec_on_node ${NODEA} "perl -pi -e 's|usage-count.*|usage-count no;|' /etc/drbd.d/global_common.conf"
    exec_on_node ${NODEA} "grep /etc/mdadm.conf /etc/csync2/csync2.cfg"
    if [ $? -eq 1 ]; then
    	exec_on_node ${NODEA} "perl -pi -e 's|}|\tinclude /etc/mdadm.conf;}|' /etc/csync2/csync2.cfg"
    else
        echo "- /etc/csync2/csync2.cfg already contains /etc/mdadm.conf files to sync"
    fi
    exec_on_node ${NODEA} "csync2 -xv"
}

format_ocfs2() {
    # need DLM
    echo "############ START format_ocfs2"
    exec_on_node ${NODEA} "mkfs.ocfs2 --force --cluster-stack pcmk -L 'VMtesting' --cluster-name hacluster /dev/md/md0"
}

umount_mnttest() {
    echo "############ START umount_mnttest"
    exec_on_node ${NODEA} "umount ${MNTTEST}"
    exec_on_node ${NODEB} "umount ${MNTTEST}"
}

monitor_progress() {
    exec_on_node ${NODEA} "cat /proc/mdstat"
}

create_RAID() {
    echo "############ START create_RAID"
#    exec_on_node ${NODEA} "mdadm --create md0 --bitmap=clustered --raid-devices=2 --level=mirror --spare-devices=1 /dev/${CLUSTERMDDEV1} /dev/${CLUSTERMDDEV2} /dev/${CLUSTERMDDEV3}"
    exec_on_node ${NODEA} "mdadm --create md0 --bitmap=clustered --raid-devices=2 --level=mirror /dev/${CLUSTERMDDEV1} /dev/${CLUSTERMDDEV2} --metadata=0.90"
    monitor_progress
    sleep 10
    monitor_progress
    exec_on_node ${NODEA} "csync2 -xv"
}

finish_mdadm_conf() {
    exec_on_node ${NODEA} "mdadm --detail --scan"
    exec_on_node ${NODEA} "mdadm --detail --scan 2> /dev/null | grep UUID | cut -d ' ' -f 4 > /tmp/UUIDMDADM"
    exec_on_node ${NODEA} "export UUIDMDADM=`cat /tmp/UUIDMDADM` ; cat > /etc/mdadm.conf <<EOF
DEVICE /dev/${CLUSTERMDDEV1} /dev/${CLUSTERMDDEV2}
ARRAY /dev/md/md0 ${UUIDMDADM}
EOF"
}

check_cluster_md() {
    echo "############ START check_cluster_md"
    exec_on_node ${NODEA} "mdadm --manage /dev/md/md0 --add /dev/vdd"
    exec_on_node ${NODEA} "mdadm --manage /dev/md/md0 --add /dev/vde"
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

create_raider_primitive() {
    echo "############ START create_raid1_primitive"
    exec_on_node ${NODEA} "crm configure<<EOF
primitive ${RESOURCEID} Raid1 params raidconf='/etc/mdadm.conf' raiddev=/dev/md/md0 force_clones=true op monitor timeout=20s interval=10 op start timeout=20s interval=0 op stop timeout=20s interval=0
modgroup base-group add ${RESOURCEID}
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

install_packages_cluster_md
umount_mnttest

create_pool CLUSTERMD1
create_pool CLUSTERMD2
create_pool CLUSTERMD3
create_vol_name ${NODEA} CLUSTERMD1 CLUSTERMD1${NODEA}
create_vol_name ${NODEA} CLUSTERMD2 CLUSTERMD2${NODEA}
create_vol_name ${NODEA} CLUSTERMD3 CLUSTERMD3${NODEA}
create_vol_name ${NODEB} CLUSTERMD1 CLUSTERMD1${NODEB}
create_vol_name ${NODEB} CLUSTERMD2 CLUSTERMD2${NODEB}
create_vol_name ${NODEB} CLUSTERMD3 CLUSTERMD3${NODEB}
attach_disk_to_node ${NODEA} CLUSTERMD1 ${CLUSTERMDDEV1}
attach_disk_to_node ${NODEA} CLUSTERMD2 ${CLUSTERMDDEV2}
attach_disk_to_node ${NODEA} CLUSTERMD3 ${CLUSTERMDDEV3}
attach_disk_to_node ${NODEB} CLUSTERMD1 ${CLUSTERMDDEV1}
attach_disk_to_node ${NODEB} CLUSTERMD2 ${CLUSTERMDDEV2}
attach_disk_to_node ${NODEB} CLUSTERMD3 ${CLUSTERMDDEV3}
cluster_md_ocfs2_cib
create_RAID
echo "ENTER"; read
create_dlm_resource
echo "ENTER"; read
create_raider_primitive
echo "ENTER"; read
finish_mdadm_conf
echo "ENTER"; read
cluster_md_csync2
echo "ENTER"; read
format_ocfs2
echo "ENTER"; read

# restore before runnning the test
back_to_begining

# restore initial conf
detach_disk_from_node ${NODEA} ${CLUSTERMDDEV1}
detach_disk_from_node ${NODEA} ${CLUSTERMDDEV2}
detach_disk_from_node ${NODEA} ${CLUSTERMDDEV3}
detach_disk_from_node ${NODEB} ${CLUSTERMDDEV1}
detach_disk_from_node ${NODEB} ${CLUSTERMDDEV2}
detach_disk_from_node ${NODEB} ${CLUSTERMDDEV3}
delete_all_resources
delete_vol_name ${NODEA} CLUSTERMD1 CLUSTERMD1${NODEA}
delete_vol_name ${NODEA} CLUSTERMD2 CLUSTERMD2${NODEA}
delete_vol_name ${NODEA} CLUSTERMD3 CLUSTERMD3${NODEA}
delete_vol_name ${NODEB} CLUSTERMD1 CLUSTERMD1${NODEB}
delete_vol_name ${NODEB} CLUSTERMD2 CLUSTERMD2${NODEB}
delete_vol_name ${NODEB} CLUSTERMD3 CLUSTERMD3${NODEB}
delete_pool_name CLUSTERMD1
delete_pool_name CLUSTERMD2
delete_pool_name CLUSTERMD3
delete_cib_resource ${NODEA} ${CIBNAME} ${RESOURCEID}
