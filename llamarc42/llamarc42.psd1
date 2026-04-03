@{
    # Script module or binary module file associated with this manifest.
    RootModule = 'llamarc42.psm1'

    # Version number of this module.
    ModuleVersion = '1.0.3'

    # Supported PSEditions
    CompatiblePSEditions = @('Core', 'Desktop')

    # Unique identifier for this module
    GUID = '6d4d3c66-5d7d-4b9d-9e5d-2d8f2b7f4f11'

    # Author of this module
    Author = 'Jeffrey Patton'

    # Company or vendor of this module
    CompanyName = 'Patton-Tech'

    # Copyright statement for this module
    Copyright = '(c) Jeffrey Patton. All rights reserved.'

    # Description of the functionality provided by this module
    Description = 'llamarc42 - Loads global and project AI artifact context from a standard folder structure and sends grounded prompts to Ollama.'

    # Minimum version of the PowerShell engine required by this module
    PowerShellVersion = '7.0'

    # Functions to export from this module
    FunctionsToExport = @(
        'Add-Llamarc42ProjectSessionMessage',
        'Get-Llamarc42Content',
        'Get-Llamarc42Files',
        'Get-Llamarc42ProjectContext',
        'Get-Llamarc42ProjectContextDebug',
        'Get-Llamarc42ProjectSession',
        'Get-Llamarc42ProjectSessionConversationWindow',
        'Get-Llamarc42ProjectSessionList',
        'Get-Llamarc42ProjectSessionMessage',
        'Get-Llamarc42RetrievalPolicy',
        'New-Llamarc42ProjectSession',
        'Resolve-Llamarc42Path',
        'Resolve-Llamarc42RetrievalContext',
        'Resume-Llamarc42ProjectSession',
        'Select-Llamarc42ProjectSession',
        'Send-Llamarc42ProjectSessionMessage',
        'Start-Llamarc42ProjectChat',
        'Update-Llamarc42ProjectSessionSummary'
    )

    # Cmdlets to export from this module
    CmdletsToExport = @()

    # Variables to export from this module
    VariablesToExport = @()

    # Aliases to export from this module
    AliasesToExport = @()

    # Private data to pass to the module specified in RootModule
    PrivateData = @{
        PSData = @{
            Tags = @(
                'llamarc42',
                'Ollama',
                'AI',
                'RAG',
                'Documentation',
                'PowerShell'
            )
            LicenseUri = ''
            ProjectUri = ''
            IconUri = ''
            ReleaseNotes = 'Initial version with project/global context resolution and grounded Ollama invocation.'
        }
    }
}
