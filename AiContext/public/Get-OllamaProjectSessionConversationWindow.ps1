<#
.SYNOPSIS
Builds the conversation window for a project session.

.DESCRIPTION
Loads the session transcript, keeps the most recent messages that should
remain in the active conversation window, and identifies older messages
that should be folded into the rolling summary once the transcript grows
beyond the summarization threshold.

.PARAMETER Session
The session object to inspect. Accepts pipeline input.

.PARAMETER Path
The path to the session folder.

.PARAMETER MaxMessages
The maximum number of recent messages to keep in the active window.

.PARAMETER SummarizeAfter
The transcript size threshold after which older messages are returned in
`MessagesToSummarize`.

.EXAMPLE
Get-OllamaProjectSessionConversationWindow -Session $session

.EXAMPLE
Get-OllamaProjectSessionConversationWindow -Path $sessionPath -MaxMessages 40 -SummarizeAfter 20

.OUTPUTS
Llamarc42.ConversationWindow
#>
function Get-OllamaProjectSessionConversationWindow {
    [CmdletBinding(DefaultParameterSetName = 'BySession')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'BySession', ValueFromPipeline)]
        [psobject]$Session,

        [Parameter(Mandatory, ParameterSetName = 'ByPath')]
        [string]$Path,

        [Parameter()]
        [int]$MaxMessages = 50,

        [Parameter()]
        [int]$SummarizeAfter = 30
    )

    $resolvedSession = if ($PSCmdlet.ParameterSetName -eq 'ByPath') {
        Resolve-SessionObject -Path $Path
    }
    else {
        Resolve-SessionObject -Session $Session
    }

    $messages = @(Get-OllamaProjectSessionMessage -Session $resolvedSession)
    $messageCount = $messages.Count

    $summary = $resolvedSession.RollingSummary
    $messagesToSummarize = @()
    $recentMessages = $messages

    if ($messageCount -gt $SummarizeAfter) {
        $keepCount = [Math]::Min($MaxMessages, $messageCount)
        $recentMessages = @($messages | Select-Object -Last $keepCount)

        $recentFirstTimestamp = $null
        if ($recentMessages.Count -gt 0) {
            $recentFirstTimestamp = $recentMessages[0].Timestamp
        }

        if ($recentFirstTimestamp) {
            $messagesToSummarize = @(
                $messages | Where-Object { $_.Timestamp -lt $recentFirstTimestamp }
            )
        }
    }

    [pscustomobject]@{
        PSTypeName           = 'Llamarc42.ConversationWindow'
        Session              = $resolvedSession
        RollingSummary       = $summary
        MessagesToSummarize  = @($messagesToSummarize)
        RecentMessages       = @($recentMessages)
        TotalMessageCount    = $messageCount
        MaxMessages          = $MaxMessages
        SummarizeAfter       = $SummarizeAfter
    }
}
