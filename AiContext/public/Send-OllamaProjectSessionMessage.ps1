<#
.SYNOPSIS
Sends a prompt within an Ollama project session.

.DESCRIPTION
Builds the current artifact-backed context, combines it with recent
session history, calls the Ollama chat endpoint, stores the user and
assistant messages, and returns the chat result.

.PARAMETER Session
The session object to use. Accepts pipeline input.

.PARAMETER Path
The path to the session folder.

.PARAMETER Prompt
The user prompt to send.

.PARAMETER Intent
The conversational intent used to shape the system prompt.

.PARAMETER Model
Overrides the model stored on the session.

.PARAMETER Endpoint
The Ollama chat API endpoint.

.PARAMETER IncludeFileHeaders
Adds file boundary headers to the generated context payload.

.PARAMETER RefreshArtifactFiles
Refreshes the session's tracked artifact file list from the current
resolved context.

.PARAMETER MessageTail
The number of most recent transcript messages to include as history.

.PARAMETER TimeoutSec
The request timeout in seconds.

.PARAMETER RawResponse
Returns the raw Ollama response and full message payload in addition to
the normalized result.

.EXAMPLE
Send-OllamaProjectSessionMessage -Session $session -Prompt 'Summarize the latest design constraints.'

.OUTPUTS
Ollama.ProjectSessionChatResult
#>
function Send-OllamaProjectSessionMessage {
    [CmdletBinding(DefaultParameterSetName = 'BySession')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'BySession', ValueFromPipeline)]
        [psobject]$Session,

        [Parameter(Mandatory, ParameterSetName = 'ByPath')]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$Prompt,

        [Parameter()]
        [ValidateSet('planning', 'coding', 'review', 'general')]
        [string]$Intent = 'general',

        [Parameter()]
        [string]$Model,

        [Parameter()]
        [string]$Endpoint = 'http://localhost:11434/api/chat',

        [Parameter()]
        [switch]$IncludeFileHeaders,

        [Parameter()]
        [switch]$RefreshArtifactFiles,

        [Parameter()]
        [int]$MessageTail = 50,

        [Parameter()]
        [int]$TimeoutSec = 300,

        [Parameter()]
        [switch]$RawResponse
    )

    if ([string]::IsNullOrWhiteSpace($Prompt)) {
        throw 'Prompt cannot be null, empty, or whitespace.'
    }

    $resolvedSession = if ($PSCmdlet.ParameterSetName -eq 'ByPath') {
        Resolve-SessionObject -Path $Path
    }
    else {
        Resolve-SessionObject -Session $Session
    }

    if ([string]::IsNullOrWhiteSpace($Model)) {
        $Model = $resolvedSession.Model
    }

    $context = Get-AiProjectContext `
        -ProjectFolder $resolvedSession.ProjectFolder `
        -GlobalFolder $resolvedSession.GlobalFolder `
        -IncludeExtensions $resolvedSession.ArtifactExtensions `
        -IncludeFileHeaders:$IncludeFileHeaders

    if ($RefreshArtifactFiles) {
        $resolvedSession.ArtifactFiles = @($context.GlobalFiles + $context.ProjectFiles)
    }

    $systemMessageContent = @"
You are a project-aware engineering assistant operating against local documentation artifacts.

Treat the provided GLOBAL CONTEXT and PROJECT CONTEXT as authoritative for this session.

Rules:
- Do not invent project-specific facts not supported by the provided artifacts.
- If the artifact context is insufficient, say so explicitly.
- Respect documented constraints and decisions over general best practices.
- Prefer explicit tradeoffs over absolute recommendations.
- For architecture-impacting recommendations, call out whether a new ADR may be needed.
- Keep responses aligned to the user's intent: $Intent.
- Conversation history provides working context, but artifact documents remain the source of truth.

GLOBAL AND PROJECT CONTEXT
==========================
$($context.CombinedContent)
"@.Trim()

    $historyMessages = @()
    $sessionHistory = Get-OllamaProjectSessionMessage -Session $resolvedSession

    if ($MessageTail -gt 0) {
        $sessionHistory = @($sessionHistory | Select-Object -Last $MessageTail)
    }

    foreach ($message in $sessionHistory) {
        $historyMessages += @{
            role    = $message.Role
            content = $message.Content
        }
    }

    Add-OllamaProjectSessionMessage `
        -Session $resolvedSession `
        -Role user `
        -Content $Prompt | Out-Null

    $chatMessages = @(
        @{
            role    = 'system'
            content = $systemMessageContent
        }
    ) + $historyMessages + @(
        @{
            role    = 'user'
            content = $Prompt
        }
    )

    $body = @{
        model    = $Model
        stream   = $false
        messages = $chatMessages
    } | ConvertTo-Json -Depth 20

    try {
        $response = Invoke-RestMethod `
            -Uri $Endpoint `
            -Method Post `
            -ContentType 'application/json' `
            -Body $body `
            -TimeoutSec $TimeoutSec
    }
    catch {
        throw "Failed to call Ollama chat endpoint '$Endpoint'. $($_.Exception.Message)"
    }

    $assistantContent = $null

    if ($response.message -and $response.message.content) {
        $assistantContent = $response.message.content
    }
    elseif ($response.response) {
        $assistantContent = $response.response
    }

    if ([string]::IsNullOrWhiteSpace($assistantContent)) {
        throw 'Ollama did not return assistant message content.'
    }

    $assistantMessage = Add-OllamaProjectSessionMessage `
        -Session $resolvedSession `
        -Role assistant `
        -Content $assistantContent

    $resolvedSession.Updated = (Get-Date).ToString('o')

    if ($RefreshArtifactFiles) {
        Save-SessionMetadata -Session $resolvedSession
    }

    if ($RawResponse) {
        return [pscustomobject]@{
            PSTypeName       = 'Ollama.ProjectSessionChatResult'
            Session          = $resolvedSession
            Intent           = $Intent
            Model            = $Model
            Endpoint         = $Endpoint
            UserPrompt       = $Prompt
            AssistantMessage = $assistantMessage
            Messages         = $chatMessages
            OllamaResponse   = $response
        }
    }

    return [pscustomobject]@{
        PSTypeName       = 'Ollama.ProjectSessionChatResult'
        Session          = $resolvedSession
        Intent           = $Intent
        Model            = $Model
        UserPrompt       = $Prompt
        AssistantMessage = $assistantMessage
        Response         = $assistantContent
    }
}
