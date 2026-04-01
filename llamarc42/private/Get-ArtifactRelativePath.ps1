<#
.SYNOPSIS
Gets an artifact path relative to a root folder.

.DESCRIPTION
Normalizes a full file path relative to a root path and returns a
forward-slash-separated relative path. If the file is outside the root,
the file name is returned instead.

.PARAMETER RootPath
The root folder used to calculate the relative path.

.PARAMETER FullPath
The full path to the artifact file.

.EXAMPLE
Get-ArtifactRelativePath -RootPath $paths.ProjectFolder -FullPath $file.FullName

.OUTPUTS
System.String
#>
function Get-ArtifactRelativePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RootPath,

        [Parameter(Mandatory)]
        [string]$FullPath
    )

    $resolvedRoot = [System.IO.Path]::GetFullPath($RootPath).TrimEnd('\', '/')
    $resolvedFile = [System.IO.Path]::GetFullPath($FullPath)

    if ($resolvedFile.StartsWith($resolvedRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $resolvedFile.Substring($resolvedRoot.Length).TrimStart('\', '/') -replace '\\', '/'
    }

    return [System.IO.Path]::GetFileName($resolvedFile)
}
