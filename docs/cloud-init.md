# cloud-init

## Official Documentation

The official documentation of the `cloud-init` project is found on read the docs at [cloud-init Documentation](https://cloudinit.readthedocs.io/en/latest/). The [Cloud config examples](https://cloudinit.readthedocs.io/en/latest/topics/examples.html) are particularly useful.

## Caveats

### Module order and data sources

Documentation for the various `scripts` modules say they will run anything executable found in the "datasource" in the directories `scripts/per-boot`, `scripts/per-instance`, and `scripts/per-once`. If you look at the source code for the various `DataSource` subclass implementations, however, you can see this is not the case. The simplest implementation is the `NoCloud` datasource. The `DataSource` parent class always calls a `get_data` method, which in turn delegates to the `_get_data` method of the implementation subclass. You can see the implementation for `NoCloud` [here](https://github.com/canonical/cloud-init/blob/master/cloudinit/sources/DataSourceNoCloud.py#L51). As of 10 May 2021, it is this:

```python
    def _get_data(self):
        defaults = {
            "instance-id": "nocloud",
            "dsmode": self.dsmode,
        }

        found = []
        mydata = {'meta-data': {}, 'user-data': "", 'vendor-data': "",
                  'network-config': None}

        try:
            # Parse the system serial label from dmi. If not empty, try parsing
            # like the commandline
            md = {}
            serial = dmi.read_dmi_data('system-serial-number')
            if serial and load_cmdline_data(md, serial):
                found.append("dmi")
                mydata = _merge_new_seed(mydata, {'meta-data': md})
        except Exception:
            util.logexc(LOG, "Unable to parse dmi data")
            return False

        try:
            # Parse the kernel command line, getting data passed in
            md = {}
            if load_cmdline_data(md):
                found.append("cmdline")
                mydata = _merge_new_seed(mydata, {'meta-data': md})
        except Exception:
            util.logexc(LOG, "Unable to parse command line data")
            return False

        # Check to see if the seed dir has data.
        pp2d_kwargs = {'required': ['user-data', 'meta-data'],
                       'optional': ['vendor-data', 'network-config']}

        for path in self.seed_dirs:
            try:
                seeded = util.pathprefix2dict(path, **pp2d_kwargs)
                found.append(path)
                LOG.debug("Using seeded data from %s", path)
                mydata = _merge_new_seed(mydata, seeded)
                break
            except ValueError:
                pass

        # If the datasource config had a 'seedfrom' entry, then that takes
        # precedence over a 'seedfrom' that was found in a filesystem
        # but not over external media
        if self.ds_cfg.get('seedfrom'):
            found.append("ds_config_seedfrom")
            mydata['meta-data']["seedfrom"] = self.ds_cfg['seedfrom']

        # fields appropriately named can also just come from the datasource
        # config (ie, 'user-data', 'meta-data', 'vendor-data' there)
        if 'user-data' in self.ds_cfg and 'meta-data' in self.ds_cfg:
            mydata = _merge_new_seed(mydata, self.ds_cfg)
            found.append("ds_config")

        def _pp2d_callback(mp, data):
            return util.pathprefix2dict(mp, **data)

        label = self.ds_cfg.get('fs_label', "cidata")
        if label is not None:
            for dev in self._get_devices(label):
                try:
                    LOG.debug("Attempting to use data from %s", dev)

                    try:
                        seeded = util.mount_cb(dev, _pp2d_callback,
                                               pp2d_kwargs)
                    except ValueError:
                        LOG.warning("device %s with label=%s not a "
                                    "valid seed.", dev, label)
                        continue

                    mydata = _merge_new_seed(mydata, seeded)

                    LOG.debug("Using data from %s", dev)
                    found.append(dev)
                    break
                except OSError as e:
                    if e.errno != errno.ENOENT:
                        raise
                except util.MountFailedError:
                    util.logexc(LOG, "Failed to mount %s when looking for "
                                "data", dev)

        # There was no indication on kernel cmdline or data
        # in the seeddir suggesting this handler should be used.
        if len(found) == 0:
            return False

        # The special argument "seedfrom" indicates we should
        # attempt to seed the userdata / metadata from its value
        # its primarily value is in allowing the user to type less
        # on the command line, ie: ds=nocloud;s=http://bit.ly/abcdefg
        if "seedfrom" in mydata['meta-data']:
            seedfrom = mydata['meta-data']["seedfrom"]
            seedfound = False
            for proto in self.supported_seed_starts:
                if seedfrom.startswith(proto):
                    seedfound = proto
                    break
            if not seedfound:
                LOG.debug("Seed from %s not supported by %s", seedfrom, self)
                return False

            # This could throw errors, but the user told us to do it
            # so if errors are raised, let them raise
            (md_seed, ud, vd) = util.read_seeded(seedfrom, timeout=None)
            LOG.debug("Using seeded cache data from %s", seedfrom)

            # Values in the command line override those from the seed
            mydata['meta-data'] = util.mergemanydict([mydata['meta-data'],
                                                      md_seed])
            mydata['user-data'] = ud
            mydata['vendor-data'] = vd
            found.append(seedfrom)

        # Now that we have exhausted any other places merge in the defaults
        mydata['meta-data'] = util.mergemanydict([mydata['meta-data'],
                                                  defaults])

        self.dsmode = self._determine_dsmode(
            [mydata['meta-data'].get('dsmode')])

        if self.dsmode == sources.DSMODE_DISABLED:
            LOG.debug("%s: not claiming datasource, dsmode=%s", self,
                      self.dsmode)
            return False

        self.seed = ",".join(found)
        self.metadata = mydata['meta-data']
        self.userdata_raw = mydata['user-data']
        self.vendordata_raw = mydata['vendor-data']
        self._network_config = mydata['network-config']
        self._network_eni = mydata['meta-data'].get('network-interfaces')
        return True
```

Only `meta-data`, `user-data`, `vendor-data`, and `network-config` are ever read from the datasource. Any other files in the same directory will be ignored, so you cannot simply add a `scripts` directory to the iso to have those be run. This is why the `write_files` module is used instead, which reads files from the `/var/lib/cloud/scripts` subdirectories. We use `per-once` since the installation media should only be booted from once and changes made to it will not be persisted between boots anyway.

### cloud-init config

It is possible to change the `cloud-init` config, but for installation media, this is only possible if you create your own installation media, for instance, using the `archiso` tool. If you use a vendor-provided installer, you will get the default configuration, which you can see with the `cloud-init` source code at [cloud.cfg.tmpl](https://github.com/canonical/cloud-init/blob/master/config/cloud.cfg.tmpl). We can see the `write_files` module is run during the `init` stage and the various `scripts` modules are all run during the `final` stage, so we can use that fact to write out scripts to execute before `cloud-init` looks for scripts to execute, allowing us to modify the installation media after boot but before any installation commands are run.

Note that this is a template and it is rendered based on which distro is detected. For Arch Linux as of 10 May 2021, the rendered config (found at `/etc/cloud/cloud.cfg`) is this:

```yaml
# The top level settings are used as module
# and system configuration.

# A set of users which may be applied and/or used by various modules
# when a 'default' entry is found it will reference the 'default_user'
# from the distro configuration specified below
users:
   - default

# If this is set, 'root' will not be able to ssh in and they
# will get a message to login instead as the default $user
disable_root: true

# This will cause the set+update hostname module to not operate (if true)
preserve_hostname: false

# Example datasource config
# datasource:
#    Ec2:
#      metadata_urls: [ 'blah.com' ]
#      timeout: 5 # (defaults to 50 seconds)
#      max_wait: 10 # (defaults to 120 seconds)

# The modules that run in the 'init' stage
cloud_init_modules:
 - migrator
 - seed_random
 - bootcmd
 - write-files
 - growpart
 - resizefs
 - disk_setup
 - mounts
 - set_hostname
 - update_hostname
 - update_etc_hosts
 - ca-certs
 - rsyslog
 - users-groups
 - ssh

# The modules that run in the 'config' stage
cloud_config_modules:
 - ssh-import-id
 - locale
 - set-passwords
  - ntp
 - timezone
 - disable-ec2-metadata
 - runcmd

# The modules that run in the 'final' stage
cloud_final_modules:
 - package-update-upgrade-install
 - puppet
 - chef
 - mcollective
 - salt-minion
 - reset_rmc
 - refresh_rmc_and_interface
 - rightscale_userdata
 - scripts-vendor
 - scripts-per-once
 - scripts-per-boot
 - scripts-per-instance
 - scripts-user
 - ssh-authkey-fingerprints
 - keys-to-console
 - phone-home
 - final-message
 - power-state-change

# System and/or distro specific settings
# (not accessible to handlers/transforms)
system_info:
   # This will affect which distro class gets used
   distro: arch
   # Default user name + that default users groups (if added/used)
   default_user:
     name: arch
     lock_passwd: True
     gecos: arch Cloud User
     groups: [wheel, users]
     sudo: ["ALL=(ALL) NOPASSWD:ALL"]
     shell: /bin/bash
   # Other config here will be given to the distro class and/or path classes
   paths:
      cloud_dir: /var/lib/cloud/
      templates_dir: /etc/cloud/templates/
   ssh_svcname: sshd
```

These are the modules that will run and the order in which they will run. Most of these modules will not do anything unless a `DataSource` is provided at boot time, with the exception of the `users-groups` module, since it is configured in the default config. The way `cloud-init` works is by taking this default config and merging it with anything found in `user-data` in a `DataSource` that it is configured to check. The default config serves as the configuration for the `None` datasource, so modules in here will only run if `cloud-init` is configured to use that datasource. This is why the example unattended Arch installer adds the following to `/etc/cloud/cloud.cfg.d/10-datasource.cfg`:

```yaml
datasource_list: [ NoCloud, None ]
```

This will cause `cloud-init` to first read any disks that are formatted as `iso9660` or `vFAT` with a `cidata` or `CIDATA` label and read config from a file named `user-data` with a `#cloud-config` block found on this disk, and then read the default config itself. The way in which config is merged preferences the first read source, so any module configuration found in `NoCloud` will override configuration from `None`.

# NoCloud DataSource resolution

To understand this best, it is again instructive to look at the source code. From the block above in the `DataSourceNoCloud._get_data` method, we see the lines:

```python
        label = self.ds_cfg.get('fs_label', "cidata")
        if label is not None:
            for dev in self._get_devices(label):
                try:
                    LOG.debug("Attempting to use data from %s", dev)

                    try:
                        seeded = util.mount_cb(dev, _pp2d_callback,
                                               pp2d_kwargs)
                    except ValueError:
                        LOG.warning("device %s with label=%s not a "
                                    "valid seed.", dev, label)
                        continue

                    mydata = _merge_new_seed(mydata, seeded)

                    LOG.debug("Using data from %s", dev)
                    found.append(dev)
                    break
                except OSError as e:
                    if e.errno != errno.ENOENT:
                        raise
                except util.MountFailedError:
                    util.logexc(LOG, "Failed to mount %s when looking for "
                                "data", dev)
```

Looking at the implementation of the `_get_devices` method shows this:

```python
    def _get_devices(self, label):
        fslist = util.find_devs_with("TYPE=vfat")
        fslist.extend(util.find_devs_with("TYPE=iso9660"))

        label_list = util.find_devs_with("LABEL=%s" % label.upper())
        label_list.extend(util.find_devs_with("LABEL=%s" % label.lower()))
        label_list.extend(util.find_devs_with("LABEL_FATBOOT=%s" % label))

        devlist = list(set(fslist) & set(label_list))
        devlist.sort(reverse=True)
        return devlist
```

In turn, the code for `util.find_devs_with` is found [here](https://github.com/canonical/cloud-init/blob/master/cloudinit/util.py#L1198):

```python
def find_devs_with(criteria=None, oformat='device',
                   tag=None, no_cache=False, path=None):
    """
    find devices matching given criteria (via blkid)
    criteria can be *one* of:
      TYPE=<filesystem>
      LABEL=<label>
      UUID=<uuid>
    """
# ...
# omitted BSD-specific logic
# ...

    blk_id_cmd = ['blkid']
    options = []
    if criteria:
        # Search for block devices with tokens named NAME that
        # have the value 'value' and display any devices which are found.
        # Common values for NAME include  TYPE, LABEL, and UUID.
        # If there are no devices specified on the command line,
        # all block devices will be searched; otherwise,
        # only search the devices specified by the user.
        options.append("-t%s" % (criteria))
    if tag:
        # For each (specified) device, show only the tags that match tag.
        options.append("-s%s" % (tag))
    if no_cache:
        # If you want to start with a clean cache
        # (i.e. don't report devices previously scanned
        # but not necessarily available at this time), specify /dev/null.
        options.extend(["-c", "/dev/null"])
    if oformat:
        # Display blkid's output using the specified format.
        # The format parameter may be:
        # full, value, list, device, udev, export
        options.append('-o%s' % (oformat))
    if path:
        options.append(path)
    cmd = blk_id_cmd + options
    # See man blkid for why 2 is added
    try:
        (out, _err) = subp.subp(cmd, rcs=[0, 2])
    except subp.ProcessExecutionError as e:
        if e.errno == ENOENT:
            # blkid not found...
            out = ""
        else:
            raise
    entries = []
    for line in out.splitlines():
        line = line.strip()
        if line:
            entries.append(line)
    return entries

```

`subp.subp` is a simple wrapper around the Python stdlib method `subprocess.Popen`, so this is just calling the command `blkid` like so:

```bash
blkid -o device -t "TYPE=vfat"
blkid -o device -t "TYPE=iso9660"
blkid -o device -t "LABEL=cidata"
blkid -o device -t "LABEL=CIDATA"
blkid -o device -t "LABEL_FATBOOT=cidata"
```

The results of all of these calls are reduced to a set and then sorted. `cloud-init` will mount each of the devices found if they are not already mounted, and then read any files named `meta-data`, `user-data`, `network-config`, and `vendor-data`.

This should provide a pretty clear overview of exactly what is happening under the hood. We provides defaults via the `None` datasource in the `/etc/cloud/cloud.cfg` and `/etc/cloud/cloud.cfg.d/*.cfg` files, and then provide overrides or additional module configuration via the `NoCloud` datasource in a file named `user-data` on a DVD mounted to a VM before booting that is given the label `cidata`. The installation media itself is not configured to use the `None` datasource, so `cloud-init` will do nothing unless an actual datasource is found. It will search through all of the common cloud providers, attempting to hit their custom-defined link-local IPs, and then check the `NoCloud` source. Thus, another way to do this would be to mock out a metadata server from a cloud provider by running an http server at their expected link-local IP.
