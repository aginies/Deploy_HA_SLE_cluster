# HA QA semi auto test suite

Goal: quickly deploy HA VM guest and run basic test
This will configure:
- a pre-configured KVM host
- 4 HA nodes

please report any bugs or improvment:
https://github.com/aginies/Deploy_HA_SLE_cluster.git

default root password: "a"

*WARNING* All guest installation will be done at the same time;
*NOTE* you need an HA DVD rom and an SLE12SPX ISO DVD rom.

## HA_testsuite_host_conf.sh
Configure the host

## HA_testsuite_deploy.sh
Install all nodes with needed data

## HA_testsuite_runtests.sh
Finish the nodes installation and run some tests

## havm.xml
autoyast profile with Graphical interface

## havm_mini.xml
autoyast profile (simple without GUI)

## haqasemi.conf
All variables for VM guest and Host.
NOTE: 
    Adjust path to ISO for installation. Currently this is using local or NFS ISO via a pool.
    HACDROM="/var/lib/libvirt/images/nasin/SLE-12-SP2-HA-DVD-x86_64-Buildxxxx-Media1.iso"
    SLECDROM="/var/lib/libvirt/images/nasin/nasin/SLE-12-SP2-Server-DVD-x86_64-Buildxxxx-Media1.iso"

If you want to specify another way to ISO (like http etc...) you maybe need to adjust
install_vm() function in HA_testsuite_deploy.sh script.
