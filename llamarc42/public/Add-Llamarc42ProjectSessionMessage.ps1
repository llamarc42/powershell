<#
.SYNOPSIS
Adds a message to an Ollama project session transcript.

.DESCRIPTION
Appends a user, assistant, or system message to the session's
`messages.jsonl` file, updates the session metadata, and returns the
message that was written.

.PARAMETER Session
The session object to update. Accepts pipeline input.

.PARAMETER Path
The path to the session folder.

.PARAMETER Role
The message role to record.

.PARAMETER Content
The message body to append.

.EXAMPLE
Get-Llamarc42ProjectSession | Add-Llamarc42ProjectSessionMessage -Role user -Content 'Summarize the ADRs.'

.OUTPUTS
Llamarc42.ProjectSessionMessage
#>
function Add-Llamarc42ProjectSessionMessage {
    [CmdletBinding(DefaultParameterSetName = 'BySession')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'BySession', ValueFromPipeline)]
        [psobject]$Session,

        [Parameter(Mandatory, ParameterSetName = 'ByPath')]
        [string]$Path,

        [Parameter(Mandatory)]
        [ValidateSet('user', 'assistant', 'system')]
        [string]$Role,

        [Parameter(Mandatory)]
        [string]$Content
    )

    if ([string]::IsNullOrWhiteSpace($Content)) {
        throw 'Content cannot be null, empty, or whitespace.'
    }

    $resolvedSession = if ($PSCmdlet.ParameterSetName -eq 'ByPath') {
        Resolve-SessionObject -Path $Path
    }
    else {
        Resolve-SessionObject -Session $Session
    }

    if (-not (Test-Path -LiteralPath $resolvedSession.SessionFolder -PathType Container)) {
        throw "Session folder not found: $($resolvedSession.SessionFolder)"
    }

    if (-not (Test-Path -LiteralPath $resolvedSession.MessagesFile -PathType Leaf)) {
        $null = New-Item -Path $resolvedSession.MessagesFile -ItemType File -Force
    }

    $timestamp = (Get-Date).ToString('o')

    $message = [ordered]@{
        role      = $Role
        timestamp = $timestamp
        content   = $Content
    }

    $jsonLine = $message | ConvertTo-Json -Compress -Depth 5
    Add-Content -LiteralPath $resolvedSession.MessagesFile -Value $jsonLine -Encoding UTF8

    $resolvedSession.MessageCount = [int]$resolvedSession.MessageCount + 1
    $resolvedSession.Updated = $timestamp

    Save-SessionMetadata -Session $resolvedSession

    [pscustomobject]@{
        PSTypeName = 'Llamarc42.ProjectSessionMessage'
        SessionId  = $resolvedSession.Id
        Role       = $Role
        Timestamp  = $timestamp
        Content    = $Content
    }
}
