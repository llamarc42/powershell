@{
    # Script module or binary module file associated with this manifest.
    RootModule = 'AiContext.psm1'

    # Version number of this module.
    ModuleVersion = '1.0.0'

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
    Description = 'Loads global and project AI artifact context from a standard folder structure and sends grounded prompts to Ollama.'

    # Minimum version of the PowerShell engine required by this module
    PowerShellVersion = '7.0'

    # Functions to export from this module
    FunctionsToExport = @(
        'Add-OllamaProjectSessionMessage',
        'Get-AiContextContent',
        'Get-AiContextFiles',
        'Get-AiProjectContext',
        'Get-OllamaProjectContextDebug',
        'Get-OllamaProjectSession',
        'Get-OllamaProjectSessionConversationWindow',
        'Get-OllamaProjectSessionList',
        'Get-OllamaProjectSessionMessage',
        'Get-RetrievalPolicy',
        'New-OllamaProjectSession',
        'Resolve-AiContextPath',
        'Resolve-RetrievalContext',
        'Resume-OllamaProjectSession',
        'Select-OllamaProjectSession',
        'Send-OllamaProjectSessionMessage',
        'Start-OllamaProjectChat',
        'Update-OllamaProjectSessionSummary'
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
