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

* Better clean up (don't leave disks lying around, don't destroy pools
that may be used by others, release IP addresses)

* Don't replace /etc/hosts config for other scenarios

* Don't destroy pools etc. before configuring, since other scenarios
may share pools

* Geo bootstrap for geo scenario

* Cluster tests / run wizards
