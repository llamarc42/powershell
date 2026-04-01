<#
.SYNOPSIS
Creates a normalized session object from metadata.

.DESCRIPTION
Maps persisted session metadata into a consistent `Llamarc42.ProjectSession`
object shape used throughout the module.

.PARAMETER Metadata
The session metadata hashtable to normalize.

.EXAMPLE
New-SessionObject -Metadata $metadata

.OUTPUTS
Llamarc42.ProjectSession
#>
function New-SessionObject {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Metadata
    )

    [pscustomobject]@{
        PSTypeName         = 'Llamarc42.ProjectSession'
        Id                 = $Metadata.id
        Name               = $Metadata.name
        Title              = $Metadata.title
        ProjectName        = $Metadata.projectName
        ProjectFolder      = $Metadata.projectFolder
        GlobalFolder       = $Metadata.globalFolder
        SessionFolder      = $Metadata.sessionFolder
        SessionFile        = (Join-Path $Metadata.sessionFolder 'session.json')
        MessagesFile       = (Join-Path $Metadata.sessionFolder 'messages.jsonl')
        Model              = $Metadata.model
        Created            = $Metadata.created
        Updated            = $Metadata.updated
        ArtifactExtensions = @($Metadata.artifactExtensions)
        ArtifactFiles      = @($Metadata.artifactFiles)
        MessageCount       = $Metadata.messageCount
        RollingSummary     = $Metadata.rollingSummary
        Tags               = @($Metadata.tags)
    }
}
