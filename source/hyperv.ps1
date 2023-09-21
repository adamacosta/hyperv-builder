function Add-BootDisk {
    param(
        [String] $vmname,
        [String] $bootiso
    )

    Add-VMDvdDrive -VMName $vmname -Path $bootiso
    $vmdvddrive = Get-VMDvdDrive $vmname
    Set-VMFirmware $vmname -FirstBootDevice $vmdvddrive
    Set-VMFirmware $vmname -EnableSecureBoot Off
}

function New-VMWithHardDrive {
    param(
        [String] $name,
        [String] $path,
        [Int] $startupMemory,
        [String] $minMemory,
        [String] $maxMemory,
        [String] $networkSwitch,
        [Int] $cpus,
        [String] $diskSize,
        [String] $blockSize
    )

    $vhd = "${name}.vhdx"
    New-VM –Name $name -Generation 2 -Path $path –MemoryStartupBytes $startupMemory -Switch $networkSwitch
    Set-VMProcessor –VMName $name –Count $cpus
    Set-VMMemory -VMName $name -DynamicMemoryEnabled $True -MinimumBytes $minMemory -MaximumBytes $maxMemory
    New-Vhd -Path "${path}\${vhd}" -Dynamic -SizeBytes $diskSize -BlocksizeBytes $blockSize
    Add-VMHardDiskDrive -VMName $name -Path "${path}\${vhd}"
}

function Update-Guest {
    param(
        [String] $vmname,
        [String] $sshUser,
        [String] $keyfile,
        [String] $scriptDir
    )

    # Wait on ip to become available before completing configuration via ssh
    $ip = (Get-VMNetworkAdapter -VMName $vmname).IPAddresses[0]
    while ([String]::IsNullOrEmpty($ip)) {
        Write-Host "Waiting for ${vmname} to connect to network"
        Start-Sleep -s 10
        $ip = (Get-VMNetworkAdapter -VMName $vmname).IPAddresses[0]
    }

    # Copy and run installer scripts once we have the ip
    scp -q -i "${keyfile}" -o StrictHostKeyChecking=no ./"${scriptDir}"/* "${sshUser}@${ip}:~"
    ssh -q -tt -i "${keyfile}" -o StrictHostKeyChecking=no "${sshUser}@${ip}" "chmod +x *.sh; for sc in `$(find . -type f -executable | sort); do . $sc; done"
}

function Update-VMDiskState {
    param(
        [String] $vmname
    )

    while ((Get-VM $vmname).State -eq 'Running') {
        Write-Host "Waiting for cloud-init to complete"
        Start-Sleep -s 10
    }

    Write-Host "Detaching installation media and updating boot order"

    Remove-VMDvdDrive -VMDvdDrive (Get-VMDvdDrive $vmname)
    $hdd = Get-VMHardDiskDrive $vmname
    Set-VMFirmware $vmname -FirstBootDevice $hdd
}