function Invoke-HyperVBuilder {
    [CmdletBinding()]
    param(
        [Parameter(Position=0)]
        [ValidateSet('Build', 'Publish', 'Remove', 'Ssh', 'Start', 'Stop')]
        [String] $Action = 'Build',
        [String] $Config = 'hvb.json',
        [String] $Name,
        [Switch] $NoInstall,
        [Switch] $NoVerify,
        [Switch] $NoGenKeys
    )

    trap { "Fatal error" }

    New-Variable -Name NoInstall -Value $NoInstall.IsPresent -Scope Script -Force
    New-Variable -Name NoVerify -Value $NoVerify.IsPresent -Scope Script -Force
    New-Variable -Name GenKeys -Value (-not $NoGenKeys.IsPresent) -Scope Script -Force

    $props = Initialize-Properties $Config

    switch ($Action) {
        'Build' { Build-Image }
        'Publish' { Export-Image }
        'Remove' { Remove-All }
        'Ssh' { Connect-ToGuest $props.vmname -CacheDir $props.cache_dir -SshUser $props.ssh_user }
        'Start' { Start-VM $props.vmname }
        'Stop' { Stop-VM $props.vmname }
    }
}

function Initialize-Properties {
    param(
        [Parameter(Position=0, Mandatory=$true)]
        [String] $Path
    )

    $props = ConvertFrom-Json (Get-Content $Path -Raw) -AsHashtable
    if (-not ($props.ContainsKey('cache_dir'))) {
        $props.cache_dir = ".\.cache"
    }
    New-Variable -Name props -Value $props -Scope Script -Force
    Write-Debug "Parsed build config ${Path}"
    Write-Debug ($props | Out-String)
    $props
}

function Build-Image {
    $boot_iso = Get-BootIso -Source $props.iso_source
    $checksumType, $checksum = ($props.iso_checksum -split ':')[0, 1]
    Test-FileCheckSum -File $boot_iso -Checksum $checksum -ChecksumType $checksumType

    if (-not (Test-Path $props.build_dir)) {
        New-Item -Path $props.build_dir -ItemType Directory
    }

    if ($GenKeys) {
        New-SshKeyPair "$($props.cache_dir)\$($props.vmname)"
        $props.key_file = "$($props.cache_dir)\$($props.vmname)\id_rsa"
        $props.pub_key = Get-Content "${keyFile}.pub"
    }

    $userDataTmpl = $props.cloudinit_userdata
    $userDataTokens = $props.cloudinit_usertokens
    $includeTokens = $props.cloudinit_includetokens
    if (-not ($userDataTokens.ContainsKey('pubKey'))) {
        $userDataTokens.pubKey = $props.pub_key
    }
    if (-not ($includeTokens.ContainsKey('pubKey'))) {
        $includeTokens.pubKey = $props.pub_key
    }
    New-CloudInitIso -Path $props.build_dir -IsoName 'cloudinit.iso' `
        -MetaDataTmpl '' -UserDataTmpl (Get-Content $userDataTmpl | Out-String) `
        -MetaDataTokens @{} -UserDataTokens $userDataTokens `
        -OscDimgPath 'C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe' `
        -Includes $props.cloudinit_includes -IncludeTokens $includeTokens

    # Always use the default switch at first since we don't need to attach to LAN
    New-VMWithHardDrive -Name $props.vmname -Path $props.build_dir -NetworkSwitch $props.network_switch `
        -StartupMemory $props.startup_memory -MinMemory $props.min_memory -MaxMemory $props.max_memory `
        -CPUs $props.cpus -DiskSize $props.disksize -BlockSize $props.blocksize
    Add-BootDisk -VMName $props.vmname -BootIso $boot_iso
    Add-VMDvdDrive -VMName $props.vmname -Path "$($props.build_dir)\cloudinit.iso"

    # cloud-init should shutdown guest
    Start-VM $props.vmname
    Update-VMDiskState $props.vmname

    # Create virtual switch if it doesn't already exist
    if (-not (Get-VMSwitch $props.network_switch 2> $null)) {
        if ($props.netadapter) {
            New-VMSwitch $props.network_switch -NetAdapterName $props.netadapter
        } else {
            New-VMSwitch $props.network_switch -SwitchType Internal
        }
    }

    # Update to use the desired switch
    if ((Get-VMSwitch $props.network_switch) -ne (Get-VMSwitch 'Default Switch')) {
        Get-VM $props.vmname | Get-VMNetworkAdapter | Connect-VMNetworkAdapter `
            -SwitchName $props.network_switch
    }

    # run any provided post-installation scripts
    if (-not ($props.ContainsKey('post_install'))) {
        return
    }
    if ((Test-Path $props.post_install) -and (Get-ChildItem $props.post_install)) {
        Start-VM $props.vmname
        Update-Guest -VMname $props.vmname -SshUser $props.ssh_user -KeyFile $props.key_file `
            -ScriptDir $props.post_install
    }
}

function Export-Image {
    New-Item -Path "$($props.dist_dir)" -ItemType Directory -Force
    Move-Item -Path "$($props.build_dir)\id_rsa" -Destination "$($props.dist_dir)\id_rsa_$($props.vmname)"
    Move-Item -Path "$($props.build_dir)\id_rsa.pub" -Destination "$($props.dist_dir)\id_rsa_$($props.vmname).pub"
    Move-Item -Path "$($props.build_dir)\$($props.vmname)"* -Destination $props.dist_dir
}

function Remove-All {
    if (Get-VM $props.vmname 2> $null) {
        if ((Get-VM $props.vmname).State -eq 'Running') {
            Stop-VM $props.vmname
        }
        Remove-VM -Force $props.vmname
    }
    if (Test-Path $props.build_dir) {
        Remove-Item -Force -Recurse $props.build_dir
    }
}

function Test-Image {
    #
}