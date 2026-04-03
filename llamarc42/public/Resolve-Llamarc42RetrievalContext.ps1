<#
.SYNOPSIS
Resolves the retrieval context for an intent.

.DESCRIPTION
Loads the retrieval policy, gathers project and global artifact files,
selects matching items for the requested intent, and returns an ordered
retrieval context object containing the chosen artifacts.

.PARAMETER Intent
The retrieval intent whose strategy should be applied.

.PARAMETER ProjectFolder
The current project folder or any child path within the project.

.PARAMETER GlobalFolder
The global context folder. When omitted, the module resolves `ai/global`
from the current project structure.

.PARAMETER PolicyPath
The path to the retrieval policy YAML file.

.PARAMETER Policy
An already loaded retrieval policy object as returned by
`Get-Llamarc42RetrievalPolicy`.

.PARAMETER IncludeExtensions
The artifact file extensions to consider when scanning project and
global folders.

.EXAMPLE
Resolve-Llamarc42RetrievalContext -Intent planning -ProjectFolder .

.EXAMPLE
$policy = Get-Llamarc42RetrievalPolicy
Resolve-Llamarc42RetrievalContext -Intent review -Policy $policy

.OUTPUTS
Llamarc42.RetrievalContext
#>
function Resolve-Llamarc42RetrievalContext {
    [CmdletBinding()]
    param(
        [Parameter()]
        [ValidateSet('planning', 'coding', 'review', 'general')]
        [string]$Intent = 'general',

        [Parameter()]
        [string]$ProjectFolder,

        [Parameter()]
        [string]$GlobalFolder,

        [Parameter()]
        [string]$PolicyPath,

        [Parameter()]
        [psobject]$Policy,

        [Parameter()]
        [string[]]$IncludeExtensions = @('.md')
    )

    $paths = Resolve-Llamarc42Path -ProjectFolder $ProjectFolder -GlobalFolder $GlobalFolder

    if (-not $Policy) {
        $Policy = Get-Llamarc42RetrievalPolicy -PolicyPath $PolicyPath -ProjectFolder $paths.ProjectFolder
    }

    $policyObject = $Policy.Policy
    $strategy = $policyObject.retrieval.strategies.$Intent

    if (-not $strategy) {
        throw "Retrieval policy does not define a strategy for intent '$Intent'."
    }

    $globalFiles = @(Get-Llamarc42Files -Path $paths.GlobalFolder -IncludeExtensions $IncludeExtensions)
    $projectFiles = @(Get-Llamarc42Files -Path $paths.ProjectFolder -IncludeExtensions $IncludeExtensions)

    $selected = New-Object System.Collections.Generic.List[object]
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)

    $folderPriorityMap = @{
        high   = 1
        medium = 2
        low    = 3
    }

    function Add-SelectedArtifact {
        param(
            [Parameter(Mandatory)]
            [System.IO.FileInfo]$File,

            [Parameter(Mandatory)]
            [string]$RelativePath,

            [Parameter(Mandatory)]
            [string]$Scope,

            [Parameter(Mandatory)]
            [string]$Reason,

            [Parameter(Mandatory)]
            [int]$OrderRank,

            [Parameter()]
            [string]$Priority = 'default'
        )

        if ($seen.Add($File.FullName)) {
            $selected.Add([pscustomobject]@{
                PSTypeName   = 'Llamarc42.RetrievalArtifact'
                FullPath     = $File.FullName
                RelativePath = $RelativePath
                Scope        = $Scope
                Reason       = $Reason
                OrderRank    = $OrderRank
                Priority     = $Priority
            })
        }
    }

    # 1. Global always_include
    $globalAlwaysInclude = @($policyObject.global.always_include)
    $globalOrder = 0

    foreach ($name in $globalAlwaysInclude) {
        $globalOrder++

        $directPath = Join-Path $paths.GlobalFolder $name
        if (Test-Path -LiteralPath $directPath -PathType Leaf) {
            $file = Get-Item -LiteralPath $directPath
            $relativePath = Get-ArtifactRelativePath -RootPath $paths.GlobalFolder -FullPath $file.FullName

            Add-SelectedArtifact `
                -File $file `
                -RelativePath $relativePath `
                -Scope 'global' `
                -Reason 'global.always_include' `
                -OrderRank (100 + $globalOrder) `
                -Priority 'always'
            continue
        }

        $fallback = $globalFiles | Where-Object { $_.Name -eq $name } | Select-Object -First 1
        if ($fallback) {
            $relativePath = Get-ArtifactRelativePath -RootPath $paths.GlobalFolder -FullPath $fallback.FullName

            Add-SelectedArtifact `
                -File $fallback `
                -RelativePath $relativePath `
                -Scope 'global' `
                -Reason 'global.always_include' `
                -OrderRank (100 + $globalOrder) `
                -Priority 'always'
        }
    }

    # 2. Project include base files
    $projectInclude = @($policyObject.project.include)
    $projectOrder = 0

    foreach ($pattern in $projectInclude) {
        $projectOrder++

        $matches = @(Find-ArtifactMatches -Files $projectFiles -RootPath $paths.ProjectFolder -Pattern $pattern)

        foreach ($match in $matches) {
            Add-SelectedArtifact `
                -File $match.File `
                -RelativePath $match.RelativePath `
                -Scope 'project' `
                -Reason 'project.include' `
                -OrderRank (200 + $projectOrder) `
                -Priority 'base'
        }
    }

    # 3. Intent strategy includes
    $strategyPatterns = @($strategy.include)
    $strategyMatches = New-Object System.Collections.Generic.List[object]

    foreach ($pattern in $strategyPatterns) {
        $matches = @(Find-ArtifactMatches -Files $projectFiles -RootPath $paths.ProjectFolder -Pattern $pattern)

        foreach ($match in $matches) {
            $pathParts = $match.RelativePath -split '/'
            $folderName = $null
            $priorityName = 'default'

            if ($pathParts.Count -gt 1) {
                $folderName = $pathParts[0]

                if (
                    $policyObject.project.PSObject.Properties['folders'] -and
                    $policyObject.project.folders.PSObject.Properties[$folderName]
                ) {
                    $priorityName = [string]$policyObject.project.folders.PSObject.Properties[$folderName].Value.priority
                }
            }

            $priorityRank = if ($folderPriorityMap.ContainsKey($priorityName)) {
                $folderPriorityMap[$priorityName]
            }
            else {
                9
            }

            $strategyMatches.Add([pscustomobject]@{
                File         = $match.File
                RelativePath = $match.RelativePath
                Pattern      = $pattern
                Folder       = $folderName
                Priority     = $priorityName
                PriorityRank = $priorityRank
            })
        }
    }

    $dedupedStrategyMatches = $strategyMatches |
        Sort-Object PriorityRank, RelativePath -Unique

    $maxFiles = 0
    if ($strategy.PSObject.Properties.Name -contains 'max_files') {
        $maxFiles = [int]$strategy.max_files
    }

    if ($maxFiles -gt 0) {
        $dedupedStrategyMatches = @($dedupedStrategyMatches | Select-Object -First $maxFiles)
    }

    $strategyOrder = 0
    foreach ($match in $dedupedStrategyMatches) {
        $strategyOrder++

        Add-SelectedArtifact `
            -File $match.File `
            -RelativePath $match.RelativePath `
            -Scope 'project' `
            -Reason "retrieval.strategies.$Intent" `
            -OrderRank (300 + $match.PriorityRank * 10 + $strategyOrder) `
            -Priority $match.Priority
    }

    $orderedItems = @(
        $selected | Sort-Object OrderRank, RelativePath
    )

    [pscustomobject]@{
        PSTypeName    = 'Llamarc42.RetrievalContext'
        PolicyPath    = $Policy.Path
        Intent        = $Intent
        ProjectFolder = $paths.ProjectFolder
        GlobalFolder  = $paths.GlobalFolder
        Items         = $orderedItems
        Files         = @($orderedItems | ForEach-Object { $_.FullPath })
    }
}
