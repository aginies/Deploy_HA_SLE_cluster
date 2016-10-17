# Hark! Deploy an HA cluster in Virtual Machines

Hark! is a tool to deploy various types of HA clusters without having
to create a base image. It uses libvirt and autoyast to automate the
creation and base configuration of virtual machines.

## Usage

```
usage: hark [-h] [-q] [-n] [-x] [-d] [-s SCENARIO]
            {download,config,status,up,halt,destroy,bootstrap,test} ...

Hark! A tool for setting up a test cluster for SLE HA. Configure your
scenarios using the hark.ini and scenario files. Run 'up' to prepare the host
and create virtual machines, run 'status' to see the state of the cluster, and
once installation completes, run 'bootstrap' to configure the cluster.

positional arguments:
  {download,config,status,up,halt,destroy,bootstrap,test}
    download            List available variants and download ISO files for
                        variants
    config              Display resolved configuration values
    status              Display status of configuration
    up                  Configure the host and bring virtual machines up
    halt                Tell running VMs to halt
    destroy             Halt and destroy any created VMs
    bootstrap           Bootstrap initial cluster
    test                Run cluster test

optional arguments:
  -h, --help            show this help message and exit
  -q, --quiet           Minimal output
  -n, --non-interactive
                        Assume yes to all prompts
  -x, --debug           Halt in debugger on error
  -d, --download        Download missing ISO files automatically
  -s SCENARIO, --scenario SCENARIO
                        Cluster scenario
```

## History

Originally this was a set of scripts that did mostly the same thing
but only for a 4 node cluster. Description of original scripts below:

### Easily Deploy an HA cluster in Virtual Machines

The goal was to easily and quickly deploy an HA cluster in Virtual
Machine to be able to test latest release and test some scenarios.

Videos: Presentation and a demo at Youtube:
* https://www.youtube.com/watch?v=y0herkr6x-A
* https://www.youtube.com/watch?v=vmUpaabYV-o
* https://www.youtube.com/watch?v=k77sa9y6Lwk

This scripts will configure:
* an host (by default KVM)
* 4 HA nodes ready for HA scenario

All configurations files on the host are dedicated for this cluster, which means
this should not interact or destroy any other configuration (pool, net, etc...)

Please report any bugs or improvments to:
https://github.com/aginies/Deploy_HA_SLE_cluster.git

## Features

* Automatically download the latest ISO
* Configure different scenarios with minimal changes needed
* Pre-install SSH keys for easy access after configuration
* Parallel background installation of VMs

## Configuration

Create different configuration scenarios using the `scenarios/*.ini`
files. See the existing scenarios for details on what can be
configured.

* Per-VM configuration (VCPUs, RAM, etc.)
* Package list to install
* Addons and base image

Basic configuration (username, password, etc.) is done in the
`hark.ini` file. See the `hark.ini.example` file for an example
configuration. The ISO download URL, username and local storage paths
will need to be modified.

* *WARNING* All guest installation will be done at the same time.

## Install / HOWTO

* Clone this repository
* Copy `hark.ini.example` to `hark.ini`
* Adjust settings to your liking
* Configure the host and create VMs: `sudo ./hark up`
* Bootstrap the cluster (optional): `sudo ./hark bootstrap`
* Your HA cluster is now able to run some HA tests

## Scenario configuration files

Most variables should be self-explanatory. Define virtual machine
instances with a section per virtual machine, with a section title as
`[vm:<name>]`.

Configure Addons to download and install using the `[addon:<name>]`
syntax. The base addon is used as the installation image.

## Scripts

### HA_testsuite_init_cluster.sh
Finish the nodes installation and run some tests.
The ha-cluster-init script will be run on node HA1.

*NOTE* This script still needs some work to handle the various
 scenarios configurable by `hark`.

*NOTE* Use the [force] option to bypass the HA cluster check.

## AutoYast templates

The AutoYast files used for auto-installation are based on the
templates found in `templates/`. These may need to be modified for
different versions of SLE or openSUSE.
