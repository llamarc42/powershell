<#
.SYNOPSIS
Gets retrieval and history debug information for a project context.

.DESCRIPTION
Resolves the project and global paths, loads the retrieval policy,
builds the retrieval context for the requested intent, and returns a
debug-friendly object that shows the selected files and any history
window settings defined by policy.

.PARAMETER Intent
The retrieval intent whose strategy should be evaluated.

.PARAMETER ProjectFolder
The current project folder or any child path within the project.

.PARAMETER GlobalFolder
The global context folder. When omitted, the module resolves `ai/global`
from the current project structure.

.PARAMETER PolicyPath
The path to the retrieval policy YAML file. When omitted, the default
retrieval policy for the AI workspace is used.

.PARAMETER IncludeExtensions
The artifact file extensions to consider when scanning project and
global folders.

.EXAMPLE
Get-OllamaProjectContextDebug -Intent review -ProjectFolder .

.EXAMPLE
Get-OllamaProjectContextDebug -Intent coding -PolicyPath './tooling/config/retrieval.yaml'

.OUTPUTS
Llamarc42.ContextDebug
#>
function Get-OllamaProjectContextDebug {
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
        [string[]]$IncludeExtensions = @('.md')
    )

    $paths = Resolve-AiContextPath -ProjectFolder $ProjectFolder -GlobalFolder $GlobalFolder

    $policy = Get-RetrievalPolicy `
        -PolicyPath $PolicyPath `
        -ProjectFolder $paths.ProjectFolder

    $retrievalContext = Resolve-RetrievalContext `
        -Intent $Intent `
        -ProjectFolder $paths.ProjectFolder `
        -GlobalFolder $paths.GlobalFolder `
        -Policy $policy `
        -IncludeExtensions $IncludeExtensions

    $historyMaxMessages = $null
    $historySummarizeAfter = $null

    if ($policy.Policy.history) {
        if ($policy.Policy.history.PSObject.Properties.Name -contains 'max_messages') {
            $historyMaxMessages = [int]$policy.Policy.history.max_messages
        }

        if ($policy.Policy.history.PSObject.Properties.Name -contains 'summarize_after') {
            $historySummarizeAfter = [int]$policy.Policy.history.summarize_after
        }
    }

    [pscustomobject]@{
        PSTypeName           = 'Llamarc42.ContextDebug'
        Intent               = $Intent
        ProjectFolder        = $paths.ProjectFolder
        GlobalFolder         = $paths.GlobalFolder
        PolicyPath           = $policy.Path
        HistoryMaxMessages   = $historyMaxMessages
        HistorySummarizeAfter= $historySummarizeAfter
        Files                = @($retrievalContext.Items | ForEach-Object {
            [pscustomobject]@{
                Scope        = $_.Scope
                RelativePath = $_.RelativePath
                Reason       = $_.Reason
                Priority     = $_.Priority
                OrderRank    = $_.OrderRank
                FullPath     = $_.FullPath
            }
        })
    }
}
