<#
.SYNOPSIS
Sends a one-off prompt to an Ollama generate endpoint.

.DESCRIPTION
Builds combined global and project context, creates a single prompt
payload, sends it to the configured Ollama generate endpoint, and
returns the assistant response without creating or updating a session.

.PARAMETER Prompt
The user prompt to send.

.PARAMETER Model
The Ollama model to use.

.PARAMETER ProjectFolder
The current project folder or any child path within the project.

.PARAMETER GlobalFolder
The global context folder. When omitted, the module resolves `ai/global`
from the project structure.

.PARAMETER IncludeExtensions
The documentation file extensions to include as context.

.PARAMETER Endpoint
The Ollama generate API endpoint.

.PARAMETER Intent
The conversational intent used to shape the system prompt.

.PARAMETER IncludeFileHeaders
Adds file boundary headers to the generated context payload.

.PARAMETER RawResponse
Returns the raw Ollama response and full prompt in addition to the
normalized result.

.PARAMETER TimeoutSec
The request timeout in seconds.

.EXAMPLE
Invoke-OllamaProjectChat -Prompt 'Summarize the project context.'

.OUTPUTS
System.Management.Automation.PSCustomObject
#>
function Invoke-OllamaProjectChat {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Prompt,

        [Parameter()]
        [string]$Model = 'gpt-oss:20b',

        [Parameter()]
        [string]$ProjectFolder,

        [Parameter()]
        [string]$GlobalFolder,

        [Parameter()]
        [string[]]$IncludeExtensions = @('.md', '.txt'),

        [Parameter()]
        [string]$Endpoint = 'http://localhost:11434/api/generate',

        [Parameter()]
        [ValidateSet('planning', 'coding', 'review', 'general')]
        [string]$Intent = 'general',

        [Parameter()]
        [switch]$IncludeFileHeaders,

        [Parameter()]
        [switch]$RawResponse,

        [Parameter()]
        [int]$TimeoutSec = 300
    )

    $context = Get-AiProjectContext `
        -ProjectFolder $ProjectFolder `
        -GlobalFolder $GlobalFolder `
        -IncludeExtensions $IncludeExtensions `
        -IncludeFileHeaders:$IncludeFileHeaders

    $systemPrompt = @"
You are a project-aware engineering assistant operating against local documentation.

Follow these rules:
- Treat the provided GLOBAL CONTEXT and PROJECT CONTEXT as authoritative.
- Do not invent project-specific facts not supported by the provided context.
- If the context is insufficient, say so explicitly.
- Prefer explicit tradeoffs over absolute recommendations.
- Respect documented constraints and decisions over general best practices.
- For architecture-impacting recommendations, call out whether a new ADR may be needed.
- Keep responses aligned to the user's intent: $Intent.
"@.Trim()

    $fullPrompt = @"
[SYSTEM]
$systemPrompt

[INTENT]
$Intent

[GLOBAL AND PROJECT CONTEXT]
$($context.CombinedContent)

[USER REQUEST]
$Prompt
"@.Trim()

    $body = @{
        model  = $Model
        prompt = $fullPrompt
        stream = $false
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
        throw "Failed to call Ollama endpoint '$Endpoint'. $($_.Exception.Message)"
    }

    if ($RawResponse) {
        return [pscustomobject]@{
            Model          = $Model
            Intent         = $Intent
            Endpoint       = $Endpoint
            ProjectFolder  = $context.ProjectFolder
            GlobalFolder   = $context.GlobalFolder
            GlobalFiles    = $context.GlobalFiles
            ProjectFiles   = $context.ProjectFiles
            Prompt         = $Prompt
            FullPrompt     = $fullPrompt
            Response       = $response.response
            OllamaResponse = $response
        }
    }

    [pscustomobject]@{
        Model         = $Model
        Intent        = $Intent
        ProjectFolder = $context.ProjectFolder
        GlobalFolder  = $context.GlobalFolder
        GlobalFiles   = $context.GlobalFiles
        ProjectFiles  = $context.ProjectFiles
        Response      = $response.response
    }
}
