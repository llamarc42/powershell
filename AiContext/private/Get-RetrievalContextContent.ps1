<#
.SYNOPSIS
Builds a text payload from a retrieval context.

.DESCRIPTION
Reads each selected artifact in a retrieval context, optionally wraps
the file content with scope-aware headers, and returns a combined
content object for prompt construction.

.PARAMETER RetrievalContext
The retrieval context object whose selected items should be read.

.PARAMETER IncludeHeaders
Adds begin and end file markers that include artifact scope and relative
path information.

.EXAMPLE
Get-RetrievalContextContent -RetrievalContext $retrievalContext -IncludeHeaders

.OUTPUTS
Llamarc42.RetrievalContextContent
#>
function Get-RetrievalContextContent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject]$RetrievalContext,

        [Parameter()]
        [switch]$IncludeHeaders
    )

    $builder = New-Object System.Text.StringBuilder

    foreach ($item in $RetrievalContext.Items) {
        $content = Get-Content -LiteralPath $item.FullPath -Raw -ErrorAction Stop

        if ($IncludeHeaders) {
            [void]$builder.AppendLine("----- BEGIN FILE: [$($item.Scope)] $($item.RelativePath) -----")
            [void]$builder.AppendLine($content.Trim())
            [void]$builder.AppendLine("----- END FILE: [$($item.Scope)] $($item.RelativePath) -----")
            [void]$builder.AppendLine()
        }
        else {
            [void]$builder.AppendLine($content.Trim())
            [void]$builder.AppendLine()
        }
    }

    [pscustomobject]@{
        PSTypeName = 'Llamarc42.RetrievalContextContent'
        Intent     = $RetrievalContext.Intent
        Files      = @($RetrievalContext.Files)
        Content    = $builder.ToString().Trim()
        Items      = @($RetrievalContext.Items)
    }
}
