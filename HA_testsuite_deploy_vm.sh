#!/bin/sh
#########################################################
#
#
#########################################################
## INSTALL HA Guest (and checks)
#########################################################

if [ -f `pwd`/functions ] ; then
    . `pwd`/functions
else
    echo "! need functions in current path; Exiting"; exit 1
fi
check_config_file


# global VAR
LIBVIRTPOOL="hapool"
DISKHAVM="${STORAGEP}/havm_xml.raw"
EXTRAARGS="autoyast=device://vdc/havm.xml"


# clean up previous VM
cleanup_vm() {
    HANAME="${DISTRO}HA"
    echo "############ START cleanup_vm #############"
    echo "  !! WARNING !! "
    echo "  !! WARNING !! "
    echo "- This will remove previous HA VM guest image (in ${STORAGEP}/${LIBVIRTPOOL} dir)"
    cd ${STORAGEP}/${LIBVIRTPOOL}
    ls -1 ${HANAME}*.qcow2
    echo
    echo " press [ENTER] twice OR Ctrl+C to abort"
    read
    read
    for nb in `seq 1 4`
    do 
    NAME="${HANAME}${nb}"
    virsh list --all | grep ${NAME} > /dev/null
    if [ $? == "0" ]; then
    	echo "- Destroy current VM: ${NAME}"
    	virsh destroy ${NAME}
    	echo "- Undefine current VM: ${NAME}"
    	virsh undefine ${NAME}
    else
        echo "- ${NAME} is not present"
    fi
    echo "- Remove previous image file for VM ${NAME} (${NAME}.qcow2)"
    rm -rvf ${STORAGEP}/${LIBVIRTPOOL}/${NAME}.qcow2
    done
}

# Install HA1 VM  
install_vm() {
    echo "############ START install_vm #############"
    # pool refresh to avoid error
    virsh pool-refresh ${LIBVIRTPOOL}
    echo "- Create new VM guest image file: ${NAME}.qcow2 ${IMAGESIZE}"
    virsh vol-create-as --pool ${LIBVIRTPOOL} --name ${NAME}.qcow2 --capacity ${IMAGESIZE} --allocation ${IMAGESIZE} --format qcow2
    virsh pool-refresh ${LIBVIRTPOOL}
    if [ ! -f ${VMDISK} ]; then echo "- ${VMDISK} NOT present"; exit 1; fi

    screen -d -m -S "install_HA_VM_guest_${NAME}" virt-install --name ${NAME} \
	   --ram ${RAM} \
	   --vcpus ${VCPU} \
	   --virt-type kvm \
	   --graphics vnc,keymap=${KEYMAP} \
	   --network network=${NETWORK},mac=${MAC} \
	   --disk path=${VMDISK},format=qcow2,bus=virtio,cache=none \
	   --disk path=${SBDDISK},bus=virtio \
	   --disk path=${DISKHAVM},bus=virtio \
	   --disk path=${HACDROM},device=cdrom \
	   --disk path=${SLECDROM},device=cdrom \
	   --location ${SLECDROM} \
	   --boot cdrom \
	   --extra-args ${EXTRAARGS} \
	   --watchdog i6300esb,action=poweroff \
	   --console pty,target_type=virtio \
	   --check all=off
}

check_before_install() {
    echo "############ START check_before_install #############"
    if [ ! -f ${DISKHAVM} ]; then 
        echo "- ${DISKHAVM} NOT present, needed for auto installation"; exit 1
    else
        echo "- ${DISKHAVM} is present"
    fi
    if [ ! -f ${SBDDISK} ]; then 
        echo "- ${SBDDISK} NOT present, needed for STONITH (SBD devices)"; exit 1
    else
        echo "- ${SBDDISK} is present"
    fi
}

copy_ssh_key() {
    echo "- Don't forget to copy the root host SSH key to VM guest
ssh-copy-id -f -i /root/.ssh/${IDRSAHA}.pub -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no ha1
ssh-copy-id -f -i /root/.ssh/${IDRSAHA}.pub -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no ha2
ssh-copy-id -f -i /root/.ssh/${IDRSAHA}.pub -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no ha3
ssh-copy-id -f -i /root/.ssh/${IDRSAHA}.pub -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no ha4"
echo 
echo "- Clean up your /root/.ssh/known_hosts from previous config (dirty way below)
cp -avf /dev/null /root/.ssh/known_hosts"
}

##########################
##########################
### MAIN
##########################
##########################

# CLEAN everything
cleanup_vm

# create the pool
create_pool ${LIBVIRTPOOL}

# verify everything is available
check_before_install

# Install HA1 VM
NAME="${DISTRO}HA1"
MAC="52:54:00:c7:92:da"
VMDISK="${STORAGEP}/${LIBVIRTPOOL}/${NAME}.qcow2"
install_vm

# Use a minimal installation without X for HA2 and HA3 etc...
EXTRAARGS="autoyast=device://vdc/havm_mini.xml"

# Install HA2 VM
NAME="${DISTRO}HA2"
MAC="52:54:00:c7:92:db"
VMDISK="${STORAGEP}/${LIBVIRTPOOL}/${NAME}.qcow2"
install_vm

# Install HA3 VM
NAME="${DISTRO}HA3"
MAC="52:54:00:c7:92:dc"
VMDISK="${STORAGEP}/${LIBVIRTPOOL}/${NAME}.qcow2"
install_vm

# Install HA4 VM
NAME="${DISTRO}HA4"
MAC="52:54:00:c7:92:dd"
VMDISK="${STORAGEP}/${LIBVIRTPOOL}/${NAME}.qcow2"
install_vm

# Check VM HA1, HA2, HA3, HA4
virsh list --all

# Get IP address
virsh net-dhcp-leases ${NETWORK}

# List installation in progress
screen -list

copy_ssh_key

