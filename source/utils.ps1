function Connect-ToGuest {
    param(
        [Parameter(Position=0)]
        [String] $VMName,
        [String] $CacheDir = ".\.cache\${VMName}",
        [String] $SshUser = "${vmname}"
    )

    $ip = (Get-VMNetworkAdapter -VMName $vmname).IPAddresses[0]
    while ([String]::IsNullOrEmpty($ip)) {
        Write-Host "Waiting for ${vmname} to connect to network"
        Start-Sleep -s 5
        $ip = (Get-VMNetworkAdapter -VMName $vmname).IPAddresses[0]
    }

    ssh -q -tt -i "${CacheDir}\${VMName}\id_rsa" -o StrictHostKeyChecking=no "${SshUser}@${ip}"
}

function Get-BootIso {
    param(
        [String] $Source
    )

    try {
        $iso_uri = [Uri]$Source
        if ($iso_uri.IsFile) {
            $boot_iso = $iso_uri.LocalPath
        } else {
            $iso_file = "$($props.cache_dir)\isos\$(Split-Path $iso_uri.LocalPath -Leaf)"
            if (-not (Test-Path $iso_file)) {
                if (-not (Test-Path ".\.cache\${vmname}")) {
                    New-Item -ItemType Directory -Path "$($props.cache_dir)\isos"
                }
                Write-Host "Downloading ${iso_uri} to ${iso_file}"
                Invoke-WebRequest -Uri $iso_uri -OutFile $iso_file
            }
            $boot_iso = $iso_file
        }
        $boot_iso
    } catch {
        Write-Error $_
        throw "Failed to obtain iso ${iso_uri}"
    }
}

function Merge-Tokens() {
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [AllowEmptyString()]
        [String] $Template,

        [Parameter(Mandatory)]
        [HashTable] $Tokens,

        [Parameter()]
        [String[]] $Delimiter = @('{{', '}}')
    )

    begin {}
    process {
        try {
            if ($Delimiter.Count -eq 1) {
                $Front, $Rear = $Delimiter[0], $Delimiter[0]
            } elseif ($Delimiter.Count -eq 2) {
                $Front, $Rear = $Delimiter[0], $Delimiter[1]
            } else {
                throw "Invalid delimiters: $($Delimiter -join ',')"
            }

            [regex]::Replace($Template, "$Front\s*(?<tokenName>[\w\.]+)\s*$Rear", {
                # {{ TOKEN }}
                param($match)

                $tokenName = $match.Groups['tokenName'].Value
                Write-Debug "tokenName: $tokenName"

                $tokenValue = Invoke-Expression "`$Tokens.$tokenName"
                Write-Debug "tokenValue: $tokenValue"

                if ($null -ne $tokenValue) {
                    return $tokenValue
                } else {
                    return $match
                }
            })

        } catch {
            Write-Error $_
            throw "Failed to render template ${Template}"
        }
    }
    end {}
}

function New-SshKeyPair {
    param(
        [Parameter(Position=0, Mandatory=$true)]
        [String] $Path
    )

    Write-Host "Generating ssh key pair"
    $keyFile = "${Path}\id_rsa"
    if (-not (Test-Path $keyFile)) {
        ssh-keygen -q -t rsa -b 4096 -N '""' -f $keyFile
    }
}

function Test-FileCheckSum {
    param(
        [String] $file,
        [String] $checksum,
        [String] $checksumType
    )

    $realSum = (certUtil -hashfile $file $checksumType)[1]
    if (-not ($realSum -eq $checksum)) {
        Write-Error "Bad iso checksum, expected ${checksum}, got ${realSum}"
        Write-Error "Aborting build..."
        throw
    }
}