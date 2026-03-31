<#
.SYNOPSIS
Prompts for and creates a new Ollama project session.

.DESCRIPTION
Prompts the user for a session name, applies a default when blank, and
then creates the session.

.PARAMETER ProjectFolder
The resolved project folder.

.PARAMETER GlobalFolder
The resolved global context folder.

.PARAMETER Model
The default model to store with the new session.

.EXAMPLE
New-InteractiveOllamaProjectSession -ProjectFolder $paths.ProjectFolder -GlobalFolder $paths.GlobalFolder

.OUTPUTS
Ollama.ProjectSession
#>
function New-InteractiveOllamaProjectSession {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProjectFolder,

        [Parameter(Mandatory)]
        [string]$GlobalFolder,

        [Parameter()]
        [string]$Model = 'gpt-oss:20b'
    )

    $newSessionName = Read-Host 'Enter a name for the new session'
    if ([string]::IsNullOrWhiteSpace($newSessionName)) {
        $newSessionName = 'chat'
    }

    New-OllamaProjectSession `
        -Name $newSessionName `
        -Model $Model `
        -ProjectFolder $ProjectFolder `
        -GlobalFolder $GlobalFolder
}
