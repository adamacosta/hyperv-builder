# Linux on Windows Hypervisors

## Disk blocksize and ext4 flex block groups

See [Tuning Linux File Systems on Dynamic VHDX Files](https://docs.microsoft.com/en-us/windows-server/virtualization/hyper-v/best-practices-for-running-linux-on-hyper-v#tuning-linux-file-systems-on-dynamic-vhdx-files)

`hvb build` will do the first part for you (setting blocksize to 1MB). Filesystem group size needs to be set to `4096` by your install/configure scripts, i.e. `cloud-init` `setup-disks` module `fs_setup` keys or `sh` `mkfs` commands.

If you choose to do this with `cloud-init`, beware that the full set of options available to `fs_setup` are not documented. You can pass extra options to the `mkfs` command, which is chosen based on the filesystem type, using the `extra_opts` string. So if you are setting up a `ext4` filesystem, you would want something like this:

```yaml
fs_setup:
  - label: root_fs
    filesystem: ext4
    device: /dev/sda
    partition: 2
    extra_args: "-G 4096"
```

This would be equivalent to the shell command:

```sh
mkfs.ext4 -G 4096 /dev/sda3
```

The purpose of this is to allow larger files to be grouped contiguously to reduce fragmentation and thus actual size consumption on an expanding virtual disk. If you choose not to use ext4, you're on your own. You should likely stick to Microsoft's recommendations unless you know what you are doing.

## LVM and Raid

Microsoft recommends not using LVM and RAID on OS disks, but it can be used on data disks.

## Static MAC address

If you are going to use failover clustering, Microsoft recommends assigning static MAC addresses to your network adapters. Note that the `Default Switch` built into `Hyper-V` is configured to use a dynamic MAC address.

## Kernel parameters

This is specifically a recommendation for deploying to Azure, as it will assist their techs in debugging issues, but it may be helpful in a homelab. Set the following to send console messages to the first serial port:

```
console=ttyS0,115200n8 earlyprintk=ttyS0,115200 rootdelay=300
```

Do not set the following:

```
rhgb quiet crashkernel=auto
```

## Swap

Microsoft recommends not creating a swap partition on the OS disk because Azure will provision a swap partition on a temporary disk automatically via the `Azure Linux Agent`, which is effectively their own version of `cloud-init`. You can try to mimic this in `cloud-init` directly by attaching a temporary disk to be used as swap each time you deploy a VM, giving it a single partition of type `Linux Swap` and running `mkswap` and `swapon` against it, or use a swap file instead, or just go ahead and create a static partition table with swap built into the same disk as the OS. Just be aware this results in a less portable disk with a swap that cannot easily be resized.

## Support for Azure deployment

Note that Azure does support `cloud-init`. See [Using cloud-init](https://docs.microsoft.com/en-us/azure/virtual-machines/linux/using-cloud-init) for details.

The only hard requirement I know of to deploy to Azure is that you need to deploy a .vhd disk, not a .vhdx, which means it needs to be statically sized, not dynamic. Azure will instead allow you to attach dynamic block storage for data.
