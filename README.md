# HA QA semi auto test suite

Goal: quickly deploy HA nodes (Virtual Machine) and run basic test.
This will configure:
* a KVM host
* 4 HA nodes

All configurations files on the host are dedicated for this cluster, which means
this should not interact or destroy any other configuration (pool, net, etc...)

please report any bugs or improvment:
https://github.com/aginies/Deploy_HA_SLE_cluster.git

*NOTE*: default root password for Virtual Machine is: "a"

* *WARNING* All guest installation will be done at the same time
* *NOTE* you need an HA DVD rom and an SLE12SPX ISO DVD rom as source for Zypper (or a repo)
* *NOTE* Host server should be a SLE or an openSUSE (will use zypper)
* *NOTE* HA1 will be the node where ha-cluster-init will be launched
* *WARNING* running the script will erase all previous configuration

## HA_testsuite_host_conf.sh
Configure the host:
* install virtualization tools and restart libvirtd
* generate an ssh root key, and prepare a config to connect to HA nodes
* pre-configure pssh (generate an /etc/hanodes)
* add HA nodes in /etc/hosts
* create a Virtual Network: DHCP with host/mac/name/ip for HA nodes
* create an SBD pool
* prepapre an image (raw) which contains autoyast file

## HA_testsuite_deploy_vm.sh
Install all nodes with needed data
* clean-up all previous data: VM definition, VM images
* create an hapool to store VM images
* install all HA VM (using screen)
* display information how to copy host root key to HA nodes (VM)

## HA_testsuite_init_cluster.sh
Finish the nodes installation and run some tests.

*WARNING* You need to enter root password to add all nodes to the cluster

## havm.xml
autoyast profile with Graphical interface

## havm_mini.xml
autoyast profile (simple without GUI)

## haqasemi.conf
All variables for VM guest and Host. Most of them should not be changed.

*NOTE*:
You should adjust path to ISO for installation. Currently this is using local or NFS ISO via a pool.
* HACDROM="/var/lib/libvirt/images/nasin/SLE-12-SP2-HA-DVD-x86_64-Buildxxxx-Media1.iso"
* SLECDROM="/var/lib/libvirt/images/nasin/nasin/SLE-12-SP2-Server-DVD-x86_64-Buildxxxx-Media1.iso"

If you want to specify another way to ISO (like http etc...) you maybe need to adjust
install_vm() function in HA_testsuite_deploy_vm.sh script.

## functions
contains needed functions for scripts
