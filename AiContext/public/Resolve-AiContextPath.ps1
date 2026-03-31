<#
.SYNOPSIS
Resolves the project and global AI context paths.

.DESCRIPTION
Walks upward from the supplied project folder until it finds the
expected `ai/projects/<project>` structure, then resolves the matching
project root and global context folder.

.PARAMETER ProjectFolder
The current project folder or any child path within the project.

.PARAMETER GlobalFolder
Overrides the default global context folder.

.EXAMPLE
Resolve-AiContextPath -ProjectFolder .

.OUTPUTS
System.Management.Automation.PSCustomObject
#>
function Resolve-AiContextPath {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$ProjectFolder,

        [Parameter()]
        [string]$GlobalFolder
    )

    if ([string]::IsNullOrWhiteSpace($ProjectFolder)) {
        $ProjectFolder = (Get-Location).Path
    }

    $current = [System.IO.DirectoryInfo]::new(
        [System.IO.Path]::GetFullPath($ProjectFolder)
    )

    $projectRoot = $null
    $aiRoot = $null

    # Walk upward until we find /ai/projects/<project>
    while ($current -ne $null) {

        if ($current.Parent -and $current.Parent.Name -eq 'projects') {
            # Found project root
            $projectRoot = $current
            $aiRoot = $current.Parent.Parent
            break
        }

        $current = $current.Parent
    }

    if (-not $projectRoot) {
        throw @"
Could not resolve project root.

Expected to be inside:
ai/projects/<project>

Current path:
$ProjectFolder
"@
    }

    if (-not $aiRoot) {
        throw "Failed to resolve ai root from project structure."
    }

    $resolvedProjectFolder = $projectRoot.FullName

    if ([string]::IsNullOrWhiteSpace($GlobalFolder)) {
        $GlobalFolder = Join-Path -Path $aiRoot.FullName -ChildPath 'global'
    }

    $resolvedGlobalFolder = [System.IO.Path]::GetFullPath($GlobalFolder)

    if (-not (Test-Path -LiteralPath $resolvedGlobalFolder -PathType Container)) {
        throw @"
Global folder not found.

Expected:
$resolvedGlobalFolder

Ensure ai/global exists.
"@
    }

    [pscustomobject]@{
        ProjectFolder = $resolvedProjectFolder
        GlobalFolder  = $resolvedGlobalFolder
        AiRoot        = $aiRoot.FullName
    }
}
