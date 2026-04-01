<#
.SYNOPSIS
Gets an Ollama project session.

.DESCRIPTION
Loads a session from a specific session folder, a known session id, or
the most recent session for a project and returns a normalized session
object.

.PARAMETER Id
The session id to load from the project's `.sessions` folder.

.PARAMETER Path
The full path to a session folder.

.PARAMETER ProjectFolder
The current project folder or any child path within the project.

.EXAMPLE
Get-Llamarc42ProjectSession -Id '2026-03-31_090000-chat'

.EXAMPLE
Get-Llamarc42ProjectSession -Path '.sessions/2026-03-31_090000-chat'

.OUTPUTS
Llamarc42.ProjectSession
#>
function Get-Llamarc42ProjectSession {
    [CmdletBinding(DefaultParameterSetName = 'ById')]
    param(
        [Parameter(ParameterSetName = 'ById')]
        [string]$Id,

        [Parameter(ParameterSetName = 'ByPath')]
        [string]$Path,

        [Parameter()]
        [string]$ProjectFolder
    )

    if ($PSCmdlet.ParameterSetName -eq 'ByPath') {
        $sessionFolder = [System.IO.Path]::GetFullPath($Path)

        if (-not (Test-Path -LiteralPath $sessionFolder -PathType Container)) {
            throw "Session path does not exist: $sessionFolder"
        }

        $sessionFile = Join-Path -Path $sessionFolder -ChildPath 'session.json'

        if (-not (Test-Path -LiteralPath $sessionFile -PathType Leaf)) {
            throw "Session metadata file not found: $sessionFile"
        }
    }
    else {
        if ([string]::IsNullOrWhiteSpace($ProjectFolder)) {
            $ProjectFolder = (Get-Location).Path
        }

        $paths = Resolve-Llamarc42Path -ProjectFolder $ProjectFolder
        $sessionRoot = Join-Path -Path $paths.ProjectFolder -ChildPath '.sessions'

        if (-not (Test-Path -LiteralPath $sessionRoot -PathType Container)) {
            throw "No .sessions folder found for project: $($paths.ProjectFolder)"
        }

        if ([string]::IsNullOrWhiteSpace($Id)) {
            $sessionFolder = Get-ChildItem -LiteralPath $sessionRoot -Directory |
                Sort-Object Name -Descending |
                Select-Object -First 1 -ExpandProperty FullName

            if (-not $sessionFolder) {
                throw "No sessions found in: $sessionRoot"
            }
        }
        else {
            $sessionFolder = Join-Path -Path $sessionRoot -ChildPath $Id

            if (-not (Test-Path -LiteralPath $sessionFolder -PathType Container)) {
                throw "Session not found: $Id"
            }
        }

        $sessionFile = Join-Path -Path $sessionFolder -ChildPath 'session.json'

        if (-not (Test-Path -LiteralPath $sessionFile -PathType Leaf)) {
            throw "Session metadata file not found: $sessionFile"
        }
    }

    $metadata = Get-Content -LiteralPath $sessionFile -Raw | ConvertFrom-Json -AsHashtable
    return New-SessionObject -Metadata $metadata
}
