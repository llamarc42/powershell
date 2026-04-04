<#
.SYNOPSIS
Starts an interactive Ollama chat session for a project.

.DESCRIPTION
Resolves project paths, lets the user resume or create a session, and
then enters a prompt loop that sends each message to the configured
Ollama session workflow.

.PARAMETER ProjectFolder
The current project folder or any child path within the project.

.PARAMETER GlobalFolder
The global context folder. When omitted, the module resolves `ai/global`
from the project structure.

.PARAMETER Name
The session name to resume or create automatically.

.PARAMETER Model
The model used when creating a new session or overriding message sends.

.PARAMETER Intent
The conversational intent used to shape assistant responses.

.PARAMETER IncludeFileHeaders
Adds file boundary headers to the generated context payload.

.PARAMETER RefreshArtifactFiles
Refreshes tracked artifact file metadata after each send.

.PARAMETER MessageTail
The number of recent transcript messages to send as chat history.

.PARAMETER TimeoutSec
The request timeout in seconds.

.EXAMPLE
Start-Llamarc42ProjectChat -Name 'planning' -Intent planning

.OUTPUTS
Llamarc42.ProjectSession
#>
function Start-Llamarc42ProjectChat {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$ProjectFolder,

        [Parameter()]
        [string]$GlobalFolder,

        [Parameter()]
        [string]$Name,

        [Parameter()]
        [string]$Model,

        [Parameter()]
        [ValidateSet('planning', 'coding', 'review', 'general')]
        [string]$Intent = 'general',

        [Parameter()]
        [switch]$IncludeFileHeaders,

        [Parameter()]
        [switch]$RefreshArtifactFiles,

        [Parameter()]
        [int]$MessageTail = 50,

        [Parameter()]
        [int]$TimeoutSec = 300
    )

    $paths = Resolve-Llamarc42Path -ProjectFolder $ProjectFolder -GlobalFolder $GlobalFolder
    $sessions = @(Get-Llamarc42ProjectSessionList -ProjectFolder $paths.ProjectFolder)
    $session = $null

    Write-Host ''
    Write-Host "Project: $($paths.ProjectFolder)"
    Write-Host "Global : $($paths.GlobalFolder)"
    Write-Host ''

    if (-not [string]::IsNullOrWhiteSpace($Name)) {
        $session = Resolve-Llamarc42ProjectSessionByName -Sessions $sessions -Name $Name

        if ($session) {
            Write-Host ''
            Write-Host "Resuming session: $($session.Title)" -ForegroundColor Cyan
        }
        else {
            Write-Host ''
            Write-Host "No session found matching '$Name'. Creating new session." -ForegroundColor Yellow

            $session = New-Llamarc42ProjectSession `
                -Name $Name `
                -Model $Model `
                -ProjectFolder $paths.ProjectFolder `
                -GlobalFolder $paths.GlobalFolder
        }
    }

    if (-not $session) {
        if ($sessions.Count -gt 0) {
            $session = Select-Llamarc42ProjectSession `
                -ProjectFolder $paths.ProjectFolder `
                -AllowNew

            if (-not $session) {
                $session = New-InteractiveLlamarc42ProjectSession `
                    -ProjectFolder $paths.ProjectFolder `
                    -GlobalFolder $paths.GlobalFolder `
                    -Model $Model
            }
        }
        else {
            Write-Host 'No existing sessions found.'

            $session = New-InteractiveLlamarc42ProjectSession `
                -ProjectFolder $paths.ProjectFolder `
                -GlobalFolder $paths.GlobalFolder `
                -Model $Model
        }
    }

    Write-Host ''
    Write-Host "Session: $($session.Title)" -ForegroundColor Cyan
    Write-Host "Model  : $($session.Model)"
    Write-Host "Intent : $Intent"
    Write-Host ''
    Write-Host "Type 'exit', 'quit', or ':q' to end the chat."
    Write-Host ''

    while ($true) {
        $prompt = Read-Host 'You'

            $sendParams = @{
            Session              = $session
            Prompt               = $prompt
            Intent               = $Intent
            IncludeFileHeaders   = $IncludeFileHeaders
            RefreshArtifactFiles = $RefreshArtifactFiles
            MessageTail          = $MessageTail
            TimeoutSec           = $TimeoutSec
            }

        if ($PSBoundParameters.ContainsKey('Model') -and -not [string]::IsNullOrWhiteSpace($Model)) {
            $sendParams.Model = $Model
        }

        if ([string]::IsNullOrWhiteSpace($prompt)) {
            continue
        }

        if ($prompt -in @('exit', 'quit', ':q')) {
            Write-Host ''
            Write-Host 'Ending chat session.'
            break
        }

        try {
            $result = Send-Llamarc42ProjectSessionMessage @sendParams

            Write-Host ''
            Write-Host 'Assistant:' -ForegroundColor Green
            Write-Host $result.Response
            Write-Host ''

            $session = Get-Llamarc42ProjectSession -Path $session.SessionFolder
        }
        catch {
            Write-Host ''
            Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
            Write-Host ''
        }
    }

    return $session
}
