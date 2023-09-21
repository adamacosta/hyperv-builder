function New-CloudInitIso {
    [CmdletBinding()]
    param(
        [String] $vmname,
        [String] $path,
        [String] $isoName,
        [String] $metadataTmpl = '',
        [String] $userdataTmpl,
        [HashTable] $metadataTokens = @{},
        [HashTable] $userdataTokens = @{},
        [String] $oscdimgPath,
        [String[]] $includes = @(),
        [HashTable] $includeTokens = @{}
    )

    $metadata = Merge-Tokens -Template $metadataTmpl -Tokens $metadataTokens
    Write-Verbose "Rendered cloud-init metadata:"
    Write-Verbose $metadata

    $userdata = Merge-Tokens -Template $userdataTmpl -Tokens $userdataTokens
    if ($includes.Count -gt 0) {
        $userdata += "write_files:`n"
        foreach ($inc in $includes) {
            if ($inc.Endswith(".tmpl")) {
                $content = Merge-Tokens -Template ((Get-Content $inc) -replace "^","    " | Out-String) `
                                        -Tokens $includeTokens
                $sc = $inc -replace ".tmpl", ""
            } else {
                $content = ((Get-Content $inc) -replace "^","    " | Out-String)
                $sc = $inc
            }
            $sc = $sc | Split-Path -Leaf
            $userdata += "- content: |`n"
            $userdata += "${content}`n"
            $userdata += "  path: /var/lib/cloud/scripts/per-once/${sc}`n"
            $userdata += "  permissions: '0755'`n"
        }
    }
    Write-Verbose "Rendered cloud-init userdata:"
    Write-Verbose $userdata

    # Output meta and user data to files
    if (-not (Test-Path "${path}\raw")) {
        New-Item -ItemType directory "${path}\raw" | Out-Null
    }
    Set-Content "${path}\raw\meta-data" ([byte[]][char[]] "${metadata}") -AsByteStream
    Set-Content "${path}\raw\user-data" ([byte[]][char[]] "${userdata}") -AsByteStream

    # Create cloud-init iso
    & $oscdimgPath "${path}\raw" "${path}\${isoName}" -j2 -lcidata | Out-Null
    Remove-Item -Force -Recurse "${path}\raw"
    Write-Host "Wrote cloud-init iso to ${path}\${isoName}"
}