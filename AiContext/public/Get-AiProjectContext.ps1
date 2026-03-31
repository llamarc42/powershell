<#
.SYNOPSIS
Builds combined global and project AI context.

.DESCRIPTION
Resolves the project and global context folders, gathers matching files
from each, reads their content, and returns a single object containing
the file lists and combined text payload.

.PARAMETER ProjectFolder
The current project folder or any child path within the project.

.PARAMETER GlobalFolder
The global context folder. When omitted, the module resolves `ai/global`
from the current project structure.

.PARAMETER IncludeExtensions
The file extensions to include when gathering context files.

.PARAMETER IncludeFileHeaders
Adds file boundary headers around each file in the combined content.

.EXAMPLE
Get-AiProjectContext -ProjectFolder . -IncludeExtensions '.md', '.txt'

.OUTPUTS
System.Management.Automation.PSCustomObject
#>
function Get-AiProjectContext {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$ProjectFolder,

        [Parameter()]
        [string]$GlobalFolder,

        [Parameter()]
        [string[]]$IncludeExtensions = @('.md', '.txt'),

        [Parameter()]
        [switch]$IncludeFileHeaders
    )

    $paths = Resolve-AiContextPath -ProjectFolder $ProjectFolder -GlobalFolder $GlobalFolder

    $globalFiles = Get-AiContextFiles -Path $paths.GlobalFolder -IncludeExtensions $IncludeExtensions
    $projectFiles = Get-AiContextFiles -Path $paths.ProjectFolder -IncludeExtensions $IncludeExtensions

    $globalContent = Get-AiContextContent `
        -Files $globalFiles `
        -RootPath $paths.GlobalFolder `
        -IncludeHeaders:$IncludeFileHeaders

    $projectContent = Get-AiContextContent `
        -Files $projectFiles `
        -RootPath $paths.ProjectFolder `
        -IncludeHeaders:$IncludeFileHeaders

    $combinedBuilder = New-Object System.Text.StringBuilder

    [void]$combinedBuilder.AppendLine("# GLOBAL CONTEXT")
    [void]$combinedBuilder.AppendLine()
    [void]$combinedBuilder.AppendLine($globalContent)
    [void]$combinedBuilder.AppendLine()
    [void]$combinedBuilder.AppendLine("# PROJECT CONTEXT")
    [void]$combinedBuilder.AppendLine()
    [void]$combinedBuilder.AppendLine($projectContent)

    [pscustomobject]@{
        ProjectFolder   = $paths.ProjectFolder
        GlobalFolder    = $paths.GlobalFolder
        GlobalFiles     = $globalFiles.FullName
        ProjectFiles    = $projectFiles.FullName
        CombinedContent = $combinedBuilder.ToString().Trim()
    }
}
