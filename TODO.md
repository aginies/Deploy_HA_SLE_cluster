# TODO

* Fix shared disk contention issue?

```
Restarting guest.
ERROR    internal error: process exited while connecting to monitor: 2016-10-17T08:34:56.905670Z qemu-system-x86_64: -drive file=/home/krig/vms/hashared/hashared.img,format=raw,if=none,id=drive-virtio-disk1: Could not open '/home/krig/vms/hashared/hashared.img': Permission denied
Domain installation does not appear to have been successful.
If it was, you can restart your domain by running:
  virsh --connect qemu:///system start SLE12SP2hageo21
otherwise, please restart your installation.
Domain has shutdown. Continuing.
```

* Fix VM creation race?

```
ERROR    Error: --disk
path=/home/krig/vms/threenode.raw,format=raw,bus=virtio: Could not
define storage pool: operation failed: pool 'vms' already exists with
uuid 12e505c7-063f-4d08-8d46-b41272b16105
```


* Don't replace /etc/hosts config for other scenarios

* Geo bootstrap for geo scenario

* Cluster tests / run wizards

# AVOID NETWORK ISSSUE

```
virsh # net-define /etc/libvirt/qemu/networks/HAnet3nodes.xml
error: Failed to define network from /etc/libvirt/qemu/networks/HAnet3nodes.xml
error: internal error: bridge name 'virbr1' already in use.

error: Failed to define network from /etc/libvirt/qemu/networks/HAnet3nodes.xml
error: operation failed: network 'HAnet' is already defined with uuid 851e50f1-db72-475a-895f-28304baf8e8c

ERROR    Requested operation is not valid: network 'HAnet3nodes' is not active
virsh # net-start HAnet3nodes
error: Failed to start network HAnet3nodes
error: internal error: Network is already in use by interface virbr1
```
