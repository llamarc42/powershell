<#
.SYNOPSIS
Saves session metadata to disk.

.DESCRIPTION
Serializes the current session state and writes it to the session's
`session.json` file.

.PARAMETER Session
The session object to persist.

.EXAMPLE
Save-SessionMetadata -Session $session
#>
function Save-SessionMetadata {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject]$Session
    )

    $metadata = [ordered]@{
        id                 = $Session.Id
        name               = $Session.Name
        title              = $Session.Title
        projectName        = $Session.ProjectName
        projectFolder      = $Session.ProjectFolder
        globalFolder       = $Session.GlobalFolder
        sessionFolder      = $Session.SessionFolder
        model              = $Session.Model
        created            = $Session.Created
        updated            = $Session.Updated
        artifactExtensions = @($Session.ArtifactExtensions)
        artifactFiles      = @($Session.ArtifactFiles)
        messageCount       = $Session.MessageCount
        rollingSummary     = $Session.RollingSummary
        tags               = @($Session.Tags)
    }

    $json = $metadata | ConvertTo-Json -Depth 10
    Set-Content -LiteralPath $Session.SessionFile -Value $json -Encoding UTF8
}
