<#
.SYNOPSIS
Builds a single text payload from context files.

.DESCRIPTION
Reads the supplied files, optionally wraps each file with begin/end
headers, and returns a combined string that can be used as AI context.

.PARAMETER Files
The files to read and combine.

.PARAMETER RootPath
The root path used to calculate relative file names for headers.

.PARAMETER IncludeHeaders
Adds begin/end file markers for each file in the output.

.EXAMPLE
Get-AiContextContent -Files $files -RootPath $projectRoot -IncludeHeaders

.OUTPUTS
System.String
#>
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
