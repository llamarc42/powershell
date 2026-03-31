<#
.SYNOPSIS
Lists Ollama project sessions for a project.

.DESCRIPTION
Reads session metadata from the project's `.sessions` folder, returns
summary information for each valid session, and optionally filters by
name or limits the number of results.

.PARAMETER ProjectFolder
The current project folder or any child path within the project.

.PARAMETER Name
Filters sessions by partial match against id, name, or title.

.PARAMETER First
Returns only the first N sessions after sorting newest-first.

.EXAMPLE
Get-OllamaProjectSessionList -ProjectFolder . -First 10

.OUTPUTS
Ollama.ProjectSessionInfo
#>
function Get-OllamaProjectSessionList {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$ProjectFolder,

        [Parameter()]
        [string]$Name,

        [Parameter()]
        [int]$First
    )

    $paths = Resolve-AiContextPath -ProjectFolder $ProjectFolder
    $sessionRoot = Join-Path -Path $paths.ProjectFolder -ChildPath '.sessions'

    if (-not (Test-Path -LiteralPath $sessionRoot -PathType Container)) {
        return @()
    }

    $sessionFolders = Get-ChildItem -LiteralPath $sessionRoot -Directory |
        Sort-Object Name -Descending

    $sessions = foreach ($folder in $sessionFolders) {
        $sessionFile = Join-Path -Path $folder.FullName -ChildPath 'session.json'

        if (-not (Test-Path -LiteralPath $sessionFile -PathType Leaf)) {
            continue
        }

        try {
            $metadata = Get-Content -LiteralPath $sessionFile -Raw -ErrorAction Stop |
                ConvertFrom-Json -AsHashtable

            $session = New-SessionObject -Metadata $metadata

            [pscustomobject]@{
                PSTypeName    = 'Ollama.ProjectSessionInfo'
                Id            = $session.Id
                Name          = $session.Name
                Title         = $session.Title
                ProjectName   = $session.ProjectName
                Model         = $session.Model
                Created       = $session.Created
                Updated       = $session.Updated
                MessageCount  = $session.MessageCount
                SessionFolder = $session.SessionFolder
                SessionFile   = $session.SessionFile
                MessagesFile  = $session.MessagesFile
            }
        }
        catch {
            Write-Warning "Failed to read session metadata from '$sessionFile'. $($_.Exception.Message)"
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($Name)) {
        $sessions = $sessions | Where-Object {
            $_.Name -like "*$Name*" -or $_.Title -like "*$Name*" -or $_.Id -like "*$Name*"
        }
    }

    if ($First -gt 0) {
        $sessions = $sessions | Select-Object -First $First
    }

    return @($sessions)
}
