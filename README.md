# Hyper-V Builder for Linux

# Introduction



# Usage

```powershell
hvb build
hvb start
hvb ssh
```

## Build a new cloud image

Module cmdlets must be run from an Administrator console. Alternatively, you can add your user to the `Hyper-V Administrators` local group. To do this, go to `Start > Windows Administrative Tools > Computer Management` and open the `Computer Management` console. Go to `Computer Management (Local) > System Tools > Local Users and Groups > Groups` in the console tree, then select the `Hyper-V Administrators` group to edit, and add your user to this group. You will need to log out and back in for the change to take effect.

To build a new image, set parameters in a build config file. This can be passed to the script directly using the `-Config` parameter. If no `-Config` parameter is passed, the current directory will be scanned for any json files that conform to the expected schema, and the first one found will be assumed to be the config.

## Start and connect to your guest

# Installation

# Dependencies

## Required

* `Hyper-V`
  * See [Install Hyper-V on Windows 10](https://docs.microsoft.com/en-us/virtualization/hyper-v-on-windows/quick-start/enable-hyper-v)

## Optional

* [Microsoft Assessment and Deployment Kit](https://go.microsoft.com/fwlink/?linkid=2120254).
* `OpenSSH`
  * See [Install OpenSSH using Windows Settings](https://docs.microsoft.com/en-us/windows-server/administration/openssh/openssh_install_firstuse)

Microsoft Assessment and Deployment Kit is required to create a `cloud-init` iso to mount to the VM along with installation media iso as a `NoCloud` datasource to automate an unattended install. `OpenSSH` is required to generate ssh key pairs in order to connect to the VM once the OS is installed.

# Contributors

* The token replacement implementation is based on Craig Buchanan's [PSTokens](https://github.com/craibuc/PsTokens) module. The only change is allowing whitespace inside of the token delimiters. `PowerShell` does have basic package management capabilities (see [Getting Started with PowerShell Gallery](https://docs.microsoft.com/en-us/powershell/scripting/gallery/getting-started)), but in the interest of possibly extending this into a more fully-featured templating engine, I chose to vendor the module rather than depend on it.
* Adam Acosta

# Additional Credits

Some inspiration is taken from https://gist.github.com/PulseBright/3a6fe586821a2ff84cd494eb897d3813 and https://github.com/MicrosoftDocs/Virtualization-Documentation/blob/master/hyperv-samples/benarm-powershell/Ubuntu-VM-Build/BaseUbuntuBuild.ps1.

Most of the information used in development came from the Arch Wiki page [Install Arch Linux via SSH](https://wiki.archlinux.org/title/Install_Arch_Linux_via_SSH), the `cloud-init` [module documentation](https://cloudinit.readthedocs.io/en/latest/topics/modules.html), and documentation for the `PowerShell` module [Hyper-V](https://docs.microsoft.com/en-us/powershell/module/hyper-v/?view=windowsserver2019-ps).