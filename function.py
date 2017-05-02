#!/usr/bin/python3


def sbd_test(args):
    """
    Test the SBD devices
    """
    nodes = [ vm.name for vm in clusterdef.vm ]
    # nodes[0] will be the "commander" node
    args.node = nodes[0]
    print("Message test to node {} from {}".format(nodes[2], nodes[0]))
    invoke('ssh root@{} "sbd -d /dev/vdc message {} test"'.format(nodes[0], nodes[2]), echo_stdout=True, echo_stderr_on=True)
    time.sleep(5)
    status_progress()
    check_cluster_status(args)
    invoke('ssh root@{} "journalctl -u sbd --lines 10"'.format(nodes[2]), echo_stdout=True, echo_stderr=True)
#    do_remote(nodes[0], "journalctl -u sbd --lines 10", stderr_on=True)
    check_cluster_status(args)
    print("Reset node {} from {}".format(nodes[2], nodes[0]))
    invoke('ssh root@{} "sbd -d /dev/vdc message {} reset"'.format(nodes[0], nodes[2]), echo_stdout=True, echo_stderr=True)
    check_cluster_status(args)
    print("Wait node {} return (sleep 30s)".format(nodes[2]))
    time.sleep(30)
    status_progress()
    check_cluster_status(args)


def add_remove_node_test(args):
    """
    Test the add remove of a node
    """
    nodes = [ vm.name for vm in clusterdef.vm ]
    nodes.remove(args.node)
    print("Removing node {} from cluster from node {}".format(args.node, nodes[0]))
    invoke('ssh root@{} -t "ha-cluster-remove -c {}"'.format(nodes[0], args.node), echo_stdout=True, echo_stderr=True)
    print("Re-add node {} to cluster from node {}".format(args.node, nodes[0]))
    invoke('ssh root@{} -t "ha-cluster-join -y -c {}"'.format(args.node, nodes[0]), echo_stdout=True, echo_stderr=True)
    check_cluster_status(args)


def maintenance_test(args):
    """
    Do a basic maintenance test on given node
    """
    nodes = [ vm.name for vm in clusterdef.vm ]
    nodes.remove(args.node)
    print("Will put node {} in maintenance and then back to ready".format(args.node))
    invoke('ssh root@{} -t "crm node maintenance {}"'.format(nodes[0], args.node))
    check_cluster_status(args)
    invoke('ssh root@{} -t "crm node ready {}"'.format(nodes[0], args.node))
    check_cluster_status(args)

def basic_test(args):
    """
    Run some basic tests
    """
    nodes = [ vm.name for vm in clusterdef.vm ]
    print("Test csync2")
    invoke('ssh root@{} -t "csync2 -xv"'.format(nodes[0]), echo_stdout=True, echo_stderr=True)
    print("Check OCF")
    invoke('ssh root@{} -t "OCF_ROOT=/usr/lib/ocf /usr/lib/ocf/resource.d/heartbeat/IPaddr meta-data"'.format(nodes[0]), echo_stdout=True, echo_stderr=True)
    print("Test some CRM shell command")
    invoke('ssh root@{} -t "crm ra list stonith"'.format(nodes[0]), echo_stdout=True, echo_stderr=True)
    invoke('ssh root@{} -t "crm script describe health"'.format(nodes[0]), echo_stdout=True, echo_stderr=True)
    invoke('ssh root@{} -t "crm script run health"'.format(nodes[0]), echo_stdout=True, echo_stderr=True)
    invoke('ssh root@{} -t "crm history info"'.format(nodes[0]), echo_stdout=True, echo_stderr=True)
    

       
