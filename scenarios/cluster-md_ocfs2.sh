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
NODEA="${DISTRO}${NODENAME}1"
NODEB="${DISTRO}${NODENAME}2"
NODEC="${DISTRO}${NODENAME}3"
CIBNAME="cluster_md_ocfs2"
RESOURCEID="raider"
CLUSTERMD="CLUSTERMD"
CLUSTERMDDEV1="vdd"
CLUSTERMDDEV2="vde"
CLUSTERMDDEV3="vdf"
CLUSTERMDDEV4="vdg"
CLUSTERMDDEV5="vdh"
CLUSTERMDDEV6="vdi"
diskname="disk"
MDDEV="/dev/md0"
DEMO=""

cluster_md_ocfs2_cib() {
    echo $I "############ START cluster_md_ocfs2_cib" $O
    exec_on_node ${NODEA} "crm<<EOF
cib new ${CIBNAME}
verify
cib use live
cib commit ${CIBNAME}
exit
EOF"
    if [ "$DEMO" != "" ]; then read; fi

}

install_packages_cluster_md() {
    echo $I "############ START install_packages_cluster" $O
    echo $I "- Installing cluster-md-kmp-default mdadm on all nodes" $O
    pssh -h ${PSSHCONF} "zypper in -y cluster-md-kmp-default mdadm"
    if [ "$DEMO" != "" ]; then read; fi
}

check_cluster_md_resource() {
    echo $I "############ START check_cluster_md_resource" $O
    check_targetvd_on_node ${NODEB} vdd d > /tmp/check_targetvd_on_node_${NODEB}
    CLUSTERMDDEV1=`cat /tmp/check_targetvd_on_node_${NODEB} | tail -2 | awk -F "/dev/" '{print $2}' | head -1`
    check_targetvd_on_node ${NODEB} vde e > /tmp/check_targetvd_on_node_${NODEB}
    CLUSTERMDDEV2=`cat /tmp/check_targetvd_on_node_${NODEB} | tail -2 | awk -F "/dev/" '{print $2}' | head -1`
}

cluster_md_csync2() {
    echo $i "############ START cluster_md_csync2" $O
    echo $I "- Corosync2 /etc/mdadm.conf" $O
    find_resource_running_dlm
    exec_on_node ${RNODE} "perl -pi -e 's|usage-count.*|usage-count no;|' /etc/drbd.d/global_common.conf"
    exec_on_node ${RNODE} "grep /etc/mdadm.conf /etc/csync2/csync2.cfg; echo \$? > /tmp/CODE "
    scp -q -o StrictHostKeyChecking=no ${RNODE}:/tmp/CODE /tmp/CODE
    VALUE=`cat /tmp/CODE`
    if [ $VALUE -ne 0 ]; then
    	exec_on_node ${RNODE} "perl -pi -e 's|}|\tinclude /etc/mdadm.conf;}|' /etc/csync2/csync2.cfg"
    else
        echo $W "- /etc/csync2/csync2.cfg already contains /etc/mdadm.conf files to sync" $O
    fi
    exec_on_node ${RNODE} "cat /etc/mdadm.conf"
    exec_on_node ${RNODE} "sync; csync2 -f /etc/mdadm.conf"
    exec_on_node ${RNODE} "csync2 -xv"
    # dirty workaround....
    exec_on_node ${RNODE} "scp -o StrictHostKeyChecking=no /etc/mdadm.conf ${NODEA}:/etc/"
    exec_on_node ${RNODE} "scp -o StrictHostKeyChecking=no /etc/mdadm.conf ${NODEB}:/etc/"
    exec_on_node ${RNODE} "scp -o StrictHostKeyChecking=no /etc/mdadm.conf ${NODEC}:/etc/"
    if [ "$DEMO" != "" ]; then read; fi
}

format_ocfs2() {
    # need DLM
    echo $I "############ START format_ocfs2" $O
    find_resource_running_dlm
    exec_on_node ${RNODE} "mkfs.ocfs2 --force --cluster-stack pcmk -L 'VMtesting' --cluster-name hacluster ${MDDEV}"
}

format_gfs2() {
    # need DLM
    echo $I "############ START format_gfs2" $O
    find_resource_running_dlm
    exec_on_node ${RNODE} "mkfs.gfs2 -O -p lock_dlm -t hacluster:gfs2 ${MDDEV}"
}


umount_mnttest() {
    echo $I "############ START umount_mnttest" $O
    exec_on_node ${NODEA} "umount ${MNTTEST}" IGNORE
    exec_on_node ${NODEB} "umount ${MNTTEST}" IGNORE
    exec_on_node ${NODEC} "umount ${MNTTEST}" IGNORE
}

monitor_progress() {
    echo $I "############ START monitor_progress" $O
    find_resource_running_dlm
    exec_on_node ${RNODE} "cat /proc/mdstat"
}

create_RAID() {
    echo $I "############ START create_RAID" $O
    #    exec_on_node ${NODEB} "mdadm --create md0 --bitmap=clustered --raid-devices=2 --level=mirror --spare-devices=1 /dev/${CLUSTERMDDEV1} /dev/${CLUSTERMDDEV2} /dev/${CLUSTERMDDEV3} --metadata=1.2"
    # exec_on_node ${NODEB} "yes| mdadm --create md0 --bitmap=clustered \
    echo "mdadm --create /dev/md0 --bitmap=clustered --raid-devices=2 --level=mirror --spare-devices=1 /dev/vdd /dev/vde /dev/vdf --metadata=1.2"
    if [ "$DEMO" != "" ]; then read; fi
    find_resource_running_dlm
    exec_on_node ${RNODE} "mdadm --create /dev/md0 --bitmap=clustered --raid-devices=2 --level=mirror --spare-devices=1 /dev/vdd /dev/vde /dev/vdf --metadata=1.2"
    monitor_progress
    if [ "$DEMO" != "" ]; then read; fi
}

find_resource_running_dlm() {
    echo $I "############ START find_resource_running_dlm" $0
    exec_on_node ${NODENAME}1 "crm_resource -r dlm -W" > /tmp/result
    # use one line, and remove \r
    RNODE=`cat /tmp/result | tail -2 | cut -d ':' -f 2 | sed -e "s/\r//" | head -1`
    echo $I "- found the resource is running on node ${RNODE}" $O
    export $RNODE
}

finish_mdadm_conf() {
    echo $I "############ START finish_mdadm_conf" $O
    find_resource_running_dlm
    exec_on_node ${RNODE} "mdadm --detail --scan"
    if [ "$DEMO" != "" ]; then read; fi
    exec_on_node ${RNODE} "echo 'DEVICE /dev/${CLUSTERMDDEV1} /dev/${CLUSTERMDDEV2} /dev/${CLUSTERMDDEV3} /dev/${CLUSTERMDDEV4} /dev/${CLUSTERMDDEV5} /dev/${CLUSTERMDDEV6}' > /etc/mdadm.conf"
    exec_on_node ${RNODE} "mdadm --detail --scan >> /etc/mdadm.conf"
    if [ "$DEMO" != "" ]; then read; fi
}

check_cluster_md() {
    echo $I "############ START check_cluster_md" $O
    #exec_on_node ${NODEA} "mdadm --manage ${MDDEV} --add ${CLUSTERMDDEV1}"
    #exec_on_node ${NODEA} "mdadm --manage ${MDDEV} --add ${CLUSTERMDDEV2}"
    #exec_on_node ${NODEA} "mdadm --manage ${MDDEV} --add ${CLUSTERMDDEV3}"
    show_md_status
    echo "- Create ${MNTTEST} directory"
    exec_on_node ${NODEA} "mkdir ${MNTTEST}" IGNORE
    exec_on_node ${NODEB} "mkdir ${MNTTEST}" IGNORE
    exec_on_node ${NODEC} "mkdir ${MNTTEST}" IGNORE
    echo "- Mount on node ${NODEA} ${MDDEV}"
    exec_on_node ${NODEA} "mount ${MDDEV} ${MNTTEST}"
    exec_on_node ${NODEB} "mount ${MDDEV} ${MNTTEST}"
    exec_on_node ${NODEA} "df -h ${MNTTEST}"
    exec_on_node ${NODEB} "df -h ${MNTTEST}"
    echo "- Create a file in the FS"
    exec_on_node ${NODEA} "dd if=/dev/zero of=${MNTTEST}/testing bs=1M count=24"
    exec_on_node ${NODEA} "dd if=/dev/random of=${MNTTEST}/random count=20240"
    exec_on_node ${NODEA} "sha1sum  ${MNTTEST}/testing ${MNTTEST}/random > ${MNTTEST}/sha1sum"
    exec_on_node ${NODEB} "cat ${MNTTEST}/sha1sum"
    exec_on_node ${NODEB} "sha1sum ${MNTTEST}/testing ${MNTTEST}/random > /mnt/testing_from_${NODEB}"
    exec_on_node ${NODEB} "diff -au ${MNTTEST}/sha1sum /mnt/testing_from_${NODEB}"
    if [ $? -eq 1 ]; then
        echo $W "- ! Warning; Corruption in FILES detected: s${NODENAME}1 are different" $O
    else
        echo $S "- Same files from ${NODEA} and ${NODEB}: TEST OK" $O
    fi
    exec_on_node ${NODEA} "touch ${MNTTEST}/bspl{001..1001}.c"
    exec_on_node ${NODEB} "ls ${MNTTEST}//bspl001*.c"
    #    exec_on_node ${NODEA} "journalctl --lines 10 --no-pager"
    umount_mnttest
}

spare_mode() {
    SPARE=$1
    echo $I "############ START spare_mode" $O
    echo "- Declare /dev/${CLUSTERMDDEV2} as failed"
    exec_on_node ${NODEA} "mdadm --manage ${MDDEV} --fail ${SPARE}"
    show_md_status
    if [ "$DEMO" != "" ]; then read; fi
    echo "- Re-add /dev/${CLUSTERMDDEV2}"
    exec_on_node ${NODEA} "mdadm --manage ${MDDEV} --re-add ${SPARE}"
    show_md_status
    if [ "$DEMO" != "" ]; then read; fi
}

show_md_status() {
    exec_on_node ${NODEA} "mdadm --detail ${MDDEV}"
}

back_to_begining() {
    echo $I "############ START back_to_begining" $O
    umount_mnttest
    exec_on_node ${NODEA} "rm -rf ${MNTTEST}"
    exec_on_node ${NODEB} "rm -rf ${MNTTEST}"
    exec_on_node ${NODEC} "rm -rf ${MNTTEST}"
    pssh -h ${PSSHCONF} "rm -vf /etc/mdadm.conf"
}

create_dlm_resource() {
    echo $I "############ START create_dlm_resource" $O
    exec_on_node ${NODEA} "OCF_ROOT=/usr/lib/ocf /usr/lib/ocf/resource.d/pacemaker/controld meta-data"
    if [ "$DEMO" != "" ]; then read; fi
    exec_on_node ${NODEA} "crm configure<<EOF
primitive dlm ocf:pacemaker:controld op monitor interval='60' timeout='60'
group base-group dlm
commit
exit
EOF"

    if [ "$DEMO" != "" ]; then read; fi

    exec_on_node ${NODEA} "crm configure<<EOF
clone base-clone base-group meta interleave=true target-role=Started
show
commit
exit
EOF"
    if [ "$DEMO" != "" ]; then read; fi
}

create_raider_primitive() {
    echo $I "############ START create_raid1_primitive" $O
    exec_on_node ${NODEA} "crm configure<<EOF
primitive ${RESOURCEID} Raid1 params raidconf='/etc/mdadm.conf' raiddev=${MDDEV} force_clones=true op monitor timeout=20s interval=10 op start timeout=20s interval=0 op stop timeout=20s interval=0
modgroup base-group add ${RESOURCEID}
show
commit
exit
EOF"
    echo $I "- Sleep 5sec until Raid is ready" $O
    sleep 5
    if [ "$DEMO" != "" ]; then read; fi
    exec_on_node ${NODEA} "journalctl --lines 8 --no-pager"
    exec_on_node ${NODEB} "crm status"

}

grow_device() {
    echo $I "############ START grow_device" $O
    echo $I "- Add more backend devices" $O
    exec_on_node ${NODEA} "mdadm --manage ${MDDEV} --add /dev/vdg" $O
    exec_on_node ${NODEA} "mdadm --manage ${MDDEV} --add /dev/vdh" $O
    exec_on_node ${NODEA} "mdadm --manage ${MDDEV} --add /dev/vdi" $O
    if [ "$DEMO" != "" ]; then read; fi
    show_md_status
    if [ "$DEMO" != "" ]; then read; fi
    echo $I "- Declare as fail the spare, remove it" $O
    exec_on_node ${NODEA} "mdadm --manage ${MDDEV} --fail /dev/vde" $O
    exec_on_node ${NODEA} "mdadm --manage ${MDDEV} --fail /dev/vdf" $O
    if [ "$DEMO" != "" ]; then read; fi
    show_md_status
    if [ "$DEMO" != "" ]; then read; fi
    echo $I "- Remove the Faulty" $O
    exec_on_node ${NODEA} "mdadm --manage ${MDDEV} --remove /dev/vde" $O
    exec_on_node ${NODEA} "mdadm --manage ${MDDEV} --remove /dev/vdf" $O
    if [ "$DEMO" != "" ]; then read; fi
    show_md_status
    if [ "$DEMO" != "" ]; then read; fi
    echo $I "- Once Sync done, declare failed latest Active on 1Gb, 1 spare of 2Gb will replace it" $O
    exec_on_node ${NODEA} "mdadm --manage ${MDDEV} --fail /dev/vdd" $O
    if [ "$DEMO" != "" ]; then read; fi
    echo $I "- Remove the latest fail device of 1Gb" $O
    exec_on_node ${NODEA} "mdadm --manage ${MDDEV} --remove /dev/vdd" $O
    show_md_status
    if [ "$DEMO" != "" ]; then read; fi
    echo $I "- Grow the size of ${MDDEV}" $O
    exec_on_node ${NODEA} "mdadm --grow ${MDDEV} --size=max" $O
    exec_on_node ${NODEA} "mdadm --grow ${MDDEV} --size=max" $O
    if [ "$DEMO" != "" ]; then read; fi
    echo $I "- Grow the size of the FS" $O
    exec_on_node ${NODEA} "tunefs.ocfs2 -S -v ${MDDEV}" $O
    if [ "$DEMO" != "" ]; then read; fi

}

delete_all_resources() {
    echo $I "############ START delete_all_resources" $O
    exec_on_node ${NODEA} "crm resource<<EOF
cleanup raider
stop raider
stop base-clone
stop base-group
stop dlm
status
EOF"
    sleep 20;
    exec_on_node ${NODEA} "crm configure<<EOF
delete raider
delete base-clone
delete base-group
delete dlm
commit
exit
EOF"
    exec_on_node ${NODEB} "crm status"
    #    exec_on_node ${NODEB} "crm resource restart base-clone"
    #    exec_on_node ${NODEB} "crm resource restart dlm"
    #    exec_on_node ${NODEB} "crm resource cleanup dlm"
    #    exec_on_node ${NODEB} "crm resource cleanup raider"
    exec_on_node ${NODEB} "crm resource status"
}

create_shared_storage() {
    echo $I "############ START create_shared_storage" $O
    virsh pool-list --all | grep ${CLUSTERMD} > /dev/null
    if [ $? == "0" ]; then
        echo $W "- Destroy current pool ${CLUSTERMD}" $O
        virsh pool-destroy ${CLUSTERMD}
        echo $W "- Undefine current pool ${CLUSTERMD}" $O
        virsh pool-undefine ${CLUSTERMD}
        #rm -vf ${SBDDISK}
    else
        echo $W "- ${CLUSTERMD} pool is not present" $O
    fi
    echo $I "- Define pool ${CLUSTERMD}" $O
    mkdir -p ${STORAGEP}/${CLUSTERMD}
    virsh pool-define-as --name ${CLUSTERMD} --type dir --target ${STORAGEP}/${CLUSTERMD}
    echo $I "- Start and Autostart the pool" $O
    virsh pool-start ${CLUSTERMD}
    virsh pool-autostart ${CLUSTERMD}

    # Create 5 VOLUMES disk1 disk2 disk3 disk4 disk5 disk 6
    for vol in `seq 1 3` 
    do
	echo $I "- Create ${diskname}${vol}.img 1024M" $O
	virsh vol-create-as --pool ${CLUSTERMD} --name ${diskname}${vol}.img --format raw --allocation 1024M --capacity 1024M
    done
    for vol in `seq 4 6` 
    do
	echo $I "- Create ${diskname}${vol}.img 2048M" $O
    	virsh vol-create-as --pool ${CLUSTERMD} --name ${diskname}${vol}.img --format raw --allocation 2048M --capacity 2048M
    done
}

delete_shared_storage() {
    echo $I "############ START delete_shared_storage"
    echo $W "- Destroy current pool ${CLUSTERMD}" $O
    virsh pool-destroy ${CLUSTERMD}
    echo $W "- Undefine current pool ${CLUSTERMD}" $O
    virsh pool-undefine ${CLUSTERMD}
    rm -rfv ${STORAGEP}/${CLUSTERMD}
}

##########################
##########################
### MAIN
##########################
##########################

echo $I "############ CLUSTER-MD / OSCFS2 SCENARIO #############"
echo "  !! WARNING !! "
echo "  !! WARNING !! "
echo "  Running this script will undefine previous scenario" $O
#echo " NOT USABLE NOW .... please QUIT or debug :)"
echo
case $1 in
    install)
	install_packages_cluster_md
	;;
    prepare)
	umount_mnttest
	create_shared_storage
	;;
    attach)
	attach_disk_to_node ${NODEA} ${CLUSTERMD} ${diskname}1 ${CLUSTERMDDEV1} img
	attach_disk_to_node ${NODEA} ${CLUSTERMD} ${diskname}2 ${CLUSTERMDDEV2} img
	attach_disk_to_node ${NODEA} ${CLUSTERMD} ${diskname}3 ${CLUSTERMDDEV3} img
	attach_disk_to_node ${NODEA} ${CLUSTERMD} ${diskname}4 ${CLUSTERMDDEV4} img
	attach_disk_to_node ${NODEA} ${CLUSTERMD} ${diskname}5 ${CLUSTERMDDEV5} img
	attach_disk_to_node ${NODEA} ${CLUSTERMD} ${diskname}6 ${CLUSTERMDDEV6} img
	attach_disk_to_node ${NODEB} ${CLUSTERMD} ${diskname}1 ${CLUSTERMDDEV1} img
	attach_disk_to_node ${NODEB} ${CLUSTERMD} ${diskname}2 ${CLUSTERMDDEV2} img
	attach_disk_to_node ${NODEB} ${CLUSTERMD} ${diskname}3 ${CLUSTERMDDEV3} img
	attach_disk_to_node ${NODEB} ${CLUSTERMD} ${diskname}4 ${CLUSTERMDDEV4} img
	attach_disk_to_node ${NODEB} ${CLUSTERMD} ${diskname}5 ${CLUSTERMDDEV5} img
	attach_disk_to_node ${NODEB} ${CLUSTERMD} ${diskname}6 ${CLUSTERMDDEV6} img
	attach_disk_to_node ${NODEC} ${CLUSTERMD} ${diskname}1 ${CLUSTERMDDEV1} img
	attach_disk_to_node ${NODEC} ${CLUSTERMD} ${diskname}2 ${CLUSTERMDDEV2} img
	attach_disk_to_node ${NODEC} ${CLUSTERMD} ${diskname}3 ${CLUSTERMDDEV3} img
	attach_disk_to_node ${NODEC} ${CLUSTERMD} ${diskname}4 ${CLUSTERMDDEV4} img
	attach_disk_to_node ${NODEC} ${CLUSTERMD} ${diskname}5 ${CLUSTERMDDEV5} img
	attach_disk_to_node ${NODEC} ${CLUSTERMD} ${diskname}6 ${CLUSTERMDDEV6} img
	;;
    crm)
	cluster_md_ocfs2_cib
	create_dlm_resource
	;;
    raid)
	check_cluster_md_resource
	create_RAID
	finish_mdadm_conf
	;;
    csync2)
	cluster_md_csync2
	;;
    crmfinish)
	create_raider_primitive
	;;
    formatocfs2)
	format_ocfs2
	;;
    formatgfs2)
	format_gfs2
	;;
    mdstatus)
	show_md_status
	;;
    check)
	check_cluster_md
	;;
    status)
    	exec_on_node ${NODEA} "crm status"
	;;
    spare)
	if [ "$2" == "" ] ; then echo "Please Specify the device (/dev/vdX)"; exit 1; fi
	spare_mode $2
	;;
    growdev)
	grow_device
	;;
    detach)
        detach_disk_from_node ${NODEA} ${CLUSTERMDDEV1}
        detach_disk_from_node ${NODEA} ${CLUSTERMDDEV2}
        detach_disk_from_node ${NODEA} ${CLUSTERMDDEV3}
        detach_disk_from_node ${NODEA} ${CLUSTERMDDEV4}
        detach_disk_from_node ${NODEA} ${CLUSTERMDDEV5}
        detach_disk_from_node ${NODEA} ${CLUSTERMDDEV6}
        detach_disk_from_node ${NODEB} ${CLUSTERMDDEV1}
        detach_disk_from_node ${NODEB} ${CLUSTERMDDEV2}
        detach_disk_from_node ${NODEB} ${CLUSTERMDDEV3}
        detach_disk_from_node ${NODEB} ${CLUSTERMDDEV4}
        detach_disk_from_node ${NODEB} ${CLUSTERMDDEV5}
        detach_disk_from_node ${NODEB} ${CLUSTERMDDEV6}
        detach_disk_from_node ${NODEC} ${CLUSTERMDDEV1}
        detach_disk_from_node ${NODEC} ${CLUSTERMDDEV2}
        detach_disk_from_node ${NODEC} ${CLUSTERMDDEV3}
        detach_disk_from_node ${NODEC} ${CLUSTERMDDEV4}
        detach_disk_from_node ${NODEC} ${CLUSTERMDDEV5}
        detach_disk_from_node ${NODEC} ${CLUSTERMDDEV6}
	;;
    cleanup)
	# restore before runnning the test
	back_to_begining
	# restore initial conf
        detach_disk_from_node ${NODEA} ${CLUSTERMDDEV1}
        detach_disk_from_node ${NODEA} ${CLUSTERMDDEV2}
        detach_disk_from_node ${NODEA} ${CLUSTERMDDEV3}
        detach_disk_from_node ${NODEA} ${CLUSTERMDDEV4}
        detach_disk_from_node ${NODEA} ${CLUSTERMDDEV5}
        detach_disk_from_node ${NODEA} ${CLUSTERMDDEV6}
        detach_disk_from_node ${NODEB} ${CLUSTERMDDEV1}
        detach_disk_from_node ${NODEB} ${CLUSTERMDDEV2}
        detach_disk_from_node ${NODEB} ${CLUSTERMDDEV3}
        detach_disk_from_node ${NODEB} ${CLUSTERMDDEV4}
        detach_disk_from_node ${NODEB} ${CLUSTERMDDEV5}
        detach_disk_from_node ${NODEB} ${CLUSTERMDDEV6}
        detach_disk_from_node ${NODEC} ${CLUSTERMDDEV1}
        detach_disk_from_node ${NODEC} ${CLUSTERMDDEV2}
        detach_disk_from_node ${NODEC} ${CLUSTERMDDEV3}
        detach_disk_from_node ${NODEC} ${CLUSTERMDDEV4}
        detach_disk_from_node ${NODEC} ${CLUSTERMDDEV5}
        detach_disk_from_node ${NODEC} ${CLUSTERMDDEV6}
	delete_all_resources
	delete_shared_storage
	delete_cib_resource ${NODEA} ${CIBNAME} ${RESOURCEID}
	;;
    reboot)
        pssh -h ${PSSHCONF} "reboot"
	;;
    all)
	install_packages_cluster_md
	umount_mnttest
	create_shared_storage
	attach_disk_to_node ${NODEA} ${CLUSTERMD} ${diskname}1 ${CLUSTERMDDEV1} img
	attach_disk_to_node ${NODEA} ${CLUSTERMD} ${diskname}2 ${CLUSTERMDDEV2} img
	attach_disk_to_node ${NODEA} ${CLUSTERMD} ${diskname}3 ${CLUSTERMDDEV3} img
	attach_disk_to_node ${NODEA} ${CLUSTERMD} ${diskname}4 ${CLUSTERMDDEV4} img
	attach_disk_to_node ${NODEA} ${CLUSTERMD} ${diskname}5 ${CLUSTERMDDEV5} img
	attach_disk_to_node ${NODEA} ${CLUSTERMD} ${diskname}6 ${CLUSTERMDDEV6} img
	attach_disk_to_node ${NODEB} ${CLUSTERMD} ${diskname}1 ${CLUSTERMDDEV1} img
	attach_disk_to_node ${NODEB} ${CLUSTERMD} ${diskname}2 ${CLUSTERMDDEV2} img
	attach_disk_to_node ${NODEB} ${CLUSTERMD} ${diskname}3 ${CLUSTERMDDEV3} img
	attach_disk_to_node ${NODEB} ${CLUSTERMD} ${diskname}4 ${CLUSTERMDDEV4} img
	attach_disk_to_node ${NODEB} ${CLUSTERMD} ${diskname}5 ${CLUSTERMDDEV5} img
	attach_disk_to_node ${NODEB} ${CLUSTERMD} ${diskname}6 ${CLUSTERMDDEV6} img
	attach_disk_to_node ${NODEC} ${CLUSTERMD} ${diskname}1 ${CLUSTERMDDEV1} img
	attach_disk_to_node ${NODEC} ${CLUSTERMD} ${diskname}2 ${CLUSTERMDDEV2} img
	attach_disk_to_node ${NODEC} ${CLUSTERMD} ${diskname}3 ${CLUSTERMDDEV3} img
	attach_disk_to_node ${NODEC} ${CLUSTERMD} ${diskname}4 ${CLUSTERMDDEV4} img
	attach_disk_to_node ${NODEC} ${CLUSTERMD} ${diskname}5 ${CLUSTERMDDEV5} img
	attach_disk_to_node ${NODEC} ${CLUSTERMD} ${diskname}6 ${CLUSTERMDDEV6} img
	cluster_md_ocfs2_cib
	create_dlm_resource
	check_cluster_md_resource
	create_RAID
	finish_mdadm_conf
	cluster_md_csync2
	create_raider_primitive
	format_ocfs2
	check_cluster_md
        detach_disk_from_node ${NODEA} ${CLUSTERMDDEV1}
        detach_disk_from_node ${NODEA} ${CLUSTERMDDEV2}
        detach_disk_from_node ${NODEA} ${CLUSTERMDDEV3}
        detach_disk_from_node ${NODEA} ${CLUSTERMDDEV4}
        detach_disk_from_node ${NODEA} ${CLUSTERMDDEV5}
        detach_disk_from_node ${NODEA} ${CLUSTERMDDEV6}
        detach_disk_from_node ${NODEB} ${CLUSTERMDDEV1}
        detach_disk_from_node ${NODEB} ${CLUSTERMDDEV2}
        detach_disk_from_node ${NODEB} ${CLUSTERMDDEV3}
        detach_disk_from_node ${NODEB} ${CLUSTERMDDEV4}
        detach_disk_from_node ${NODEB} ${CLUSTERMDDEV5}
        detach_disk_from_node ${NODEB} ${CLUSTERMDDEV6}
        detach_disk_from_node ${NODEC} ${CLUSTERMDDEV1}
        detach_disk_from_node ${NODEC} ${CLUSTERMDDEV2}
        detach_disk_from_node ${NODEC} ${CLUSTERMDDEV3}
        detach_disk_from_node ${NODEC} ${CLUSTERMDDEV4}
        detach_disk_from_node ${NODEC} ${CLUSTERMDDEV5}
        detach_disk_from_node ${NODEC} ${CLUSTERMDDEV6}
	# restore before runnning the test
	back_to_begining
	# restore initial conf
        detach_disk_from_node ${NODEA} ${CLUSTERMDDEV1}
        detach_disk_from_node ${NODEA} ${CLUSTERMDDEV2}
        detach_disk_from_node ${NODEA} ${CLUSTERMDDEV3}
        detach_disk_from_node ${NODEA} ${CLUSTERMDDEV4}
        detach_disk_from_node ${NODEA} ${CLUSTERMDDEV5}
        detach_disk_from_node ${NODEA} ${CLUSTERMDDEV6}
        detach_disk_from_node ${NODEB} ${CLUSTERMDDEV1}
        detach_disk_from_node ${NODEB} ${CLUSTERMDDEV2}
        detach_disk_from_node ${NODEB} ${CLUSTERMDDEV3}
        detach_disk_from_node ${NODEB} ${CLUSTERMDDEV4}
        detach_disk_from_node ${NODEB} ${CLUSTERMDDEV5}
        detach_disk_from_node ${NODEB} ${CLUSTERMDDEV6}
        detach_disk_from_node ${NODEC} ${CLUSTERMDDEV1}
        detach_disk_from_node ${NODEC} ${CLUSTERMDDEV2}
        detach_disk_from_node ${NODEC} ${CLUSTERMDDEV3}
        detach_disk_from_node ${NODEC} ${CLUSTERMDDEV4}
        detach_disk_from_node ${NODEC} ${CLUSTERMDDEV5}
        detach_disk_from_node ${NODEC} ${CLUSTERMDDEV6}
	delete_all_resources
	delete_shared_storage
	delete_cib_resource ${NODEA} ${CIBNAME} ${RESOURCEID}
	;;
    *)
	echo "
usage of $0

all:		do everything
install:	install all needed packages on nodes
prepare:	umount /mnt/test; create 6 shared storage 1G (3 not used 2G)
attach:		attach disks to nodes
crm:		create a CIB cluster_md_ocfs2
	        create the dlm resource
raid:		verify available disk for nodes 
        	create the RAID device
	        finish the mdadm configuration
csync2:	        csync2 the configuration
crmfinish:	create the raider primitive
formatocfs2:	format in OCFS2 the ${MDDEV} device
formatgfs2:	format in GFS2 the ${MDDEV} device
check:		various test on RAID1
spare:		test the spare functionality
cleanup:	restore everything to initial statement
growdev:	demo to Grow the device

status:		show crm status
mdstatus:	show md status
detach:		detach disks to nodes
reboot:		reboot all nodes (mandatory in case of error in storage name)
"
	;;
esac
