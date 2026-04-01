<#
.SYNOPSIS
Finds context files in a folder tree.

.DESCRIPTION
Recursively scans a path and returns files whose extensions match the
requested set.

.PARAMETER Path
The root folder to scan.

.PARAMETER IncludeExtensions
The file extensions to include. Values may be passed with or without
the leading period.

.EXAMPLE
Get-Llamarc42Files -Path $paths.ProjectFolder -IncludeExtensions '.md', '.txt'

.OUTPUTS
System.IO.FileInfo
#>
function Get-Llamarc42Files {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter()]
        [string[]]$IncludeExtensions = @('.md', '.txt')
    )

    $normalizedExtensions = $IncludeExtensions | ForEach-Object {
        if ($_.StartsWith('.')) { $_.ToLowerInvariant() } else { ".$_".ToLowerInvariant() }
    }

    Get-ChildItem -LiteralPath $Path -Recurse -File | Where-Object {
        $normalizedExtensions -contains $_.Extension.ToLowerInvariant()
    } | Sort-Object FullName
}
