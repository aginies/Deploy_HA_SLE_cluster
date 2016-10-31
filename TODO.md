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


* Better clean up (don't leave disks lying around, don't destroy pools
that may be used by others, release IP addresses)

* Don't replace /etc/hosts config for other scenarios

* Don't destroy pools etc. before configuring, since other scenarios
may share pools

* Geo bootstrap for geo scenario

* Cluster tests / run wizards
