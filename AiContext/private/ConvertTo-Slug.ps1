<#
.SYNOPSIS
Converts text to a slug.

.DESCRIPTION
Normalizes a string for session naming by lowercasing it, replacing
whitespace and unsupported characters with hyphens, collapsing repeated
hyphens, and returning `chat` when no slug content remains.

.PARAMETER InputString
The text to normalize.

.EXAMPLE
ConvertTo-Slug -InputString 'API Review'

.OUTPUTS
System.String
#>
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
