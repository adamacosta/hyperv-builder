Set-StrictMode -Version Latest

Get-ChildItem $PSScriptRoot\source -Recurse -Filter *.ps1 |
    ? { ! ($_.FullName.Contains(".test.")) } |
    % { . $_.FullName }

New-Alias -Name hvb -Value Invoke-HyperVBuilder
Export-ModuleMember -Alias hvb