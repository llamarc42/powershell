<#
.SYNOPSIS
Loads the retrieval policy for the current AI workspace.

.DESCRIPTION
Resolves the retrieval policy path, loads the YAML file, validates the
required top-level sections, and returns the parsed policy object with
its source path.

.PARAMETER PolicyPath
The path to the retrieval policy YAML file. When omitted, the command
uses `tooling/config/retrieval.yaml` under the resolved AI root.

.PARAMETER ProjectFolder
The current project folder or any child path within the project.

.EXAMPLE
Get-RetrievalPolicy

.EXAMPLE
Get-RetrievalPolicy -PolicyPath './tooling/config/retrieval.yaml'

.OUTPUTS
Llamarc42.RetrievalPolicy
#>
function Get-RetrievalPolicy {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$PolicyPath,

        [Parameter()]
        [string]$ProjectFolder
    )

    if ([string]::IsNullOrWhiteSpace($ProjectFolder)) {
        $ProjectFolder = (Get-Location).Path
    }

    $paths = Resolve-AiContextPath -ProjectFolder $ProjectFolder

    if ([string]::IsNullOrWhiteSpace($PolicyPath)) {
        $PolicyPath = Join-Path $paths.AiRoot 'tooling/config/retrieval.yaml'
    }

    $resolvedPolicyPath = [System.IO.Path]::GetFullPath($PolicyPath)

    if (-not (Test-Path -LiteralPath $resolvedPolicyPath -PathType Leaf)) {
        throw "Retrieval policy file not found: $resolvedPolicyPath"
    }

    if (-not (Get-Command ConvertFrom-Yaml -ErrorAction SilentlyContinue)) {
        throw "ConvertFrom-Yaml is not available. Install the 'powershell-yaml' module."
    }

    try {
        $policy = Get-Content -LiteralPath $resolvedPolicyPath -Raw -ErrorAction Stop |
            ConvertFrom-Yaml
    }
    catch {
        throw "Failed to load retrieval policy from '$resolvedPolicyPath'. $($_.Exception.Message)"
    }

    if (-not $policy) {
        throw "Retrieval policy file '$resolvedPolicyPath' was empty or could not be parsed."
    }

    if (-not $policy.version) {
        throw "Retrieval policy is missing required property: version"
    }

    if (-not $policy.global) {
        throw "Retrieval policy is missing required section: global"
    }

    if (-not $policy.project) {
        throw "Retrieval policy is missing required section: project"
    }

    if (-not $policy.retrieval) {
        throw "Retrieval policy is missing required section: retrieval"
    }

    [pscustomobject]@{
        PSTypeName = 'Llamarc42.RetrievalPolicy'
        Path       = $resolvedPolicyPath
        Policy     = $policy
    }
}
