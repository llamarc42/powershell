<#
.SYNOPSIS
Resolves a session input into a session object.

.DESCRIPTION
Normalizes either an existing session object, a session folder path, or
the current default session into a full `Llamarc42.ProjectSession` object.

.PARAMETER Session
An existing session object.

.PARAMETER Path
The path to a session folder.

.EXAMPLE
Resolve-SessionObject -Path $sessionPath

.OUTPUTS
Llamarc42.ProjectSession
#>
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
        return Get-Llamarc42ProjectSession -Path $Path
    }

    return Get-Llamarc42ProjectSession
}
