<#
.SYNOPSIS
Resolves a session from a list by partial name match.

.DESCRIPTION
Searches the supplied session list for partial matches against session
id, name, or title. Returns the resolved session when exactly one match
is found, throws when multiple matches are found, and returns `$null`
when there are no matches.

.PARAMETER Sessions
The session summaries to search.

.PARAMETER Name
The partial session name, title, or id to match.

.EXAMPLE
Resolve-OllamaProjectSessionByName -Sessions $sessions -Name 'planning'

.OUTPUTS
Ollama.ProjectSession
#>
function Resolve-OllamaProjectSessionByName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object[]]$Sessions,

        [Parameter(Mandatory)]
        [string]$Name
    )

    $matches = @(
        $Sessions | Where-Object {
            $_.Id    -like "*$Name*" -or
            $_.Name  -like "*$Name*" -or
            $_.Title -like "*$Name*"
        }
    )

    if ($matches.Count -eq 1) {
        return Get-OllamaProjectSession -Path $matches[0].SessionFolder
    }

    if ($matches.Count -gt 1) {
        $options = $matches | Select-Object Title, Updated, MessageCount
        $formatted = $options | Format-Table -AutoSize | Out-String
        throw "Multiple sessions matched '$Name':`n$formatted"
    }

    return $null
}
