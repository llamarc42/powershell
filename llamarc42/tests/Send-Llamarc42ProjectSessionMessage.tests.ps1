BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' 'llamarc42.psd1') -Force

    $aiRoot      = Join-Path $TestDrive 'ai'
    $globalDir   = Join-Path $aiRoot 'global'
    $projectsDir = Join-Path $aiRoot 'projects'
    $projectDir  = Join-Path $projectsDir 'myproject'
    $sessionsDir = Join-Path $projectDir '.sessions'

    New-Item -ItemType Directory -Path $globalDir   -Force | Out-Null
    New-Item -ItemType Directory -Path $projectDir  -Force | Out-Null
    New-Item -ItemType Directory -Path $sessionsDir -Force | Out-Null

    # Minimal global and project context files (needed for Resolve-Llamarc42RetrievalContext inside send)
    Set-Content -Path (Join-Path $globalDir 'global-notes.md') -Value 'Global notes'
    Set-Content -Path (Join-Path $projectDir 'spec.md')        -Value 'Project spec'

    function New-TestSession {
        param([string]$SessionId = '2026-05-01_120000-sendtest')
        $sessionFolder = Join-Path $sessionsDir $SessionId
        if (Test-Path -LiteralPath $sessionFolder) {
            Remove-Item -LiteralPath $sessionFolder -Recurse -Force
        }
        New-Item -ItemType Directory -Path $sessionFolder -Force | Out-Null
        New-Item -ItemType File -Path (Join-Path $sessionFolder 'messages.jsonl') -Force | Out-Null

        $meta = [ordered]@{
            id                 = $SessionId
            name               = 'sendtest'
            title              = 'Send Test'
            projectName        = 'myproject'
            projectFolder      = $projectDir
            globalFolder       = $globalDir
            sessionFolder      = $sessionFolder
            model              = 'gpt-oss:20b'
            created            = '2026-05-01T12:00:00.0000000+00:00'
            updated            = '2026-05-01T12:00:00.0000000+00:00'
            artifactExtensions = @('.md')
            artifactFiles      = @()
            messageCount       = 0
            rollingSummary     = $null
            tags               = @()
        }
        $meta | ConvertTo-Json -Depth 5 |
            Set-Content -LiteralPath (Join-Path $sessionFolder 'session.json')

        return Get-Llamarc42ProjectSession -Path $sessionFolder
    }

    # Fake retrieval objects reused across mocks
    $fakePolicy = [pscustomobject]@{
        PSTypeName = 'Llamarc42.RetrievalPolicy'
        Path       = 'fake.yaml'
        Policy     = @{
            version   = 1
            global    = @{ always_include = @() }
            project   = @{ include = @(); folders = @{} }
            history   = $null
            retrieval = @{ strategies = @{ general = @{ include = @(); max_files = 0 }
                planning = @{ include = @(); max_files = 0 }
                coding   = @{ include = @(); max_files = 0 }
                review   = @{ include = @(); max_files = 0 } } }
        }
    }

    $fakeContext = [pscustomobject]@{
        PSTypeName    = 'Llamarc42.RetrievalContext'
        PolicyPath    = 'fake.yaml'
        Intent        = 'general'
        ProjectFolder = $projectDir
        GlobalFolder  = $globalDir
        Items         = @()
        Files         = @()
    }

    $fakeContent = [pscustomobject]@{
        PSTypeName = 'Llamarc42.RetrievalContextContent'
        Intent     = 'general'
        Files      = @()
        Content    = 'Mocked retrieval content'
        Items      = @()
    }

    $fakeOllamaResponse = [pscustomobject]@{
        model   = 'gpt-oss:20b'
        message = [pscustomobject]@{ role = 'assistant'; content = 'Mocked assistant reply' }
    }
}

AfterAll {
    Remove-Module llamarc42 -Force -ErrorAction SilentlyContinue
}

Describe 'Send-Llamarc42ProjectSessionMessage' {
    BeforeEach {
        $session = New-TestSession

        Mock Get-Llamarc42RetrievalPolicy        -ModuleName llamarc42 { $fakePolicy }
        Mock Resolve-Llamarc42RetrievalContext   -ModuleName llamarc42 { $fakeContext }
        Mock Get-RetrievalContextContent -ModuleName llamarc42 { $fakeContent }
        Mock Invoke-RestMethod           -ModuleName llamarc42 { $fakeOllamaResponse }
    }

    Context 'Successful send' {
        It 'returns an Llamarc42.ProjectSessionChatResult object' {
            $result = Send-Llamarc42ProjectSessionMessage -Session $session -Prompt 'Hello AI'
            $result.PSObject.TypeNames[0] | Should -Be 'Llamarc42.ProjectSessionChatResult'
        }

        It 'includes the UserPrompt in the result' {
            $result = Send-Llamarc42ProjectSessionMessage -Session $session -Prompt 'Hello AI'
            $result.UserPrompt | Should -Be 'Hello AI'
        }

        It 'includes the assistant response content' {
            $result = Send-Llamarc42ProjectSessionMessage -Session $session -Prompt 'Hello AI'
            $result.Response | Should -Be 'Mocked assistant reply'
        }

        It 'stores both the user and assistant messages in the transcript' {
            Send-Llamarc42ProjectSessionMessage -Session $session -Prompt 'Hello AI' | Out-Null
            $lines = @(Get-Content -LiteralPath $session.MessagesFile | Where-Object { $_ -ne '' })
            $lines.Count | Should -Be 2
            ($lines[0] | ConvertFrom-Json).role | Should -Be 'user'
            ($lines[1] | ConvertFrom-Json).role | Should -Be 'assistant'
        }

        It 'echoes the correct intent in the result' {
            $result = Send-Llamarc42ProjectSessionMessage -Session $session -Prompt 'Hello' -Intent planning
            $result.Intent | Should -Be 'planning'
        }

        It 'uses the session model when no model override is provided' {
            $result = Send-Llamarc42ProjectSessionMessage -Session $session -Prompt 'Hello'
            $result.Model | Should -Be 'gpt-oss:20b'
        }

        It 'uses the override model when -Model is supplied' {
            $result = Send-Llamarc42ProjectSessionMessage -Session $session -Prompt 'Hello' -Model 'llama3:8b'
            $result.Model | Should -Be 'llama3:8b'
        }
    }

    Context 'ConversationWindow in result' {
        It 'includes a ConversationWindow property in the result' {
            $result = Send-Llamarc42ProjectSessionMessage -Session $session -Prompt 'Hello AI'
            $result.PSObject.Properties.Name | Should -Contain 'ConversationWindow'
        }

        It 'ConversationWindow has the Llamarc42.ConversationWindow type' {
            $result = Send-Llamarc42ProjectSessionMessage -Session $session -Prompt 'Hello AI'
            $result.ConversationWindow.PSObject.TypeNames[0] | Should -Be 'Llamarc42.ConversationWindow'
        }
    }

    Context '-RawResponse switch' {
        It 'returns an OllamaResponse property instead of Response' {
            $result = Send-Llamarc42ProjectSessionMessage -Session $session -Prompt 'Hello' -RawResponse
            $result.PSObject.Properties.Name | Should -Contain 'OllamaResponse'
        }

        It 'does not return a Response property when -RawResponse is used' {
            $result = Send-Llamarc42ProjectSessionMessage -Session $session -Prompt 'Hello' -RawResponse
            $result.PSObject.Properties.Name | Should -Not -Contain 'Response'
        }
    }

    Context 'Validation errors' {
        It 'throws when Prompt is empty' {
            { Send-Llamarc42ProjectSessionMessage -Session $session -Prompt '' } | Should -Throw
        }

        It 'throws when Prompt is whitespace' {
            { Send-Llamarc42ProjectSessionMessage -Session $session -Prompt '   ' } | Should -Throw
        }
    }

    Context 'When Ollama returns empty content' {
        BeforeEach {
            Mock Invoke-RestMethod -ModuleName llamarc42 {
                [pscustomobject]@{ model = 'gpt-oss:20b'; message = [pscustomobject]@{ role = 'assistant'; content = '' } }
            }
        }

        It 'throws an error about missing assistant content' {
            { Send-Llamarc42ProjectSessionMessage -Session $session -Prompt 'Hello' } | Should -Throw
        }
    }

    Context 'ByPath parameter set' {
        It 'accepts a session folder path and returns a result' {
            $result = Send-Llamarc42ProjectSessionMessage -Path $session.SessionFolder -Prompt 'Hello via path'
            $result.PSObject.TypeNames[0] | Should -Be 'Llamarc42.ProjectSessionChatResult'
        }
    }

    Context 'Pipeline input' {
        It 'accepts a session object from the pipeline and returns a result' {
            $result = $session | Send-Llamarc42ProjectSessionMessage -Prompt 'Hello via pipeline'
            $result.PSObject.TypeNames[0] | Should -Be 'Llamarc42.ProjectSessionChatResult'
        }
    }

    Context '-InspectPrompt switch' {
        It 'returns a Llamarc42.PromptInspection object' {
            $result = Send-Llamarc42ProjectSessionMessage -Session $session -Prompt 'Hello' -InspectPrompt
            $result.PSObject.TypeNames[0] | Should -Be 'Llamarc42.PromptInspection'
        }

        It 'includes a Messages property in the inspection result' {
            $result = Send-Llamarc42ProjectSessionMessage -Session $session -Prompt 'Hello' -InspectPrompt
            $result.PSObject.Properties.Name | Should -Contain 'Messages'
        }

        It 'includes a SystemPrompt property in the inspection result' {
            $result = Send-Llamarc42ProjectSessionMessage -Session $session -Prompt 'Hello' -InspectPrompt
            $result.PSObject.Properties.Name | Should -Contain 'SystemPrompt'
        }

        It 'does not write messages to the transcript when -InspectPrompt is used' {
            Send-Llamarc42ProjectSessionMessage -Session $session -Prompt 'Hello' -InspectPrompt | Out-Null
            $lines = @(Get-Content -LiteralPath $session.MessagesFile | Where-Object { $_ -ne '' })
            $lines.Count | Should -Be 0
        }

        It 'does not call Ollama when -InspectPrompt is used' {
            Send-Llamarc42ProjectSessionMessage -Session $session -Prompt 'Hello' -InspectPrompt | Out-Null
            Should -Invoke Invoke-RestMethod -ModuleName llamarc42 -Times 0 -Exactly
        }
    }

    Context '-RefreshArtifactFiles switch' {
        BeforeEach {
            Mock Add-Llamarc42ProjectSessionMessage -ModuleName llamarc42 {
                [pscustomobject]@{ PSTypeName = 'Llamarc42.SessionMessage'; Role = $Role; Content = $Content }
            }
            Mock Save-SessionMetadata -ModuleName llamarc42 {}
        }

        It 'saves session metadata when -RefreshArtifactFiles is used' {
            Send-Llamarc42ProjectSessionMessage -Session $session -Prompt 'Hello' -RefreshArtifactFiles | Out-Null
            Should -Invoke Save-SessionMetadata -ModuleName llamarc42 -Times 1 -Exactly
        }

        It 'does not save session metadata when -RefreshArtifactFiles is omitted' {
            Send-Llamarc42ProjectSessionMessage -Session $session -Prompt 'Hello' | Out-Null
            Should -Invoke Save-SessionMetadata -ModuleName llamarc42 -Times 0 -Exactly
        }
    }
}
