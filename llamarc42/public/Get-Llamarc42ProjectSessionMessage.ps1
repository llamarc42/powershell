<#
.SYNOPSIS
Gets messages from an Ollama project session.

.DESCRIPTION
Reads the session's `messages.jsonl` transcript and returns either raw
deserialized records or normalized message objects.

.PARAMETER Session
The session object to read. Accepts pipeline input.

.PARAMETER Path
The path to the session folder.

.PARAMETER Tail
Returns only the most recent N messages.

.PARAMETER Raw
Returns the raw deserialized JSON records instead of normalized objects.

.EXAMPLE
Get-Llamarc42ProjectSessionMessage -Path $sessionPath -Tail 20

.OUTPUTS
Llamarc42.ProjectSessionMessage
#>
function Get-Llamarc42ProjectSessionMessage {
    [CmdletBinding(DefaultParameterSetName = 'BySession')]
    param(
        [Parameter(ParameterSetName = 'BySession', ValueFromPipeline)]
        [psobject]$Session,

        [Parameter(ParameterSetName = 'ByPath')]
        [string]$Path,

        [Parameter()]
        [int]$Tail,

        [Parameter()]
        [switch]$Raw
    )

    $resolvedSession = if ($PSCmdlet.ParameterSetName -eq 'ByPath') {
        Resolve-SessionObject -Path $Path
    }
    else {
        Resolve-SessionObject -Session $Session
    }

    if (-not (Test-Path -LiteralPath $resolvedSession.MessagesFile -PathType Leaf)) {
        throw "Messages file not found: $($resolvedSession.MessagesFile)"
    }

    $lines = Get-Content -LiteralPath $resolvedSession.MessagesFile -ErrorAction Stop

    if ($Tail -gt 0) {
        $lines = $lines | Select-Object -Last $Tail
    }

    $messages = foreach ($line in $lines) {
        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }

        $message = $line | ConvertFrom-Json

        if ($Raw) {
            $message
        }
        else {
            [pscustomobject]@{
                PSTypeName = 'Llamarc42.ProjectSessionMessage'
                SessionId  = $resolvedSession.Id
                Role       = $message.role
                Timestamp  = $message.timestamp
                Content    = $message.content
            }
        }
    }

    return @($messages)
}
