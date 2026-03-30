Set-StrictMode -Version Latest

function Resolve-AiContextPath {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$ProjectFolder,

        [Parameter()]
        [string]$GlobalFolder
    )

    if ([string]::IsNullOrWhiteSpace($ProjectFolder)) {
        $ProjectFolder = (Get-Location).Path
    }

    $current = [System.IO.DirectoryInfo]::new(
        [System.IO.Path]::GetFullPath($ProjectFolder)
    )

    $projectRoot = $null
    $aiRoot = $null

    # Walk upward until we find /ai/projects/<project>
    while ($current -ne $null) {

        if ($current.Parent -and $current.Parent.Name -eq 'projects') {
            # Found project root
            $projectRoot = $current
            $aiRoot = $current.Parent.Parent
            break
        }

        $current = $current.Parent
    }

    if (-not $projectRoot) {
        throw @"
Could not resolve project root.

Expected to be inside:
ai/projects/<project>

Current path:
$ProjectFolder
"@
    }

    if (-not $aiRoot) {
        throw "Failed to resolve ai root from project structure."
    }

    $resolvedProjectFolder = $projectRoot.FullName

    if ([string]::IsNullOrWhiteSpace($GlobalFolder)) {
        $GlobalFolder = Join-Path -Path $aiRoot.FullName -ChildPath 'global'
    }

    $resolvedGlobalFolder = [System.IO.Path]::GetFullPath($GlobalFolder)

    if (-not (Test-Path -LiteralPath $resolvedGlobalFolder -PathType Container)) {
        throw @"
Global folder not found.

Expected:
$resolvedGlobalFolder

Ensure ai/global exists.
"@
    }

    [pscustomobject]@{
        ProjectFolder = $resolvedProjectFolder
        GlobalFolder  = $resolvedGlobalFolder
        AiRoot        = $aiRoot.FullName
    }
}

function Get-AiContextFiles {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter()]
        [string[]]$IncludeExtensions = @('.md', '.txt')
    )

    $normalizedExtensions = $IncludeExtensions | ForEach-Object {
        if ($_.StartsWith('.')) { $_.ToLowerInvariant() } else { ".$_".ToLowerInvariant() }
    }

    Get-ChildItem -LiteralPath $Path -Recurse -File | Where-Object {
        $normalizedExtensions -contains $_.Extension.ToLowerInvariant()
    } | Sort-Object FullName
}

function Get-AiContextContent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.IO.FileInfo[]]$Files,

        [Parameter(Mandatory)]
        [string]$RootPath,

        [Parameter()]
        [switch]$IncludeHeaders
    )

    $rootFullPath = [System.IO.Path]::GetFullPath($RootPath).TrimEnd('\','/')

    $builder = New-Object System.Text.StringBuilder

    foreach ($file in $Files) {
        $filePath = [System.IO.Path]::GetFullPath($file.FullName)

        $relativePath = if ($filePath.StartsWith($rootFullPath, [System.StringComparison]::OrdinalIgnoreCase)) {
            $filePath.Substring($rootFullPath.Length).TrimStart('\','/')
        }
        else {
            $file.Name
        }

        $content = Get-Content -LiteralPath $file.FullName -Raw -ErrorAction Stop

        if ($IncludeHeaders) {
            [void]$builder.AppendLine("----- BEGIN FILE: $relativePath -----")
            [void]$builder.AppendLine($content.Trim())
            [void]$builder.AppendLine("----- END FILE: $relativePath -----")
            [void]$builder.AppendLine()
        }
        else {
            [void]$builder.AppendLine($content.Trim())
            [void]$builder.AppendLine()
        }
    }

    $builder.ToString().Trim()
}

function Get-AiProjectContext {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$ProjectFolder,

        [Parameter()]
        [string]$GlobalFolder,

        [Parameter()]
        [string[]]$IncludeExtensions = @('.md', '.txt'),

        [Parameter()]
        [switch]$IncludeFileHeaders
    )

    $paths = Resolve-AiContextPath -ProjectFolder $ProjectFolder -GlobalFolder $GlobalFolder

    $globalFiles = Get-AiContextFiles -Path $paths.GlobalFolder -IncludeExtensions $IncludeExtensions
    $projectFiles = Get-AiContextFiles -Path $paths.ProjectFolder -IncludeExtensions $IncludeExtensions

    $globalContent = Get-AiContextContent `
        -Files $globalFiles `
        -RootPath $paths.GlobalFolder `
        -IncludeHeaders:$IncludeFileHeaders

    $projectContent = Get-AiContextContent `
        -Files $projectFiles `
        -RootPath $paths.ProjectFolder `
        -IncludeHeaders:$IncludeFileHeaders

    $combinedBuilder = New-Object System.Text.StringBuilder

    [void]$combinedBuilder.AppendLine("# GLOBAL CONTEXT")
    [void]$combinedBuilder.AppendLine()
    [void]$combinedBuilder.AppendLine($globalContent)
    [void]$combinedBuilder.AppendLine()
    [void]$combinedBuilder.AppendLine("# PROJECT CONTEXT")
    [void]$combinedBuilder.AppendLine()
    [void]$combinedBuilder.AppendLine($projectContent)

    [pscustomobject]@{
        ProjectFolder   = $paths.ProjectFolder
        GlobalFolder    = $paths.GlobalFolder
        GlobalFiles     = $globalFiles.FullName
        ProjectFiles    = $projectFiles.FullName
        CombinedContent = $combinedBuilder.ToString().Trim()
    }
}

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

Set-StrictMode -Version Latest

function ConvertTo-Slug {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$InputString
    )

    $slug = $InputString.Trim().ToLowerInvariant()
    $slug = [regex]::Replace($slug, '\s+', '-')
    $slug = [regex]::Replace($slug, '[^a-z0-9\-]', '-')
    $slug = [regex]::Replace($slug, '-{2,}', '-')
    $slug = $slug.Trim('-')

    if ([string]::IsNullOrWhiteSpace($slug)) {
        return 'chat'
    }

    return $slug
}

function Get-SessionTimestamp {
    [CmdletBinding()]
    param()

    (Get-Date).ToString('yyyy-MM-dd_HHmmss')
}

function New-SessionObject {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Metadata
    )

    [pscustomobject]@{
        PSTypeName         = 'Ollama.ProjectSession'
        Id                 = $Metadata.id
        Name               = $Metadata.name
        Title              = $Metadata.title
        ProjectName        = $Metadata.projectName
        ProjectFolder      = $Metadata.projectFolder
        GlobalFolder       = $Metadata.globalFolder
        SessionFolder      = $Metadata.sessionFolder
        SessionFile        = (Join-Path $Metadata.sessionFolder 'session.json')
        MessagesFile       = (Join-Path $Metadata.sessionFolder 'messages.jsonl')
        Model              = $Metadata.model
        Created            = $Metadata.created
        Updated            = $Metadata.updated
        ArtifactExtensions = @($Metadata.artifactExtensions)
        ArtifactFiles      = @($Metadata.artifactFiles)
        MessageCount       = $Metadata.messageCount
        RollingSummary     = $Metadata.rollingSummary
        Tags               = @($Metadata.tags)
    }
}

function Save-SessionMetadata {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject]$Session
    )

    $metadata = [ordered]@{
        id                 = $Session.Id
        name               = $Session.Name
        title              = $Session.Title
        projectName        = $Session.ProjectName
        projectFolder      = $Session.ProjectFolder
        globalFolder       = $Session.GlobalFolder
        sessionFolder      = $Session.SessionFolder
        model              = $Session.Model
        created            = $Session.Created
        updated            = $Session.Updated
        artifactExtensions = @($Session.ArtifactExtensions)
        artifactFiles      = @($Session.ArtifactFiles)
        messageCount       = $Session.MessageCount
        rollingSummary     = $Session.RollingSummary
        tags               = @($Session.Tags)
    }

    $json = $metadata | ConvertTo-Json -Depth 10
    Set-Content -LiteralPath $Session.SessionFile -Value $json -Encoding UTF8
}

function New-OllamaProjectSession {
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

    $paths = Resolve-AiContextPath -ProjectFolder $ProjectFolder -GlobalFolder $GlobalFolder

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

function Get-OllamaProjectSession {
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

        $paths = Resolve-AiContextPath -ProjectFolder $ProjectFolder
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

function Resolve-SessionObject {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline)]
        [psobject]$Session,

        [Parameter()]
        [string]$Path
    )

    if ($null -ne $Session) {
        if (-not $Session.PSObject.Properties['SessionFile']) {
            throw 'The provided session object is not valid. Expected a session object with SessionFile and MessagesFile properties.'
        }

        return $Session
    }

    if (-not [string]::IsNullOrWhiteSpace($Path)) {
        return Get-OllamaProjectSession -Path $Path
    }

    return Get-OllamaProjectSession
}

function Get-OllamaProjectSessionMessage {
    [CmdletBinding(DefaultParameterSetName = 'BySession')]
    param(
        [Parameter(ParameterSetName = 'BySession', ValueFromPipeline)]
        [psobject]$Session,

        [Parameter(ParameterSetName = 'ByPath')]
        [string]$Path,

        [Parameter()]
        [int]$Tail,

        [Parameter()]
        [switch]$Raw
    )

    $resolvedSession = if ($PSCmdlet.ParameterSetName -eq 'ByPath') {
        Resolve-SessionObject -Path $Path
    }
    else {
        Resolve-SessionObject -Session $Session
    }

    if (-not (Test-Path -LiteralPath $resolvedSession.MessagesFile -PathType Leaf)) {
        throw "Messages file not found: $($resolvedSession.MessagesFile)"
    }

    $lines = Get-Content -LiteralPath $resolvedSession.MessagesFile -ErrorAction Stop

    if ($Tail -gt 0) {
        $lines = $lines | Select-Object -Last $Tail
    }

    $messages = foreach ($line in $lines) {
        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }

        $message = $line | ConvertFrom-Json

        if ($Raw) {
            $message
        }
        else {
            [pscustomobject]@{
                PSTypeName = 'Ollama.ProjectSessionMessage'
                SessionId  = $resolvedSession.Id
                Role       = $message.role
                Timestamp  = $message.timestamp
                Content    = $message.content
            }
        }
    }

    return @($messages)
}

function Add-OllamaProjectSessionMessage {
    [CmdletBinding(DefaultParameterSetName = 'BySession')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'BySession', ValueFromPipeline)]
        [psobject]$Session,

        [Parameter(Mandatory, ParameterSetName = 'ByPath')]
        [string]$Path,

        [Parameter(Mandatory)]
        [ValidateSet('user', 'assistant', 'system')]
        [string]$Role,

        [Parameter(Mandatory)]
        [string]$Content
    )

    if ([string]::IsNullOrWhiteSpace($Content)) {
        throw 'Content cannot be null, empty, or whitespace.'
    }

    $resolvedSession = if ($PSCmdlet.ParameterSetName -eq 'ByPath') {
        Resolve-SessionObject -Path $Path
    }
    else {
        Resolve-SessionObject -Session $Session
    }

    if (-not (Test-Path -LiteralPath $resolvedSession.SessionFolder -PathType Container)) {
        throw "Session folder not found: $($resolvedSession.SessionFolder)"
    }

    if (-not (Test-Path -LiteralPath $resolvedSession.MessagesFile -PathType Leaf)) {
        $null = New-Item -Path $resolvedSession.MessagesFile -ItemType File -Force
    }

    $timestamp = (Get-Date).ToString('o')

    $message = [ordered]@{
        role      = $Role
        timestamp = $timestamp
        content   = $Content
    }

    $jsonLine = $message | ConvertTo-Json -Compress -Depth 5
    Add-Content -LiteralPath $resolvedSession.MessagesFile -Value $jsonLine -Encoding UTF8

    $resolvedSession.MessageCount = [int]$resolvedSession.MessageCount + 1
    $resolvedSession.Updated = $timestamp

    Save-SessionMetadata -Session $resolvedSession

    [pscustomobject]@{
        PSTypeName = 'Ollama.ProjectSessionMessage'
        SessionId  = $resolvedSession.Id
        Role       = $Role
        Timestamp  = $timestamp
        Content    = $Content
    }
}

function Send-OllamaProjectSessionMessage {
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
        [switch]$IncludeFileHeaders,

        [Parameter()]
        [switch]$RefreshArtifactFiles,

        [Parameter()]
        [int]$MessageTail = 50,

        [Parameter()]
        [int]$TimeoutSec = 300,

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

    $context = Get-AiProjectContext `
        -ProjectFolder $resolvedSession.ProjectFolder `
        -GlobalFolder $resolvedSession.GlobalFolder `
        -IncludeExtensions $resolvedSession.ArtifactExtensions `
        -IncludeFileHeaders:$IncludeFileHeaders

    if ($RefreshArtifactFiles) {
        $resolvedSession.ArtifactFiles = @($context.GlobalFiles + $context.ProjectFiles)
    }

    $systemMessageContent = @"
You are a project-aware engineering assistant operating against local documentation artifacts.

Treat the provided GLOBAL CONTEXT and PROJECT CONTEXT as authoritative for this session.

Rules:
- Do not invent project-specific facts not supported by the provided artifacts.
- If the artifact context is insufficient, say so explicitly.
- Respect documented constraints and decisions over general best practices.
- Prefer explicit tradeoffs over absolute recommendations.
- For architecture-impacting recommendations, call out whether a new ADR may be needed.
- Keep responses aligned to the user's intent: $Intent.
- Conversation history provides working context, but artifact documents remain the source of truth.

GLOBAL AND PROJECT CONTEXT
==========================
$($context.CombinedContent)
"@.Trim()

    $historyMessages = @()
    $sessionHistory = Get-OllamaProjectSessionMessage -Session $resolvedSession

    if ($MessageTail -gt 0) {
        $sessionHistory = @($sessionHistory | Select-Object -Last $MessageTail)
    }

    foreach ($message in $sessionHistory) {
        $historyMessages += @{
            role    = $message.Role
            content = $message.Content
        }
    }

    Add-OllamaProjectSessionMessage `
        -Session $resolvedSession `
        -Role user `
        -Content $Prompt | Out-Null

    $chatMessages = @(
        @{
            role    = 'system'
            content = $systemMessageContent
        }
    ) + $historyMessages + @(
        @{
            role    = 'user'
            content = $Prompt
        }
    )

    $body = @{
        model    = $Model
        stream   = $false
        messages = $chatMessages
    } | ConvertTo-Json -Depth 20

    try {
        $response = Invoke-RestMethod `
            -Uri $Endpoint `
            -Method Post `
            -ContentType 'application/json' `
            -Body $body `
            -TimeoutSec $TimeoutSec
    }
    catch {
        throw "Failed to call Ollama chat endpoint '$Endpoint'. $($_.Exception.Message)"
    }

    $assistantContent = $null

    if ($response.message -and $response.message.content) {
        $assistantContent = $response.message.content
    }
    elseif ($response.response) {
        $assistantContent = $response.response
    }

    if ([string]::IsNullOrWhiteSpace($assistantContent)) {
        throw 'Ollama did not return assistant message content.'
    }

    $assistantMessage = Add-OllamaProjectSessionMessage `
        -Session $resolvedSession `
        -Role assistant `
        -Content $assistantContent

    $resolvedSession.Updated = (Get-Date).ToString('o')

    if ($RefreshArtifactFiles) {
        Save-SessionMetadata -Session $resolvedSession
    }

    if ($RawResponse) {
        return [pscustomobject]@{
            PSTypeName       = 'Ollama.ProjectSessionChatResult'
            Session          = $resolvedSession
            Intent           = $Intent
            Model            = $Model
            Endpoint         = $Endpoint
            UserPrompt       = $Prompt
            AssistantMessage = $assistantMessage
            Messages         = $chatMessages
            OllamaResponse   = $response
        }
    }

    return [pscustomobject]@{
        PSTypeName       = 'Ollama.ProjectSessionChatResult'
        Session          = $resolvedSession
        Intent           = $Intent
        Model            = $Model
        UserPrompt       = $Prompt
        AssistantMessage = $assistantMessage
        Response         = $assistantContent
    }
}

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

function Start-OllamaProjectChat {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$ProjectFolder,

        [Parameter()]
        [string]$GlobalFolder,

        [Parameter()]
        [string]$Name,

        [Parameter()]
        [string]$Model = 'gpt-oss:20b',

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

    $paths = Resolve-AiContextPath -ProjectFolder $ProjectFolder -GlobalFolder $GlobalFolder
    $sessions = @(Get-OllamaProjectSessionList -ProjectFolder $paths.ProjectFolder)
    $session = $null

    Write-Host ''
    Write-Host "Project: $($paths.ProjectFolder)"
    Write-Host "Global : $($paths.GlobalFolder)"
    Write-Host ''

    if (-not [string]::IsNullOrWhiteSpace($Name)) {
        $session = Resolve-OllamaProjectSessionByName -Sessions $sessions -Name $Name

        if ($session) {
            Write-Host ''
            Write-Host "Resuming session: $($session.Title)" -ForegroundColor Cyan
        }
        else {
            Write-Host ''
            Write-Host "No session found matching '$Name'. Creating new session." -ForegroundColor Yellow

            $session = New-OllamaProjectSession `
                -Name $Name `
                -Model $Model `
                -ProjectFolder $paths.ProjectFolder `
                -GlobalFolder $paths.GlobalFolder
        }
    }

    if (-not $session) {
        if ($sessions.Count -gt 0) {
            $session = Select-OllamaProjectSession `
                -ProjectFolder $paths.ProjectFolder `
                -AllowNew

            if (-not $session) {
                $session = New-InteractiveOllamaProjectSession `
                    -ProjectFolder $paths.ProjectFolder `
                    -GlobalFolder $paths.GlobalFolder `
                    -Model $Model
            }
        }
        else {
            Write-Host 'No existing sessions found.'

            $session = New-InteractiveOllamaProjectSession `
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

        if ([string]::IsNullOrWhiteSpace($prompt)) {
            continue
        }

        if ($prompt -in @('exit', 'quit', ':q')) {
            Write-Host ''
            Write-Host 'Ending chat session.'
            break
        }

        try {
            $result = Send-OllamaProjectSessionMessage `
                -Session $session `
                -Prompt $prompt `
                -Intent $Intent `
                -Model $Model `
                -IncludeFileHeaders:$IncludeFileHeaders `
                -RefreshArtifactFiles:$RefreshArtifactFiles `
                -MessageTail $MessageTail `
                -TimeoutSec $TimeoutSec

            Write-Host ''
            Write-Host 'Assistant:' -ForegroundColor Green
            Write-Host $result.Response
            Write-Host ''

            $session = Get-OllamaProjectSession -Path $session.SessionFolder
        }
        catch {
            Write-Host ''
            Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
            Write-Host ''
        }
    }

    return $session
}

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

Export-ModuleMember -Function @(
    'Resolve-AiContextPath',
    'Get-AiContextFiles',
    'Get-AiContextContent',
    'Get-AiProjectContext',
    'New-OllamaProjectSession',
    'Get-OllamaProjectSession',
    'Get-OllamaProjectSessionList',
    'Select-OllamaProjectSession',
    'Resume-OllamaProjectSession',
    'Get-OllamaProjectSessionMessage',
    'Add-OllamaProjectSessionMessage',
    'Send-OllamaProjectSessionMessage',
    'Start-OllamaProjectChat'
)
