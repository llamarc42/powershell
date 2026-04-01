<#
.SYNOPSIS
Sends a prompt within an Ollama project session.

.DESCRIPTION
Loads the retrieval policy, resolves the intent-specific retrieval
context, updates the rolling conversation summary when older transcript
messages need to be condensed, combines the retrieved artifacts with the
rolling summary and recent session history, calls the Ollama chat
endpoint, stores the user and assistant messages, and returns the chat
result.

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

.PARAMETER PolicyPath
The path to the retrieval policy YAML file. When omitted, the default
retrieval policy for the AI workspace is used.

.PARAMETER IncludeFileHeaders
Adds file boundary headers to the generated context payload.

.PARAMETER RefreshArtifactFiles
Refreshes the session's tracked artifact file list from the resolved
retrieval context.

.PARAMETER MessageTail
The default maximum number of recent transcript messages to retain in
the active conversation window when the retrieval policy does not define
`history.max_messages`.

.PARAMETER TimeoutSec
The request timeout in seconds.

.PARAMETER InspectPrompt
Returns the fully constructed prompt payload for inspection and exits
before writing the user message to `messages.jsonl` and before calling
the Ollama endpoint.

.PARAMETER RawResponse
Returns the raw Ollama response and full message payload in addition to
the normalized result.

.EXAMPLE
Send-Llamarc42ProjectSessionMessage -Session $session -Prompt 'Summarize the latest design constraints.'

.EXAMPLE
Send-Llamarc42ProjectSessionMessage -Path $sessionPath -Prompt 'What ADRs affect this change?' -Intent review -PolicyPath './tooling/config/retrieval.yaml'

.EXAMPLE
Send-Llamarc42ProjectSessionMessage -Session $session -Prompt 'Continue the refactor plan.' -MessageTail 40 -RefreshArtifactFiles

.EXAMPLE
Send-Llamarc42ProjectSessionMessage -Session $session -Prompt 'Show me the exact payload.' -InspectPrompt

.OUTPUTS
Llamarc42.ProjectSessionChatResult
#>
function Send-Llamarc42ProjectSessionMessage {
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
        [string]$PolicyPath,

        [Parameter()]
        [switch]$IncludeFileHeaders,

        [Parameter()]
        [switch]$RefreshArtifactFiles,

        [Parameter()]
        [int]$MessageTail = 50,

        [Parameter()]
        [int]$TimeoutSec = 300,

        [Parameter()]
        [switch]$InspectPrompt,

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

    $policy = Get-Llamarc42RetrievalPolicy `
        -PolicyPath $PolicyPath `
        -ProjectFolder $resolvedSession.ProjectFolder

    $retrievalContext = Resolve-Llamarc42RetrievalContext `
        -Intent $Intent `
        -ProjectFolder $resolvedSession.ProjectFolder `
        -GlobalFolder $resolvedSession.GlobalFolder `
        -Policy $policy `
        -IncludeExtensions $resolvedSession.ArtifactExtensions

    $retrievalContent = Get-RetrievalContextContent `
        -RetrievalContext $retrievalContext `
        -IncludeHeaders:$IncludeFileHeaders

    if ($RefreshArtifactFiles) {
        $resolvedSession.ArtifactFiles = @($retrievalContext.Files)
    }

    $historyMaxMessages = $MessageTail
    $historySummarizeAfter = 30

    if ($policy.Policy.history) {
        if ($policy.Policy.history.PSObject.Properties.Name -contains 'max_messages') {
            $historyMaxMessages = [int]$policy.Policy.history.max_messages
        }

        if ($policy.Policy.history.PSObject.Properties.Name -contains 'summarize_after') {
            $historySummarizeAfter = [int]$policy.Policy.history.summarize_after
        }
    }

    $resolvedSession = Update-Llamarc42ProjectSessionSummary `
        -Session $resolvedSession `
        -Model $Model `
        -Endpoint $Endpoint `
        -MaxMessages $historyMaxMessages `
        -SummarizeAfter $historySummarizeAfter `
        -TimeoutSec $TimeoutSec

    $conversationWindow = Get-Llamarc42ProjectSessionConversationWindow `
        -Session $resolvedSession `
        -MaxMessages $historyMaxMessages `
        -SummarizeAfter $historySummarizeAfter

    $rollingSummaryText = $conversationWindow.RollingSummary
    if ([string]::IsNullOrWhiteSpace($rollingSummaryText)) {
        $rollingSummaryText = 'No rolling conversation summary yet.'
    }

    $historyMessages = @()
    foreach ($message in $conversationWindow.RecentMessages) {
        $historyMessages += @{
            role    = $message.Role
            content = $message.Content
        }
    }

    $systemPrompt = @"
You are a project-aware engineering assistant operating against local documentation artifacts.

Treat the provided RETRIEVED CONTEXT as authoritative for this session.

Rules:
- Do not invent project-specific facts not supported by the provided artifacts.
- If the retrieved context is insufficient, say so explicitly.
- Respect documented constraints and decisions over general best practices.
- Prefer explicit tradeoffs over absolute recommendations.
- For architecture-impacting recommendations, call out whether a new ADR may be needed.
- Keep responses aligned to the user's intent: $Intent.
- Conversation history provides working context, but artifact documents remain the source of truth.

INTENT
======
$Intent

ROLLING CONVERSATION SUMMARY
============================
$rollingSummaryText

RETRIEVED CONTEXT
=================
$($retrievalContent.Content)
"@.Trim()

    $chatMessages = @(
        @{
            role    = 'system'
            content = $systemPrompt
        }
    ) + $historyMessages + @(
        @{
            role    = 'user'
            content = $Prompt
        }
    )

    $requestBody = @{
        model    = $Model
        stream   = $false
        messages = $chatMessages
    }

    if ($InspectPrompt) {
        return [pscustomobject]@{
            PSTypeName         = 'Llamarc42.PromptInspection'
            Session            = $resolvedSession
            Intent             = $Intent
            Model              = $Model
            Endpoint           = $Endpoint
            PolicyPath         = $policy.Path
            RetrievalContext   = $retrievalContext
            ConversationWindow = $conversationWindow
            SystemPrompt       = $systemPrompt
            Messages           = $chatMessages
            RequestBody        = $requestBody
        }
    }

    Add-Llamarc42ProjectSessionMessage `
        -Session $resolvedSession `
        -Role user `
        -Content $Prompt | Out-Null

    $body = $requestBody | ConvertTo-Json -Depth 20

    try {
        $response = Invoke-RestMethod `
            -Uri $Endpoint `
            -Method Post `
            -ContentType 'application/json' `
            -Body $body `
            -TimeoutSec $TimeoutSec `
            -ErrorAction Stop
    }
    catch {
        $message = $_.Exception.Message

        if ($message -match 'timed out') {
            throw "Ollama request timed out after $TimeoutSec seconds. Endpoint: $Endpoint"
        }

        if ($message -match 'actively refused' -or $message -match 'No connection could be made') {
            throw "Could not connect to Ollama at '$Endpoint'. Ensure Ollama is running and the endpoint is correct."
        }

        if ($message -match '404') {
            throw "Ollama endpoint '$Endpoint' was not found. Verify the Ollama API path."
        }

        if ($message -match '500') {
            throw "Ollama returned an internal server error. Check the Ollama process and model availability."
        }

        throw "Failed to call Ollama chat endpoint '$Endpoint'. $message"
    }

    $assistantContent = $null

    if ($response.message -and $response.message.content) {
        $assistantContent = $response.message.content
    }
    elseif ($response.response) {
        $assistantContent = $response.response
    }

    if ([string]::IsNullOrWhiteSpace($assistantContent)) {
        $responsePreview = try {
            $response | ConvertTo-Json -Depth 10 -Compress
        }
        catch {
            '<unavailable>'
        }

        throw "Ollama did not return assistant message content. Response preview: $responsePreview"
    }

    $assistantMessage = Add-Llamarc42ProjectSessionMessage `
        -Session $resolvedSession `
        -Role assistant `
        -Content $assistantContent

    $resolvedSession.Updated = (Get-Date).ToString('o')

    if ($RefreshArtifactFiles) {
        Save-SessionMetadata -Session $resolvedSession
    }

    if ($RawResponse) {
        return [pscustomobject]@{
            PSTypeName         = 'Llamarc42.ProjectSessionChatResult'
            Session            = $resolvedSession
            Intent             = $Intent
            Model              = $Model
            Endpoint           = $Endpoint
            PolicyPath         = $policy.Path
            RetrievalContext   = $retrievalContext
            ConversationWindow = $conversationWindow
            UserPrompt         = $Prompt
            AssistantMessage   = $assistantMessage
            Messages           = $chatMessages
            RequestBody        = $requestBody
            OllamaResponse     = $response
        }
    }

    return [pscustomobject]@{
        PSTypeName         = 'Llamarc42.ProjectSessionChatResult'
        Session            = $resolvedSession
        Intent             = $Intent
        Model              = $Model
        RetrievalContext   = $retrievalContext
        ConversationWindow = $conversationWindow
        UserPrompt         = $Prompt
        AssistantMessage   = $assistantMessage
        Response           = $assistantContent
    }
}
