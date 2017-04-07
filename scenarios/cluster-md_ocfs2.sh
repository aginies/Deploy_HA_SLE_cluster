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
CLUSTERMD="CLUSTERMD"
CLUSTERMDDEV1="vdd"
CLUSTERMDDEV2="vde"
CLUSTERMDDEV3="vdf"
diskname="disk"
MDDEV="/dev/md0"

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
    check_targetvd_on_node ${NODEB} vdd d > /tmp/check_targetvd_on_node_${NODEB}
    CLUSTERMDDEV1=`cat /tmp/check_targetvd_on_node_${NODEB} | tail -1 | awk -F "/dev/" '{print $2}'`
    check_targetvd_on_node ${NODEB} vde e > /tmp/check_targetvd_on_node_${NODEB}
    CLUSTERMDDEV2=`cat /tmp/check_targetvd_on_node_${NODEB} | tail -1 | awk -F "/dev/" '{print $2}'`
}

cluster_md_csync2() {
    echo "############ START cluster_md_csync2"
    echo "- Corosync2 /etc/mdadm.conf"
    exec_on_node ${NODEB} "perl -pi -e 's|usage-count.*|usage-count no;|' /etc/drbd.d/global_common.conf"
    exec_on_node ${NODEB} "grep /etc/mdadm.conf /etc/csync2/csync2.cfg"
    if [ $? -eq 1 ]; then
    	exec_on_node ${NODEB} "perl -pi -e 's|}|\tinclude /etc/mdadm.conf;}|' /etc/csync2/csync2.cfg"
    else
        echo "- /etc/csync2/csync2.cfg already contains /etc/mdadm.conf files to sync"
    fi
    exec_on_node ${NODEB} "cat /etc/mdadm.conf"
    exec_on_node ${NODEB} "sync; csync2 -f /etc/mdadm.conf"
    exec_on_node ${NODEB} "csync2 -xv"
}

format_ocfs2() {
    # need DLM
    echo "############ START format_ocfs2"
    exec_on_node ${NODEB} "mkfs.ocfs2 --force --cluster-stack pcmk -L 'VMtesting' --cluster-name hacluster ${MDDEV}"
}

umount_mnttest() {
    echo "############ START umount_mnttest"
    exec_on_node ${NODEA} "umount ${MNTTEST}"
    exec_on_node ${NODEB} "umount ${MNTTEST}"
}

monitor_progress() {
    exec_on_node ${NODEB} "cat /proc/mdstat"
}

create_RAID() {
    echo "############ START create_RAID"
#    exec_on_node ${NODEB} "mdadm --create md0 --bitmap=clustered --raid-devices=2 --level=mirror --spare-devices=1 /dev/${CLUSTERMDDEV1} /dev/${CLUSTERMDDEV2} /dev/${CLUSTERMDDEV3} --metadata=1.2"
    # exec_on_node ${NODEB} "yes| mdadm --create md0 --bitmap=clustered \
    echo "mdadm --create md0 --bitmap=clustered --raid-devices=2 --level=mirror --spare-devices=1 /dev/vdd /dev/vde /dev/vdf --metadata=1.2"
    exec_on_node ${NODEB} "mdadm --create md0 --bitmap=clustered --raid-devices=2 --level=mirror --spare-devices=1 /dev/vdd /dev/vde /dev/vdf --metadata=1.2"
    monitor_progress
}

finish_mdadm_conf() {
    exec_on_node ${NODEB} "mdadm --detail --scan"
    exec_on_node ${NODEB} "echo 'DEVICE /dev/${CLUSTERMDDEV1} /dev/${CLUSTERMDDEV2} /dev/${CLUSTERMDDEV3}' > /etc/mdadm.conf"
    exec_on_node ${NODEB} "mdadm --detail --scan >> /etc/mdadm.conf"
}

check_cluster_md() {
    echo "############ START check_cluster_md"
    #exec_on_node ${NODEA} "mdadm --manage ${MDDEV} --add ${CLUSTERMDDEV1}"
    #exec_on_node ${NODEA} "mdadm --manage ${MDDEV} --add ${CLUSTERMDDEV2}"
    #exec_on_node ${NODEA} "mdadm --manage ${MDDEV} --add ${CLUSTERMDDEV3}"
    echo "- Create ${MNTTEST} directory"
    exec_on_node ${NODEA} "mkdir ${MNTTEST}"
    exec_on_node ${NODEB} "mkdir ${MNTTEST}"
    exec_on_node ${NODEC} "mkdir ${MNTTEST}"
    echo "- Mount on node ${NODEA} ${MDDEV}"
    exec_on_node ${NODEA} "mount ${MDDEV} ${MNTTEST}"
    exec_on_node ${NODEB} "mount ${MDDEV} ${MNTTEST}"
    exec_on_node ${NODEA} "df -h ${MNTTEST}"
    exec_on_node ${NODEB} "df -h ${MNTTEST}"
    echo "- Create a file in the FS"
    exec_on_node ${NODEA} "dd if=/dev/zero of=${MNTTEST}/testing bs=1M count=24"
    exec_on_node ${NODEA} "dd if=/dev/random of=${MNTTEST}/random count=20240"
    exec_on_node ${NODEA} "sha1sum  ${MNTTEST}/testing ${MNTTEST}/random > ${MNTTEST}/sha1sum"
    exec_on_node ${NODEB} "cat ${MNTTEST}/s${NODENAME}1sum"
    exec_on_node ${NODEB} "sha1sum ${MNTTEST}/testing ${MNTTEST}/random > /mnt/testing_from_${NODEB}"
    exec_on_node ${NODEB} "dd if=/dev/zero of=${MNTTEST}/testing2 bs=1M count=24"
    exec_on_node ${NODEA} "touch ${MNTTEST}/bspl{0001..10001}.c"
    #exec_on_node ${NODEA} "ls ${MNTTEST}/*.c"
    exec_on_node ${NODEA} "journalctl --lines 10 --no-pager"
}

back_to_begining() {
    echo "############ START back_to_begining"
    umount_mnttest
    exec_on_node ${NODEA} "rm -rf ${MNTTEST}"
    exec_on_node ${NODEB} "rm -rf ${MNTTEST}"
    exec_on_node ${NODEC} "rm -rf ${MNTTEST}"
    pssh -h /etc/hanodes "rm -vf /etc/mdadm.conf"

}

create_dlm_resource() {
    echo "############ START create_dlm_resource"
    exec_on_node ${NODEA} "crm configure<<EOF
primitive dlm ocf:pacemaker:controld op monitor interval='60' timeout='60'
group base-group dlm
commit
exit
EOF"
}

create_raider_primitive() {
    echo "############ START create_raid1_primitive"
    exec_on_node ${NODEA} "crm configure<<EOF
primitive ${RESOURCEID} Raid1 params raidconf='/etc/mdadm.conf' raiddev=${MDDEV} force_clones=true op monitor timeout=20s interval=10 op start timeout=20s interval=0 op stop timeout=20s interval=0
modgroup base-group add ${RESOURCEID}
show
commit
exit
EOF"
    exec_on_node ${NODEA} "crm configure<<EOF
clone base-clone base-group meta interleave=true target-role=Started
show
commit
exit
EOF"
}

delete_all_resources() {
    echo "############ START delete_all_resources"
    exec_on_node ${NODEA} "crm resource<<EOF
cleanup raider
stop raider
stop base-clone
stop base-group
stop dlm
status
EOF"
    sleep 10;
    exec_on_node ${NODEA} "crm configure<<EOF
delete raider
delete base-clone
delete base-group
delete dlm
commit
exit
EOF"
    exec_on_node ${NODEB} "crm status"
    exec_on_node ${NODEB} "crm resource restart base-clone"
    exec_on_node ${NODEB} "crm resource restart dlm"
    exec_on_node ${NODEB} "crm resource cleanup dlm"
    exec_on_node ${NODEB} "crm resource cleanup raider"
    exec_on_node ${NODEB} "crm resource status"
}

create_3shared_storage() {
    echo "############ START create_3shared_storage"
    virsh pool-list --all | grep ${CLUSTERMD} > /dev/null
    if [ $? == "0" ]; then
        echo "- Destroy current pool ${CLUSTERMD}"
        virsh pool-destroy ${CLUSTERMD}
        echo "- Undefine current pool ${CLUSTERMD}"
        virsh pool-undefine ${CLUSTERMD}
        #rm -vf ${SBDDISK}
    else
        echo "- ${CLUSTERMD} pool is not present"
    fi
    echo "- Define pool ${CLUSTERMD}"
    mkdir -p ${STORAGEP}/${CLUSTERMD}
    virsh pool-define-as --name ${CLUSTERMD} --type dir --target ${STORAGEP}/${CLUSTERMD}
    echo "- Start and Autostart the pool"
    virsh pool-start ${CLUSTERMD}
    virsh pool-autostart ${CLUSTERMD}

    # Create 3 VOLUMES disk1 disk2 disk3
    for vol in `seq 1 3` 
    do
	echo "- Create ${diskname}${vol}.img"
	virsh vol-create-as --pool ${CLUSTERMD} --name ${diskname}${vol}.img --format raw --allocation 1024M --capacity 1024M
    done
}

delete_3shared_storage() {
	echo "############ START delete_3shared_storage"
	echo "- Destroy current pool ${CLUSTERMD}"
	virsh pool-destroy ${CLUSTERMD}
	echo "- Undefine current pool ${CLUSTERMD}"
	virsh pool-undefine ${CLUSTERMD}
	rm -rv ${STORAGEP}/${CLUSTERMD}
}

##########################
##########################
### MAIN
##########################
##########################

echo "############ CLUSTER-MD / OSCFS2 SCENARIO #############"
echo "  !! WARNING !! "
echo "  !! WARNING !! "
#echo " NOT USABLE NOW .... please QUIT or debug :)"
echo
case $1 in
    install)
	install_packages_cluster_md
	;;
    prepare)
	umount_mnttest
	create_3shared_storage
	;;
   attach)
	attach_disk_to_node ${NODEA} ${CLUSTERMD} ${diskname}1 ${CLUSTERMDDEV1} img
	attach_disk_to_node ${NODEA} ${CLUSTERMD} ${diskname}2 ${CLUSTERMDDEV2} img
	attach_disk_to_node ${NODEA} ${CLUSTERMD} ${diskname}3 ${CLUSTERMDDEV3} img
	attach_disk_to_node ${NODEB} ${CLUSTERMD} ${diskname}1 ${CLUSTERMDDEV1} img
	attach_disk_to_node ${NODEB} ${CLUSTERMD} ${diskname}2 ${CLUSTERMDDEV2} img
	attach_disk_to_node ${NODEB} ${CLUSTERMD} ${diskname}3 ${CLUSTERMDDEV3} img
	attach_disk_to_node ${NODEC} ${CLUSTERMD} ${diskname}1 ${CLUSTERMDDEV1} img
	attach_disk_to_node ${NODEC} ${CLUSTERMD} ${diskname}2 ${CLUSTERMDDEV2} img
	attach_disk_to_node ${NODEC} ${CLUSTERMD} ${diskname}3 ${CLUSTERMDDEV3} img
	;;
    crm)
	cluster_md_ocfs2_cib
	create_dlm_resource
	;;
    raid)
	check_cluster_md_resource
	create_RAID
	finish_mdadm_conf
	cluster_md_csync2
	;;
    crmfinish)
	create_raider_primitive
	;;
    format)
	format_ocfs2
	;;
    check)
	check_cluster_md
	;;
    cleanup)
	# restore before runnning the test
	back_to_begining
	# restore initial conf
	detach_disk_from_node ${NODEA} ${CLUSTERMDDEV1}
	detach_disk_from_node ${NODEA} ${CLUSTERMDDEV2}
	detach_disk_from_node ${NODEA} ${CLUSTERMDDEV3}
	detach_disk_from_node ${NODEB} ${CLUSTERMDDEV1}
	detach_disk_from_node ${NODEB} ${CLUSTERMDDEV2}
	detach_disk_from_node ${NODEB} ${CLUSTERMDDEV3}
	detach_disk_from_node ${NODEC} ${CLUSTERMDDEV1}
	detach_disk_from_node ${NODEC} ${CLUSTERMDDEV2}
	detach_disk_from_node ${NODEC} ${CLUSTERMDDEV3}
	delete_all_resources
	delete_3shared_storage
	delete_cib_resource ${NODEA} ${CIBNAME} ${RESOURCEID}
	;;
    all)
	$0 install
	$0 prepare
	$0 attach
	$0 crm
	$0 raid
	$0 crmfinish
	$0 format
	$0 check
	$0 cleanup
	;;
    *)
	echo "
usage of $0

all:		do everything
install:	install all needed packages on nodes
prepare:	umount /mnt/test; create 3 shared storage
attach:		attach disks to nodes
crm:		create a CIB cluster_md_ocfs2
	        create the dlm resource
raid:		verify available disk for nodes 
        	create the RAID device
	        finish the mdadm configuration
	        csync2 the configuration
format:		format in OCFS2 the /dev/md0 device
check:		various test on Raid1
crmfinish:	create the raider primitive
cleanup:	restore everything to initial statement
"
	;;
esac
