<#
.SYNOPSIS
Resumes an existing Ollama project session.

.DESCRIPTION
Returns the most recent session for a project or resolves a specific
session by partial name, title, or id match.

.PARAMETER ProjectFolder
The current project folder or any child path within the project.

.PARAMETER Name
The partial session name, title, or id to match.

.EXAMPLE
Resume-OllamaProjectSession -Name 'review'

.OUTPUTS
Ollama.ProjectSession
#>
function Resume-OllamaProjectSession {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$ProjectFolder,

        [Parameter()]
        [string]$Name
    )

    $sessions = Get-OllamaProjectSessionList -ProjectFolder $ProjectFolder

    if (-not $sessions -or $sessions.Count -eq 0) {
        if ([string]::IsNullOrWhiteSpace($ProjectFolder)) {
            $ProjectFolder = (Get-Location).Path
        }

        $paths = Resolve-AiContextPath -ProjectFolder $ProjectFolder

        throw "No sessions found for project: $($paths.ProjectFolder)"
    }

    if ([string]::IsNullOrWhiteSpace($Name)) {
        $match = $sessions | Select-Object -First 1
        return Get-OllamaProjectSession -Path $match.SessionFolder
    }

    $matches = @(
        $sessions | Where-Object {
            $_.Id   -like "*$Name*" -or
            $_.Name -like "*$Name*" -or
            $_.Title -like "*$Name*"
        }
    )

    if ($matches.Count -eq 0) {
        throw "No session found matching '$Name'."
    }

    if ($matches.Count -gt 1) {
        $options = $matches | Select-Object Id, Title, Updated
        $formatted = $options | Format-Table -AutoSize | Out-String
        throw "Multiple sessions matched '$Name':`n$formatted"
    }

    return Get-OllamaProjectSession -Path $matches[0].SessionFolder
}
