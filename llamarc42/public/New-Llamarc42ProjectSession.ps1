<#
.SYNOPSIS
Creates a new Ollama project session.

.DESCRIPTION
Creates a session folder under `.sessions`, initializes the metadata and
message files, and returns the new session object.

.PARAMETER Name
The base name used to generate the session slug and id.

.PARAMETER Title
The display title for the session. When omitted, a title is generated
from the slug.

.PARAMETER Model
The default Ollama model stored with the session.

.PARAMETER ProjectFolder
The current project folder or any child path within the project.

.PARAMETER GlobalFolder
The global context folder. When omitted, the module resolves `ai/global`
from the project structure.

.PARAMETER ArtifactExtensions
The documentation file extensions tracked for session context refreshes.

.PARAMETER Tags
Optional tags to persist with the session metadata.

.EXAMPLE
New-Llamarc42ProjectSession -Name 'api-review' -Model 'gpt-oss:20b'

.OUTPUTS
Llamarc42.ProjectSession
#>
function New-Llamarc42ProjectSession {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Name = 'chat',

        [Parameter()]
        [string]$Title,

        [Parameter()]
        [string]$Model = 'gpt-oss:20b',

        [Parameter()]
        [string]$ProjectFolder,

        [Parameter()]
        [string]$GlobalFolder,

        [Parameter()]
        [string[]]$ArtifactExtensions = @('.md'),

        [Parameter()]
        [string[]]$Tags = @()
    )

    $paths = Resolve-Llamarc42Path -ProjectFolder $ProjectFolder -GlobalFolder $GlobalFolder

    $projectName = Split-Path -Path $paths.ProjectFolder -Leaf
    $sessionRoot = Join-Path -Path $paths.ProjectFolder -ChildPath '.sessions'

    if (-not (Test-Path -LiteralPath $sessionRoot -PathType Container)) {
        $null = New-Item -Path $sessionRoot -ItemType Directory -Force
    }

    $slug = ConvertTo-Slug -InputString $Name

    if ([string]::IsNullOrWhiteSpace($Title)) {
        $Title = ($slug -split '-') | ForEach-Object {
            if ($_.Length -gt 0) {
                $_.Substring(0,1).ToUpperInvariant() + $_.Substring(1)
            }
        } | Join-String -Separator ' '
    }

    $timestamp = Get-SessionTimestamp
    $sessionId = "$timestamp-$slug"
    $sessionFolder = Join-Path -Path $sessionRoot -ChildPath $sessionId
    $sessionFile = Join-Path -Path $sessionFolder -ChildPath 'session.json'
    $messagesFile = Join-Path -Path $sessionFolder -ChildPath 'messages.jsonl'

    if (Test-Path -LiteralPath $sessionFolder) {
        throw "Session folder already exists: $sessionFolder"
    }

    $null = New-Item -Path $sessionFolder -ItemType Directory -Force
    $null = New-Item -Path $messagesFile -ItemType File -Force

    $now = (Get-Date).ToString('o')

    $metadata = @{
        id                 = $sessionId
        name               = $slug
        title              = $Title
        projectName        = $projectName
        projectFolder      = $paths.ProjectFolder
        globalFolder       = $paths.GlobalFolder
        sessionFolder      = $sessionFolder
        model              = $Model
        created            = $now
        updated            = $now
        artifactExtensions = @($ArtifactExtensions)
        artifactFiles      = @()
        messageCount       = 0
        rollingSummary     = $null
        tags               = @($Tags)
    }

    $session = New-SessionObject -Metadata $metadata
    Save-SessionMetadata -Session $session

    return $session
}
