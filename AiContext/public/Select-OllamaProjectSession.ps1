<#
.SYNOPSIS
Prompts the user to choose a project session interactively.

.DESCRIPTION
Displays existing sessions for a project, prompts for a numeric choice,
and returns the selected session. When `-AllowNew` is used, the command
can also return `$null` to signal that a new session should be created.

.PARAMETER ProjectFolder
The current project folder or any child path within the project.

.PARAMETER AllowNew
Adds an option to start a new session instead of selecting an existing
one.

.EXAMPLE
Select-OllamaProjectSession -ProjectFolder . -AllowNew

.OUTPUTS
Ollama.ProjectSession
#>
function Select-OllamaProjectSession {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$ProjectFolder,

        [Parameter()]
        [switch]$AllowNew
    )

    $paths = Resolve-AiContextPath -ProjectFolder $ProjectFolder
    $sessions = @(Get-OllamaProjectSessionList -ProjectFolder $paths.ProjectFolder)

    if ($sessions.Count -eq 0) {
        if ($AllowNew) {
            return $null
        }

        throw "No sessions found for project: $($paths.ProjectFolder)"
    }

    Write-Host 'Existing sessions:'
    Write-Host ''

    $index = 1
    foreach ($item in $sessions) {
        $updated = try {
            (Get-Date $item.Updated).ToString('yyyy-MM-dd HH:mm')
        }
        catch {
            $item.Updated
        }

        $title = $item.Title.PadRight(24)

        Write-Host ("[{0}] {1} | {2,3} msgs | {3}" -f `
            $index,
            $title,
            $item.MessageCount,
            $updated
        )

        $index++
    }

    if ($AllowNew) {
        Write-Host ("[{0}] Start a new session" -f $index)
    }

    Write-Host ''

    while ($true) {
        $selection = Read-Host 'Select a session number'

        $selectionNumber = 0
        if (-not [int]::TryParse($selection, [ref]$selectionNumber)) {
            Write-Host 'Please enter a valid number.' -ForegroundColor Yellow
            continue
        }

        if ($selectionNumber -ge 1 -and $selectionNumber -le $sessions.Count) {
            return Get-OllamaProjectSession -Path $sessions[$selectionNumber - 1].SessionFolder
        }

        if ($AllowNew -and $selectionNumber -eq ($sessions.Count + 1)) {
            return $null
        }

        Write-Host 'Selection out of range.' -ForegroundColor Yellow
    }
}
