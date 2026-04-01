<#
.SYNOPSIS
Finds artifact files that match a relative path pattern.

.DESCRIPTION
Compares each candidate file's artifact-relative path to the supplied
PowerShell wildcard pattern and returns the matching files with their
relative paths.

.PARAMETER Files
The candidate artifact files to evaluate.

.PARAMETER RootPath
The root path used to compute artifact-relative file paths.

.PARAMETER Pattern
The wildcard pattern to match against relative paths.

.EXAMPLE
Find-ArtifactMatches -Files $projectFiles -RootPath $paths.ProjectFolder -Pattern 'docs/*.md'

.OUTPUTS
System.Management.Automation.PSCustomObject
#>
function Find-ArtifactMatches {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.IO.FileInfo[]]$Files,

        [Parameter(Mandatory)]
        [string]$RootPath,

        [Parameter(Mandatory)]
        [string]$Pattern
    )

    $normalizedPattern = ($Pattern -replace '\\', '/').TrimStart('/')

    foreach ($file in $Files) {
        $relativePath = Get-ArtifactRelativePath -RootPath $RootPath -FullPath $file.FullName

        if ($relativePath -like $normalizedPattern) {
            [pscustomobject]@{
                File         = $file
                RelativePath = $relativePath
            }
        }
    }
}
