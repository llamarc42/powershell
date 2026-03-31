<#
.SYNOPSIS
Gets a timestamp string for session identifiers.

.DESCRIPTION
Returns the current local time formatted for use in session ids and
folder names.

.EXAMPLE
Get-SessionTimestamp

.OUTPUTS
System.String
#>
function Get-SessionTimestamp {
    [CmdletBinding()]
    param()

    (Get-Date).ToString('yyyy-MM-dd_HHmmss')
}
