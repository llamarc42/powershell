<#
.SYNOPSIS
Updates the rolling summary for a project session.

.DESCRIPTION
Builds a conversation window for the session, summarizes older messages
through the configured Ollama chat endpoint when needed, stores the
result in the session's rolling summary, and persists the updated
session metadata.

.PARAMETER Session
The session object to summarize. Accepts pipeline input.

.PARAMETER Path
The path to the session folder.

.PARAMETER Model
Overrides the model stored on the session for summary generation.

.PARAMETER Endpoint
The Ollama chat API endpoint used for summary generation.

.PARAMETER MaxMessages
The maximum number of recent messages to keep outside the rolling
summary.

.PARAMETER SummarizeAfter
The transcript size threshold after which older messages are summarized.

.PARAMETER TimeoutSec
The request timeout in seconds.

.EXAMPLE
Update-Llamarc42ProjectSessionSummary -Session $session

.EXAMPLE
Update-Llamarc42ProjectSessionSummary -Path $sessionPath -MaxMessages 40 -SummarizeAfter 20

.OUTPUTS
Llamarc42.ProjectSession
#>
function Update-Llamarc42ProjectSessionSummary {
    [CmdletBinding(DefaultParameterSetName = 'BySession')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'BySession', ValueFromPipeline)]
        [psobject]$Session,

        [Parameter(Mandatory, ParameterSetName = 'ByPath')]
        [string]$Path,

        [Parameter()]
        [string]$Model,

        [Parameter()]
        [string]$Endpoint = 'http://localhost:11434/api/chat',

        [Parameter()]
        [int]$MaxMessages = 50,

        [Parameter()]
        [int]$SummarizeAfter = 30,

        [Parameter()]
        [int]$TimeoutSec = 180
    )

    $resolvedSession = if ($PSCmdlet.ParameterSetName -eq 'ByPath') {
        Resolve-SessionObject -Path $Path
    }
    else {
        Resolve-SessionObject -Session $Session
    }

    if ([string]::IsNullOrWhiteSpace($Model)) {
        $Model = $resolvedSession.Model
    }

    $window = Get-Llamarc42ProjectSessionConversationWindow `
        -Session $resolvedSession `
        -MaxMessages $MaxMessages `
        -SummarizeAfter $SummarizeAfter

    if ($window.MessagesToSummarize.Count -eq 0) {
        return $resolvedSession
    }

    $existingSummary = $window.RollingSummary
    if ([string]::IsNullOrWhiteSpace($existingSummary)) {
        $existingSummary = 'No prior summary.'
    }

    $messageText = ($window.MessagesToSummarize | ForEach-Object {
        "[{0}] {1}: {2}" -f $_.Timestamp, $_.Role, $_.Content
    }) -join "`n`n"

    $summaryPrompt = @"
You are summarizing a project-scoped engineering conversation.

Produce a concise rolling summary that preserves:
- decisions made
- constraints identified
- open questions
- important implementation direction
- user preferences that affect this session

Do not restate the project documentation.
Do not invent facts.
Prefer bullet points.
Keep the result compact and useful for future continuation.

Existing summary:
$existingSummary

Messages to summarize:
$messageText
"@.Trim()

    $body = @{
        model    = $Model
        stream   = $false
        messages = @(
            @{
                role    = 'system'
                content = 'Summarize prior chat history for future continuation.'
            },
            @{
                role    = 'user'
                content = $summaryPrompt
            }
        )
    } | ConvertTo-Json -Depth 10

    try {
        $response = Invoke-RestMethod `
            -Uri $Endpoint `
            -Method Post `
            -ContentType 'application/json' `
            -Body $body `
            -TimeoutSec $TimeoutSec
    }
    catch {
        throw "Failed to summarize session history via Ollama. $($_.Exception.Message)"
    }

    $summaryText = $null

    if ($response.message -and $response.message.content) {
        $summaryText = $response.message.content
    }
    elseif ($response.response) {
        $summaryText = $response.response
    }

    if ([string]::IsNullOrWhiteSpace($summaryText)) {
        throw 'Ollama did not return summary content.'
    }

    $resolvedSession.RollingSummary = $summaryText.Trim()
    $resolvedSession.Updated = (Get-Date).ToString('o')

    Save-SessionMetadata -Session $resolvedSession

    return $resolvedSession
}
