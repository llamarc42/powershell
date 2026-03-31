Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:ModuleRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

# Dot-source Private first
$private = Join-Path $script:ModuleRoot 'Private'
if (Test-Path $private)
{
    Get-ChildItem -Path $private -Filter '*.ps1' | Sort-Object FullName | ForEach-Object {
        . $_.FullName
    }
}

# Then Public
$public = Join-Path $script:ModuleRoot 'Public'
if (Test-Path $public)
{
    Get-ChildItem -Path $public -Filter '*.ps1' | Sort-Object FullName | ForEach-Object {
        . $_.FullName
    }
}

# Export public functions (based on Public folder)
$publicFunctions = @()
if (Test-Path $public)
{
    $publicFunctions = Get-ChildItem -Path $public -Filter '*.ps1' | ForEach-Object { $_.BaseName }
}
Export-ModuleMember -Function $publicFunctions