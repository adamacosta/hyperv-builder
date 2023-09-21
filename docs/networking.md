# Networking

During OS installation when booting from the installation media, the VM will always use the 'Default Switch' that comes provided by `Hyper-V`. This switch uses NAT to provide network access, which may not be what you want when deploying the VM. If you wish to attach your VM to the LAN directly, you can create a bridged virtual switch by setting the property `network_switch` to an external virtual switch. If it doesn't exist, it will be created and attached to whatever host interface is specified in the property `netadapter`. This will likely either be 'Ethernet' if you have a wired connection or 'Wi-Fi' if your connection is wireless (numbered if you have multiple interfaces of one type). To get a list of available network adapters and their connection status, run the following:

```powershell
Get-NetAdapter | Select Name,Status
```

If status is 'Up' and the adapter is not virtual, then it is connected to your LAN. If you're still not sure, you can run:

```powershell
Get-NetIPAddress | Where { ($_.InterfaceAlias -eq <interface>) -and ($_.AddressFamily -eq 'IPv4') }
```

If the address assigned to the interface starts with `192.168` and `SuffixOrigin` is `Dhcp`, then this is probably the interface you want. If you're using a VPN tunnel, you may have one that starts with `169.254` with `SuffixOrigin` of `Link`. Note that the link-local range is also used by `Avahi`/`Bonjour`/`zeroconf`. I have not attempted to use mDNS service discovery on Windows, but do believe it is available as of Windows 10.